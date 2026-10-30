import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    layerNamespacePlugin: "presentation-hub"
    popoutWidth: root.parentScreen ? Math.min(440, root.parentScreen.width - 24) : 440
    popoutHeight: root.parentScreen ? Math.min(550, root.parentScreen.height - 36) : 550

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
            property string mode: "window"
            property string mirrorSource: ""
            property var mirrorInfo: PluginService.getGlobalVar("presentationHub", "mirror", { state: "idle", message: "" })
            property string mirrorDependency: PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking")
            readonly property bool mirrorActive: mirrorInfo.state === "starting" || mirrorInfo.state === "running" || mirrorInfo.state === "stopping"

            Connections {
                target: PluginService
                function onGlobalVarChanged(id, name) {
                    if (id === "presentationHub" && name === "mirror")
                        panel.mirrorInfo = PluginService.getGlobalVar("presentationHub", "mirror", { state: "idle", message: "" })
                    if (id === "presentationHub" && name === "mirrorDependency")
                        panel.mirrorDependency = PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking")
                }
            }

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
                        if (!panel.outputs.some(o => o.name === panel.mirrorSource)) {
                            const laptop = panel.outputs.find(o => /^(edp|lvds|dsi)-/i.test(o.name))
                            panel.mirrorSource = laptop ? laptop.name : ""
                        }
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
            function mirrorCommand(action) {
                if (busy) return
                busy = true
                message = ""
                const args = action === "startMirror" ? ["dms", "ipc", "call", "presentationHub", action, mirrorSource, target] : ["dms", "ipc", "call", "presentationHub", action]
                Proc.runCommand("presentationHub.mirrorControl", args, (out, code) => {
                    panel.busy = false
                    if (code !== 0) panel.message = "Could not contact Presentation Hub. Check that the plugin is enabled."
                    else if (!out.trim().startsWith("Starting mirror") && !out.trim().startsWith("Stopping mirror")) panel.message = out.trim() || "Mirror request failed."
                })
            }
            function checkMirrorDependency() {
                Proc.runCommand("presentationHub.checkMirror", ["dms", "ipc", "call", "presentationHub", "checkMirror"], (out, code) => {
                    if (code !== 0) panel.message = "Could not check wl-mirror. Check that the plugin is enabled."
                })
            }
            Component.onCompleted: refresh()

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - panel.headerHeight - panel.detailsHeight - Theme.spacingXL
                Flickable {
                    id: contentViewport
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: contentColumn
                    width: contentViewport.width
                    spacing: Theme.spacingS
                    Row {
                        spacing: Theme.spacingXS
                        DButton { text: panel.mode === "window" ? "✓ Windows" : "Windows"; onClicked: panel.mode = "window" }
                        DButton { text: panel.mode === "mirror" ? "✓ Duplicate" : "Duplicate"; onClicked: { panel.mode = "mirror"; panel.refresh(); panel.checkMirrorDependency() } }
                    }
                    StyledText { text: "Destination display"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                    StyledText { visible: panel.outputs.length === 0; text: panel.busy ? "Loading displays…" : "No active displays found. Refresh to try again."; color: Theme.surfaceVariantText; wrapMode: Text.WordWrap; width: parent.width }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS
                        Repeater {
                            model: panel.outputs
                            DButton {
                                text: (panel.target === modelData.name ? "✓ " : "") + modelData.name
                                enabled: !panel.mirrorActive
                                onClicked: {
                                    panel.target = modelData.name
                                    pluginService.savePluginData("presentationHub", "presentationOutput", modelData.name)
                                }
                            }
                        }
                    }
                    StyledText { visible: panel.outputs.length === 1; text: "Only one display is connected. Connect another display and refresh."; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
                    StyledText { visible: panel.mode === "window"; text: "Window"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                    ListView {
                        id: windowList
                        readonly property real rowHeight: 55
                        readonly property int visibleRows: Math.min(count, Math.max(1, Math.floor((Math.min(190, Math.max(90, contentViewport.height * 0.35)) + spacing) / (rowHeight + spacing))))
                        visible: panel.mode === "window"
                        width: parent.width
                        height: visible && visibleRows > 0 ? visibleRows * rowHeight + (visibleRows - 1) * spacing : 0
                        clip: true
                        spacing: Theme.spacingXS
                        model: panel.windows
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        Accessible.role: Accessible.List
                        Accessible.name: "Open windows"
                        Keys.onReturnPressed: event => { if (currentItem) panel.selectedWindow = currentItem.modelData.id; event.accepted = true }
                        Keys.onEnterPressed: event => { if (currentItem) panel.selectedWindow = currentItem.modelData.id; event.accepted = true }
                        Keys.onSpacePressed: event => { if (currentItem) panel.selectedWindow = currentItem.modelData.id; event.accepted = true }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: windowList.rowHeight
                            radius: Theme.cornerRadius
                            color: panel.selectedWindow === modelData.id ? Theme.chipSurface : Theme.cardSurface
                            border.width: activeFocus || (windowList.activeFocus && windowList.currentIndex === index) ? 2 : 0
                            border.color: Theme.primary
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: (modelData.title || modelData.app_id || "Untitled window") + ", " + (modelData.output || "Unknown display")
                            Accessible.description: panel.selectedWindow === modelData.id ? "Selected" : "Select window"
                            Accessible.onPressAction: panel.selectedWindow = modelData.id
                            Keys.onReturnPressed: event => { panel.selectedWindow = modelData.id; event.accepted = true }
                            Keys.onEnterPressed: event => { panel.selectedWindow = modelData.id; event.accepted = true }
                            Keys.onSpacePressed: event => { panel.selectedWindow = modelData.id; event.accepted = true }
                            onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                            Column {
                                anchors.fill: parent; anchors.margins: Theme.spacingS
                                StyledText { width: parent.width; text: modelData.title || modelData.app_id || "Untitled window"; color: Theme.surfaceText; elide: Text.ElideRight }
                                StyledText { width: parent.width; text: (modelData.app_id || "Unknown app") + " · " + (modelData.output || "Unknown display"); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.selectedWindow = modelData.id }
                        }
                    }
                    StyledText {
                        visible: panel.mode === "window" && windowList.count > windowList.visibleRows
                        width: parent.width
                        text: "Scroll or use arrow keys to see more windows"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        visible: panel.mode === "window" && !panel.busy && windowList.count === 0
                        width: parent.width
                        text: "No windows found. Refresh to try again."
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                    StyledText { visible: panel.mode === "mirror"; text: "Source display"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                    Flow {
                        visible: panel.mode === "mirror"
                        width: parent.width
                        spacing: Theme.spacingXS
                        Repeater {
                            model: panel.outputs
                            DButton {
                                text: (panel.mirrorSource === modelData.name ? "✓ " : "") + modelData.name
                                enabled: !panel.mirrorActive
                                onClicked: panel.mirrorSource = modelData.name
                            }
                        }
                    }
                    StyledText {
                        visible: panel.mode === "mirror"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceVariantText
                        text: "Everything on the source display is visible to the audience, including notifications and presenter notes."
                    }
                    StyledText {
                        visible: panel.mode === "mirror" && panel.mirrorDependency !== "available"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: panel.mirrorDependency === "missing" ? Theme.error : Theme.surfaceVariantText
                        text: panel.mirrorDependency === "missing" ? "Duplicate needs wl-mirror. Install it with your package manager (Arch/CachyOS: sudo pacman -S wl-mirror), then recheck. Other features remain available." : "Checking for wl-mirror…"
                    }
                    DButton {
                        visible: panel.mode === "mirror" && panel.mirrorDependency === "missing"
                        text: "Recheck wl-mirror"
                        onClicked: panel.checkMirrorDependency()
                    }
                    StyledText {
                        visible: panel.mode === "mirror" && panel.mirrorInfo.message !== ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: panel.mirrorInfo.state === "error" ? Theme.error : Theme.surfaceText
                        text: panel.mirrorInfo.state === "running" ? "Mirroring " + panel.mirrorInfo.source + " → " + panel.mirrorInfo.target : panel.mirrorInfo.message
                    }
                    DButton {
                        visible: panel.mode === "mirror"
                        text: panel.mirrorActive ? "Stop mirroring" : "Start mirroring"
                        enabled: !panel.busy && (panel.mirrorActive ? panel.mirrorInfo.state !== "stopping" : panel.mirrorDependency === "available" && panel.mirrorSource !== "" && panel.target !== "" && panel.mirrorSource !== panel.target)
                        onClicked: panel.mirrorCommand(panel.mirrorActive ? "stopMirror" : "startMirror")
                    }
                    StyledText { visible: panel.message !== ""; text: panel.message; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceText }
                    Row {
                        visible: panel.mode === "window"
                        spacing: Theme.spacingS
                        DButton { text: "Refresh"; enabled: !panel.busy; onClicked: panel.refresh() }
                        DButton { text: "Move window"; enabled: !panel.busy && panel.selectedWindow !== null && panel.target !== "" && panel.outputs.length > 1; onClicked: panel.move() }
                    }
                }
                }
                Rectangle {
                    visible: contentViewport.contentHeight > contentViewport.height
                    width: 3
                    radius: width / 2
                    color: Theme.outlineVariant
                    anchors.right: parent.right
                    height: Math.max(20, contentViewport.height * contentViewport.height / contentViewport.contentHeight)
                    y: (contentViewport.height - height) * contentViewport.contentY / Math.max(1, contentViewport.contentHeight - contentViewport.height)
                }
            }
        }
    }
}
