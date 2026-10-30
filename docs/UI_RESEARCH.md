# Presentation Hub interface research

Research date: 2026-10-30. The current interface was reviewed from QML and prior user feedback; it has not been compared side-by-side in matched screenshots. External references below were inspected from their published screenshots, source, or documentation as noted.

## References

| Reference | Evidence inspected | Useful pattern | Limitation |
| --- | --- | --- | --- |
| [DMS Display Mirror](https://github.com/jfchenier/dms-display-mirror) | Repository screenshot and QML | Active source → destination and Stop are grouped above available displays; missing dependency is visible. | Older DMS API and different source/target flow; do not copy code or assume behavior is the same. |
| [Niri Display Settings](https://github.com/hthienloc/dms-niri-display-settings) | Repository screenshot and QML | Large icon-and-label actions and explicit monitor states; shortcuts are discoverable. | Repository is archived and controls output configuration, not presentation windows. |
| [Niri Screenshot](https://github.com/jfchenier/dms-niri-screenshot) | README and integration description | A compact bar entry, Control Center detail and settings have distinct roles. | The screenshot tool has different actions and lifecycle; Control Center integration remains a future option. |
| [Windows display modes](https://support.microsoft.com/en-us/windows/hardware/display-graphics/how-to-use-multiple-monitors-in-windows) | Product documentation | Name modes by what the audience sees: Duplicate, Extend, screen only. | Niri duplication uses a capture window, not native Windows-style mirroring. |

## Comparison and decisions

| Task | Presentation Hub before this pass | Decision |
| --- | --- | --- |
| Stop a running mirror | Status appeared at top but Stop was below the source list and could require scrolling. | Put Stop beside the live source → destination status at the top; retain a single Stop action. |
| Understand an invalid mirror choice | Start was disabled if source and audience were the same, without an explanation. | Explain that the two displays must differ. |
| Check missing `wl-mirror` | Duplicate already provides install guidance and a recheck control. | Keep dependency optional and system-managed. |
| Select a window | Window list and overall panel use separate scroll areas, verified by the user. | Preserve this; avoid another nested list redesign without a matching runtime comparison. |
| Quick access outside the bar | Bar widget indicates when Duplicate is running. | A Control Center tile is a future idea, not part of this change. |
| Keyboard and compact layouts | Focus behavior and controls exist, but end-to-end keyboard, small screens and more than two displays have not been verified. | Keep as open validation; do not claim parity. |

The intermittent report that Start/Stop needed two clicks was not reproduced during the earlier instrumented run. A later user report and logs should be gathered if it recurs; this research pass does not claim to fix it.

## Session layout update (2026-10-31)

- [Zoom screen sharing](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060596) separates choosing what to share from the controls used during sharing; its presenter toolbar keeps sharing controls and preview accessible. Presentation Hub applies that distinction through Windows / Duplicate setup and an Audience Controls tab.
- [PowerPoint Presenter View](https://support.microsoft.com/en-us/powerpoint/training/start-the-presentation-and-see-your-notes-in-presenter-view) keeps the audience and presenter roles explicit and makes display management discoverable. Presentation Hub uses an explicit audience display and manual return; it does not infer or auto-swap an ambiguous pair.
- [DMS Display Mirror](https://github.com/jfchenier/dms-display-mirror) keeps active mirror state and stopping discoverable; the session's End action is retained in the status row above the tab content.

This is a QML implementation informed by the references, not a claim of visual parity. User verification is still needed for compact screens, keyboard navigation, and the new session states.
