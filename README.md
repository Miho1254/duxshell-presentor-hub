# Presentation Hub

A Niri-first tool for moving windows to an external display. The core is a C++/Qt program independent of DMS; the DMS frontend is a QML widget.

## Requirements

- A running Niri session
- Qt 6 Core and Network at runtime
- CMake 3.20+, a C++17 compiler and Qt 6 development packages to build
- DMS 2.0 or newer for the widget

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

The build creates `presentation-hub/bin/presentation-hub-core`, which is ignored by Git and used by the widget. Build for each target machine before using the plugin. The binary needs compatible Qt runtime libraries.

## Core CLI

The executable uses `$NIRI_SOCKET` directly and prints JSON to stdout and errors to stderr:

```sh
presentation-hub/bin/presentation-hub-core snapshot
presentation-hub/bin/presentation-hub-core move --window 42 --output HDMI-A-1
```

`snapshot` lists active outputs and windows. `move` verifies that the selected window and output exist before requesting the move and checks the resulting output afterward. State can change between queries; failure to confirm does not guarantee that the move did not occur. The snapshot uses separate IPC requests and is not atomic.

## DMS widget

After building, link `presentation-hub` into `~/.config/dms/plugins/`, enable Presentation Hub in DMS Settings → Plugins, and add its widget to the bar. Choose a destination and window, then select **Move window**. Refresh after connecting or disconnecting a display.

The background component checks active outputs approximately every three seconds. When an external output appears after the initial scan, a DMS dialog asks whether to use it for presentations, including when Do Not Disturb is enabled. Choosing **Use for presentations** remembers the output name; **Not now** makes no change. The widget selects the remembered output when it is available, and selecting a different output in the widget updates that preference. The prompt does not move windows or change display configuration. At startup, displays already connected are treated as the baseline and do not trigger a prompt. A disconnect shorter than the polling interval may be missed. Internal display detection uses connector-name prefixes and may not recognize every device.

The same periodic snapshot checks new or changed windows. With a connected presentation display selected, the plugin can suggest moving a likely presentation window; it never moves one without confirmation. The title-based rule is limited to LibreOffice slideshow windows and remains experimental; other applications may be missed. Windows already recognized at startup are not suggested; dismissing suppresses a suggestion while it remains a candidate.

The DMS frontend watches Wayland fullscreen state for known browsers and offers to move fullscreen browser windows, including videos and other non-presentation content. It waits for fullscreen to remain active for about half a second before offering. Canva and other browser presentations are not suggested based on titles alone. The frontend joins Wayland windows to Niri by exact app ID and title and skips ambiguous matches; this detection is currently DMS-specific and is not provided by the standalone core. Niri's windowed fullscreen may also trigger it. A window already fullscreen at plugin startup is treated as the baseline. Dismissing the prompt suppresses another suggestion until the window exits fullscreen.

Additional browser app IDs can be entered in Presentation Hub's plugin settings as a comma-separated list. Custom IDs are matched exactly, case-insensitively. Use `niri msg windows` to find an application's ID.

## Verification

```sh
sh tests/smoke.sh
ctest --test-dir build --output-on-failure
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The smoke checks require `jq` and a running Niri session. The Python integration tests use a disposable fake Niri socket and do not require a running compositor. The DMS widget has been tested with Firefox and Canva on Niri 26.04; other browsers and LibreOffice still require live verification.

References: [DMS composite example](https://github.com/duxlabs-dev/dux-shell/tree/v2.0.0/quickshell/PLUGINS/ExampleCompositePlugin), [Niri Display Settings](https://github.com/hthienloc/dms-niri-display-settings), [Niri IPC](https://github.com/niri-wm/niri/blob/main/docs/wiki/IPC.md). Original reference copies remain in Git history.

Next: validate and refine the detection rules against real Canva and LibreOffice presentation sessions.
