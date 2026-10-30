# Presentation Hub

A DMS plugin for presenting on an external display in Niri. Choose a window or duplicate a display, then control the audience screen from one place. A small C++/Qt core talks to Niri independently of DMS; the QML frontend provides the widget and background watcher.

> **Project status:** early development. Live audience preview is temporarily disabled after a reported DMS/Quickshell crash. A later DMS crash also occurred with preview disabled; the cause remains under investigation. See [Known limitations](#known-limitations).

## Features

- Move a selected window to an audience display or back to a built-in display.
- Start a presentation session with a window or a duplicated display, optional Do Not Disturb, and a Wayland idle-inhibition request.
- Identify an output and temporarily cover it with black or a custom image.
- Get an optional prompt when a new display is connected or a browser goes fullscreen. Suggestions never move a window without confirmation.
- Use the Niri core from the command line without DMS.

## Requirements

- A running [Niri](https://github.com/niri-wm/niri) session.
- [DMS](https://github.com/duxlabs-dev/dux-shell) 2.0 or newer for the plugin.
- Qt 6 Core and Network at runtime; Qt 6 development packages, CMake 3.20+ and a C++17 compiler to build.
- `wl-mirror` on the DMS session's `PATH` **only for Duplicate**. The plugin neither bundles nor installs it; install and update it with your system package manager. For Arch Linux and CachyOS: `sudo pacman -S wl-mirror`.
- `jq` for the live smoke test. Python 3 is needed only for integration tests.

## Installation

Clone this repository and build on the target machine:

```sh
git clone https://github.com/Miho1254/duxshell-presentor-hub.git
cd duxshell-presentor-hub
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

The build places `presentation-hub-core` in `presentation-hub/bin/`. This binary is generated locally and is not tracked by Git. It requires compatible Qt runtime libraries.

Link the plugin directory, then enable it under **DMS Settings → Plugins** and add Presentation Hub to the bar:

```sh
mkdir -p "$HOME/.config/dms/plugins"
ln -s "$PWD/presentation-hub" "$HOME/.config/dms/plugins/presentation-hub"
```

If the destination already exists, inspect it before replacing it. After source changes, rebuild the core when needed and reload the plugin through DMS. Reloading ends any active presentation session and plugin-owned mirror.

## Using the widget

1. Select the **audience display**.
2. In **Windows**, select a window; in **Duplicate**, select the source display. Duplicate needs two different displays and `wl-mirror`.
3. Optionally select **Do Not Disturb**, then choose **Start presentation**. Use **End** to end the session.
4. Under **Controls**, identify or cover the audience display. Choose an image for the cover, or use black. **Resume audience display** removes the cover.

The widget also offers manual window moves and mirroring without starting a session. The last moved window can be returned while it is still on its destination and its original display remains connected. A presentation window stays on the audience display at the end of a session until you move it back.

The session requests Wayland idle inhibition. This depends on compositor and idle-daemon behavior and does not prevent manual lock or suspend. Ending a session stops the cover and mirror it owns; existing ones are not claimed. If the plugin enabled Do Not Disturb, it switches it off at the end only if the DMS state has not subsequently changed. External changes to the DND state or timer relinquish ownership. Identical external requests that emit no state-change signal cannot be detected. If DND was already on, the plugin leaves it alone. Disconnecting the audience display ends the session; session state is not restored after a plugin reload. An unexpected DMS crash may prevent cleanup, so check Do Not Disturb manually after a crash.

### Suggestions

After the initial scan, the watcher checks active outputs about every three seconds and asks whether a newly detected external display should be used for presentations. Displays already present at startup are the baseline; a disconnection shorter than the polling interval can be missed.

The plugin can also suggest moving a fullscreen browser window, including videos. In plugin settings choose **Ask for browser fullscreen**, **Only during a session**, or **Manual only**. Manual only also disables experimental LibreOffice slideshow title suggestions. Browser IDs can be extended, allowed or excluded using comma-separated exact app IDs; find an ID with `niri msg windows`. The frontend matches Wayland toplevels to Niri windows by app ID and title and skips ambiguous matches. Suggestions are suppressed during duplication. At startup, already fullscreen windows are treated as the baseline.

## Standalone core

The core uses `$NIRI_SOCKET`, writes JSON to stdout, and reports errors to stderr:

```sh
presentation-hub/bin/presentation-hub-core snapshot
presentation-hub/bin/presentation-hub-core move --window 42 --output HDMI-A-1
```

A snapshot combines multiple IPC queries and is not atomic. A move validates the window and output before requesting the action and queries again to confirm the resulting output. A failed confirmation does not prove that the move did not happen.

## Known limitations

- **Live audience preview is disabled.** A DMS/Quickshell crash was reported when it was opened, and a second crash occurred with preview disabled; the available stack traces do not establish the root cause or which component is responsible. This does not disable window moving, Duplicate, or the cover.
- Duplicate uses a fullscreen `wl-mirror` window rather than native display cloning. Resolution and aspect ratio can differ, and everything on the source—including notifications and presenter notes—can be visible to the audience. A running process alone does not guarantee a successful capture. The plugin discards `wl-mirror` stderr to avoid unbounded buffering during long sessions; run `wl-mirror` directly in a terminal when diagnosing capture failures.
- The cover is a Wayland overlay, not a hardware blank or privacy guarantee. Other overlay or lock surfaces may appear above it. A missing or unreadable cover image leaves a black screen.
- Automatic presenter/audience window pairing and swapping are not implemented. Built-in-display detection relies on connector prefixes and may not match every device.
- Firefox/Canva and the basic two-display flows have been tested on Niri 26.04. Other browsers, LibreOffice, compact screens, keyboard navigation and multi-display edge cases need more testing.

## Development and tests

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
sh tests/smoke.sh
```

The smoke test requires a running Niri session. The Python integration suite uses a disposable fake Niri socket. Set `PRESENTATION_HUB_CORE` to test an alternative core binary, such as a sanitizer build. The standalone core lives in `core/`; the composite plugin lives in `presentation-hub/`. See [interface research](docs/UI_RESEARCH.md) for design references and the [resource audit](docs/PERFORMANCE.md) for measurements and their limits.

Please include the DMS, Niri and Quickshell versions, relevant logs, and steps to reproduce when reporting an issue. Avoid including private window titles, images or other sensitive data in logs.

## License and acknowledgments

Presentation Hub is licensed under [GNU GPL version 3 only](LICENSE). The initial repository also included MIT-licensed reference material; its original notices are preserved in [third-party notices](THIRD_PARTY_NOTICES.md) and Git history.

Thanks to the [DMS composite plugin example](https://github.com/duxlabs-dev/dux-shell/tree/v2.0.0/quickshell/PLUGINS/ExampleCompositePlugin), [Niri Display Settings](https://github.com/hthienloc/dms-niri-display-settings), [DMS Display Mirror](https://github.com/jfchenier/dms-display-mirror), and the [Niri IPC documentation](https://github.com/niri-wm/niri/blob/main/docs/wiki/IPC.md) for examples and design references.
