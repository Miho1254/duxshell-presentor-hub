# Performance and resource audit

These are point-in-time observations, not guarantees or a substitute for a long-duration leak investigation.

## Environment and method

**Historical measurements:** The plugin has since moved to DMS NiriService events and no longer runs the C++ core for plugin operations. The figures below describe the earlier polling implementation and do not measure the current version.

The audit on 2026-10-31 used an Intel Core i5-12450HX (12 logical CPUs), Niri 26.04, DMS 2.0.0, Quickshell 0.3.2, Qt 6.12.0, and two connected displays. A desktop session and other DMS plugins were active. CPU percentages below are relative to **one logical CPU**; they are not percentages of total machine capacity. Samples used Linux `/proc/<pid>/stat` CPU time and `/proc/<pid>/smaps_rollup` PSS and private dirty memory. Interactive workloads and graphics activity were not controlled.

- The C++ core was compiled with AddressSanitizer, UndefinedBehaviorSanitizer and LeakSanitizer. Six fake-IPC integration tests passed, including invalid JSON and an oversized response. An additional 120 short-lived snapshot/move runs on a fake Niri socket produced no sanitizer diagnostics. This covers the core process, not the DMS QML engine or third-party libraries as a whole.
- One hundred real Niri `snapshot` executions took a median of 8.19 ms and p95 of 12.73 ms. Their combined child user/system CPU averaged 8.26 ms per invocation, roughly **0.28% of one CPU** at one execution every three seconds. This estimate excludes Niri's processing, DMS parsing and event-triggered extra polls. Peak child RSS observed by `getrusage` was 19,308 KiB.
- For the DMS process with Presentation Hub enabled, 267 seconds of samples before a crash showed CPU averaging 11.52% of one CPU, PSS increasing from 492.88 to 524.15 MiB, and private dirty memory from 400.63 to 422.30 MiB. DMS hosts other plugins and the desktop was in use, so these changes cannot be attributed to this plugin or classified as a leak from this sample alone. The measurement ended early when DMS crashed.
- A short enabled / disabled / re-enabled comparison recorded approximately 42 seconds per stage: DMS CPU was 6.98% / 7.29% / 7.95% of one CPU. PSS changed by -8.30 / +0.25 / -2.82 MiB respectively. The fluctuation and concurrent desktop activity make the difference unsuitable as a precise estimate of plugin overhead or proof of leak freedom.

- During a 30-second Duplicate run, a 21-second post-warm-up sample of `wl-mirror` used 2.8% of one CPU; PSS and private dirty memory remained at 31.01 MiB and 13.62 MiB respectively. This short test does not establish long-session behavior, and does not include compositor capture/rendering cost. The plugin stopped the process afterward.

The current plugin obtains Niri state from DMS events and does not launch the standalone core for snapshots. It discards `wl-mirror` stderr instead of retaining an unlimited stream in a `StdioCollector`, and removes stale or duplicate pending prompt entries as windows and outputs change.

## Unresolved crash and limits

The desktop reported two DMS/Quickshell SIGSEGV crashes during this development session. The first was reported immediately after opening live preview; the second occurred with live preview disabled while the user was interacting with the desktop/widget. The first stack stopped in Qt Wayland; the second in QML garbage collection. Niri remained running. These observations do not establish a root cause. Live preview remains disabled, and further isolation on a disposable session is needed before claiming it or the widget stable.

Neither the short A/B measurement nor the sanitized short-lived core tests establish the absence of a long-running DMS/Qt memory leak or increasing CPU use. A longer isolated run, separate per-plugin profiling, active presentation and repeated hotplug testing are still needed. No crash was intentionally reproduced on the user's desktop.

## Follow-up investigation (2026-10-31)

The two original Quickshell core dumps were still available. GDB reproduced the recorded
stacks: the first stops in Qt Wayland event dispatch, and the second in the QML JavaScript
garbage collector. Debug information for the relevant Qt libraries was unavailable;
some unrelated installed libraries no longer matched the core-file build IDs. Neither
stack identifies a Presentation Hub QML line or establishes which component caused the
crash.

A short follow-up used a separate DMS instance inside Niri's nested X11 backend on Xvfb,
with software rendering, a private D-Bus session, an inaccessible system bus, a temporary
home/config/runtime directory, and one virtual output. The DMS version and plugin source
were the installed DMS 2.0.0 and the current plugin under test. With the plugin disabled,
15 settings open/close request pairs completed without DMS exiting. With the plugin
enabled, 25 widget open/close request pairs completed in one run; a separate run completed
20 pairs with clicks on the Windows, Duplicate, and Controls tab positions between each
pair. Screenshots confirmed that the widget and Duplicate tab were rendered. The DMS
process did not exit during these short runs. DMS emitted unrelated warnings in the
isolated environment, including errors in a settings callback with the plugin disabled.

These runs used different actions for the enabled and disabled cases, a single virtual
display, and no hardware screencopy, hotplug, or live preview. They do not reproduce the
original two-display workload and cannot establish crash freedom or rule out the plugin.
The crash cause remains unknown, and live preview remains disabled.
