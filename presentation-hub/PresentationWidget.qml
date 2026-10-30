import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    layerNamespacePlugin: "presentation-hub"
    popoutWidth: 440
    popoutHeight: 550

    horizontalBarPill: Component {
        DIcon { name: "present_to_all"; size: root.iconSize }
    }
    verticalBarPill: horizontalBarPill

    popoutContent: Component {
        PopoutComponent {
            id: panel
            headerText: "Presentation Hub"
            detailsText: "Move a window to another display"
            property var outputs: []
            property var windows: []
            property string target: ""
            property var selectedWindow: null
            property string message: ""
            property bool busy: false

            // Resolve relative to this QML file so the plugin works from a symlink too.
            readonly property string corePath: decodeURIComponent(Qt.resolvedUrl("bin/presentation-hub-core").toString().replace(/^file:\/\//, ""))

            function refresh() {
                busy = true
                message = ""
                Proc.runCommand("presentationHub.snapshot", [corePath, "snapshot"], (out, code) => {
                    panel.busy = false
                    if (code !== 0) { panel.message = "Cannot read Niri state. Check the Niri session and build the core, then refresh."; return }
                    try {
                        const data = JSON.parse(out)
                        panel.outputs = data.outputs
                        panel.windows = data.windows
                        if (!panel.outputs.some(o => o.name === panel.target)) {
                            const preferred = pluginService.loadPluginData("presentationHub", "presentationOutput", "")
                            panel.target = panel.outputs.some(o => o.name === preferred) ? preferred : ""
                        }
                        if (panel.selectedWindow !== null && !panel.windows.some(w => w.id === panel.selectedWindow)) panel.selectedWindow = null
                    } catch (e) { panel.message = "Could not read display and window information." }
                })
            }
            function move() {
                if (selectedWindow === null || !target || busy) return
                busy = true
                Proc.runCommand("presentationHub.move", [corePath, "move", "--window", String(selectedWindow), "--output", target], (out, code) => {
                    panel.busy = false
                    if (code !== 0) { panel.message = "Could not move the window. It or the display may have disappeared."; return }
                    panel.message = "Window moved to " + panel.target + "."
                    panel.selectedWindow = null
                })
            }
            Component.onCompleted: refresh()

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - panel.headerHeight - panel.detailsHeight - Theme.spacingXL
                Column {
                    anchors.fill: parent
                    spacing: Theme.spacingS
                    StyledText { text: "Destination display"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                    StyledText { visible: panel.outputs.length === 0; text: panel.busy ? "Loading displays…" : "No active displays found. Refresh to try again."; color: Theme.surfaceVariantText; wrapMode: Text.WordWrap; width: parent.width }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS
                        Repeater {
                            model: panel.outputs
                            DButton {
                                text: (panel.target === modelData.name ? "✓ " : "") + modelData.name
                                onClicked: {
                                    panel.target = modelData.name
                                    pluginService.savePluginData("presentationHub", "presentationOutput", modelData.name)
                                }
                            }
                        }
                    }
                    StyledText { visible: panel.outputs.length === 1; text: "Only one display is connected. Connect another display and refresh."; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
                    StyledText { text: "Window"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                    ListView {
                        width: parent.width
                        height: Math.max(100, parent.height - 240)
                        clip: true
                        spacing: Theme.spacingXS
                        model: panel.windows
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 55
                            radius: Theme.cornerRadius
                            color: panel.selectedWindow === modelData.id ? Theme.chipSurface : Theme.cardSurface
                            Column {
                                anchors.fill: parent; anchors.margins: Theme.spacingS
                                StyledText { width: parent.width; text: modelData.title || modelData.app_id || "Untitled window"; color: Theme.surfaceText; elide: Text.ElideRight }
                                StyledText { width: parent.width; text: (modelData.app_id || "Unknown app") + " · " + (modelData.output || "Unknown display"); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.selectedWindow = modelData.id }
                        }
                    }
                    StyledText { visible: panel.message !== ""; text: panel.message; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceText }
                    Row {
                        spacing: Theme.spacingS
                        DButton { text: "Refresh"; enabled: !panel.busy; onClicked: panel.refresh() }
                        DButton { text: "Move window"; enabled: !panel.busy && panel.selectedWindow !== null && panel.target !== "" && panel.outputs.length > 1; onClicked: panel.move() }
                    }
                }
            }
        }
    }
}
