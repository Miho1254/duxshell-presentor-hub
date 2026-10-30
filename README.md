# DMS + Niri presentation plugin references

The agreed initial scope is:

1. Manually select a window and move it to an external display.
2. Suggest moving a likely presentation window to the external display and wait for the user to confirm.

English is the default language for project documentation and the plugin interface. Other languages can be added later through localization.

## Official DMS template

[`templates/dux-composite-v2`](templates/dux-composite-v2/) is an unchanged copy of `quickshell/PLUGINS/ExampleCompositePlugin` from [Dux Shell v2.0.0](https://github.com/duxlabs-dev/dux-shell/tree/v2.0.0/quickshell/PLUGINS/ExampleCompositePlugin), commit `9b413296b16721f7679fb62e624cb1ed2433fa58`. The repository's MIT license and `THEME_REFERENCE.md` from the same version have been added.

The example includes a daemon, a bar widget with a popout, a desktop widget, and settings. It is an upstream example, not a presentation plugin: its daemon watches wallpaper changes and its widgets have unrelated behavior. For implementation, use the daemon, widget, and settings structure as a starting point and remove unrelated example features.

## Niri reference

[`references/niri-display-settings`](references/niri-display-settings/) is a copy of [Niri Display Settings](https://github.com/hthienloc/dms-niri-display-settings), commit `c8aa9c4`, with its MIT license included. The upstream repository is archived. It is a reference for composite plugin structure, display management UI, and Niri commands, not an official Dux template or a guarantee of compatibility with DMS 2.0.0. Check individual APIs before reuse.

Neither copy has been installed, enabled, or tested in DMS. See the [official plugin development guide](https://duxlabs.dev/docs/dms/plugin-development).

## Manual window mover prototype

[`presentation-hub`](presentation-hub/) is the first DMS 2.0 / Niri prototype. It lists active outputs and windows, then moves the chosen window to the chosen output using `niri msg action move-window-to-monitor --id`. It does not change display configuration or automatically detect presentations. Refresh the list after connecting or disconnecting a display. Window and output state can change between selection and the move; failures are shown in the popout.

Niri exposes windows, workspaces, and outputs over IPC. A window belongs to a workspace; its workspace identifies its current output. See the [Niri IPC guide](https://github.com/niri-wm/niri/blob/main/docs/wiki/IPC.md) and [workspace guide](https://github.com/niri-wm/niri/wiki/Workspaces).

To try the prototype, link the `presentation-hub` directory into `~/.config/dms/plugins/`, scan and enable it in DMS Settings → Plugins, then add its widget to the bar. Manual window movement through the widget was confirmed with an external display on DMS 2.0.0 and Niri 26.04.
