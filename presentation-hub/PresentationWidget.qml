// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modals.FileBrowser
import qs.Services

PluginComponent {
    id: root

    property var barSessionInfo: PluginService.getGlobalVar("presentationHub", "session", {
        "active": false
    })
    property var barMirrorInfo: PluginService.getGlobalVar("presentationHub", "mirror", {
        "state": "idle"
    })
    readonly property bool barMirrorActive: barMirrorInfo.state === "starting" || barMirrorInfo.state === "running" || barMirrorInfo.state === "stopping"

    function candidate(appId, title) {
        const app = String(appId || '').toLowerCase();
        const text = String(title || '').toLowerCase();
        if (['presenter', 'người thuyết trình', 'speaker notes', 'presenter notes'].some((x) => {
            return text.includes(x);
        }))
            return false;

        return (app.includes('impress') || app.includes('libreoffice')) && (text.includes('slide show') || text.includes('slideshow'));
    }

    function niriSnapshot(service) {
        const outputs = Quickshell.screens.map((screen) => {
            return Object.assign({
            }, (service.outputs || {
            })[screen.name] || {
            }, {
                "name": screen.name
            });
        }).sort((a, b) => {
            return a.name.localeCompare(b.name);
        });
        const workspaces = service.workspaces || {
        };
        const windows = (service.windows || []).map((w) => {
            return Object.assign({
            }, w, {
                "output": workspaces[w.workspace_id] ? workspaces[w.workspace_id].output : null,
                "presentation_candidate": candidate(w.app_id, w.title)
            });
        });
        return {
            "outputs": outputs,
            "windows": windows
        };
    }

    layerNamespacePlugin: "presentation-hub"
    // Keep breathing room around the panel on smaller or scaled displays.
    readonly property real desiredPopoutWidth: Theme.fontSizeMedium * 46
    readonly property real desiredPopoutHeight: Theme.fontSizeMedium * 61
    popoutWidth: root.parentScreen ? Math.max(1, Math.min(desiredPopoutWidth, root.parentScreen.width - Theme.spacingL * 2)) : desiredPopoutWidth
    popoutHeight: root.parentScreen ? Math.max(1, Math.min(desiredPopoutHeight, root.parentScreen.height - (Theme.spacingXL * 3 + Theme.spacingS))) : desiredPopoutHeight

    Connections {
        function onGlobalVarChanged(id, name) {
            if (id === "presentationHub" && name === "session")
                root.barSessionInfo = PluginService.getGlobalVar("presentationHub", "session", {
                "active": false
            });

            if (id === "presentationHub" && name === "mirror")
                root.barMirrorInfo = PluginService.getGlobalVar("presentationHub", "mirror", {
                "state": "idle"
            });

        }

        target: PluginService
    }

    component MoveController: QtObject {
        id: moveRoot

        property var pending: []
        property Timer verification

        verification: Timer {
            interval: 80
            repeat: true
            onTriggered: {
                const state = moveRoot.snapshot();
                const remaining = [];
                for (const request of moveRoot.pending) {
                    const window = state.windows.find((w) => {
                        return w.id === request.id;
                    });
                    if (window && window.output === request.output)
                        request.callback(true);
                    else if (!window || !state.outputs.some((o) => {
                        return o.name === request.output;
                    }) || Date.now() >= request.deadline)
                        request.callback(false);
                    else
                        remaining.push(request);
                }
                moveRoot.pending = remaining;
                if (!remaining.length)
                    stop();

            }
        }

        function snapshot() {
            const outputs = Quickshell.screens.map((screen) => {
                return ({
                    "name": screen.name
                });
            });
            const workspaces = NiriService.workspaces || {
            };
            const windows = (NiriService.windows || []).map((w) => {
                return ({
                    "id": w.id,
                    "output": workspaces[w.workspace_id] ? workspaces[w.workspace_id].output : null
                });
            });
            return {
                "outputs": outputs,
                "windows": windows
            };
        }

        // NiriService.send reports socket availability, not whether the move applied.
        function move(id, output, callback) {
            const state = moveRoot.snapshot();
            if (!state.outputs.some((o) => {
                return o.name === output;
            }) || !state.windows.some((w) => {
                return w.id === id;
            })) {
                callback(false);
                return ;
            }
            if (!NiriService.send({
                "Action": {
                    "MoveWindowToMonitor": {
                        "id": id,
                        "output": output
                    }
                }
            })) {
                callback(false);
                return ;
            }
            pending = pending.concat([{
                "id": id,
                "output": output,
                "deadline": Date.now() + 2000,
                "callback": callback
            }]);
            verification.restart();
        }

    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: "present_to_all"
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: root.barMirrorActive || root.barSessionInfo.active
                width: Theme.spacingXS + Theme.spacingXXS
                height: width
                radius: width / 2
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

        }

    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DIcon {
                name: "present_to_all"
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
                visible: root.barMirrorActive || root.barSessionInfo.active
                width: Theme.spacingXS + Theme.spacingXXS
                height: width
                radius: width / 2
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

        }

    }

    popoutContent: Component {
        PopoutComponent {
            id: panel

            property var outputs: []
            property var windows: []
            property string target: ""
            property var selectedWindow: null
            property string message: ""
            property bool messageIsError: true
            property bool busy: false
            property string mode: PluginService.getGlobalVar("presentationHub", "session", {
                "active": false
            }).active ? "controls" : "window"
            property bool sessionDnd: false
            property string mirrorSource: ""
            property var mirrorInfo: PluginService.getGlobalVar("presentationHub", "mirror", {
                "state": "idle",
                "message": ""
            })
            property var sessionInfo: PluginService.getGlobalVar("presentationHub", "session", {
                "active": false,
                "output": ""
            })
            property var coverInfo: PluginService.getGlobalVar("presentationHub", "cover", {
                "active": false,
                "output": ""
            })
            property string coverImagePath: ""
            property var lastMoved: PluginService.getGlobalVar("presentationHub", "lastMoved", null)
            property string mirrorDependency: PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking")
            readonly property bool mirrorActive: mirrorInfo.state === "starting" || mirrorInfo.state === "running" || mirrorInfo.state === "stopping"

            function refresh() {
                const data = root.niriSnapshot(NiriService);
                panel.outputs = data.outputs;
                panel.windows = data.windows;
                if (!panel.outputs.some((o) => {
                    return o.name === panel.mirrorSource;
                })) {
                    const laptop = panel.outputs.find((o) => {
                        return /^(edp|lvds|dsi)-/i.test(o.name);
                    });
                    panel.mirrorSource = laptop ? laptop.name : "";
                }
                if (!panel.outputs.some((o) => {
                    return o.name === panel.target;
                })) {
                    const preferred = pluginService.loadPluginData("presentationHub", "presentationOutput", "");
                    panel.target = panel.outputs.some((o) => {
                        return o.name === preferred;
                    }) ? preferred : "";
                }
                if (panel.selectedWindow !== null && !panel.windows.some((w) => {
                    return w.id === panel.selectedWindow;
                }))
                    panel.selectedWindow = null;

                if (panel.lastMoved && !panel.windows.some((w) => {
                    return w.id === panel.lastMoved.id;
                })) {
                    panel.lastMoved = null;
                    PluginService.setGlobalVar("presentationHub", "lastMoved", null);
                }
            }

            function move() {
                if (selectedWindow === null || !target || busy)
                    return ;

                busy = true;
                messageIsError = true;
                const movedId = selectedWindow;
                const original = windows.find((w) => {
                    return w.id === movedId;
                });
                const oldOutput = original ? original.output : "";
                const newOutput = target;
                mover.move(movedId, newOutput, (success) => {
                    panel.busy = false;
                    if (!success) {
                        panel.message = "Could not move the window. It or the display may have disappeared.";
                        return ;
                    }
                    panel.messageIsError = false;
                    panel.lastMoved = oldOutput && oldOutput !== newOutput ? {
                        "id": movedId,
                        "output": oldOutput,
                        "target": newOutput
                    } : null;
                    PluginService.setGlobalVar("presentationHub", "lastMoved", panel.lastMoved);
                    panel.message = "Window moved to " + newOutput + ".";
                    panel.selectedWindow = null;
                });
            }

            function bringSelectedBack() {
                if (selectedWindow === null || busy)
                    return ;

                const laptop = outputs.find((o) => {
                    return /^(edp|lvds|dsi)-/i.test(o.name);
                });
                if (!laptop) {
                    messageIsError = true;
                    message = "No built-in display found. Choose a display and move the window manually.";
                    return ;
                }
                const id = selectedWindow;
                busy = true;
                mover.move(id, laptop.name, (success) => {
                    panel.busy = false;
                    panel.messageIsError = !success;
                    panel.message = success ? "Window moved to " + laptop.name + "." : "Could not move the window. Refresh and try again.";
                    if (success)
                        panel.refresh();

                });
            }

            function returnWindow() {
                if (!lastMoved || busy)
                    return ;

                busy = true;
                const entry = lastMoved;
                const state = root.niriSnapshot(NiriService);
                const window = state.windows.find((w) => {
                    return w.id === entry.id;
                });
                if (!window || window.output !== entry.target || !state.outputs.some((o) => {
                    return o.name === entry.output;
                })) {
                    busy = false;
                    messageIsError = true;
                    message = "Window or original display changed. Refresh and move it manually.";
                    lastMoved = null;
                    PluginService.setGlobalVar("presentationHub", "lastMoved", null);
                    return ;
                }
                mover.move(entry.id, entry.output, (success) => {
                    panel.busy = false;
                    panel.messageIsError = !success;
                    panel.message = success ? "Window returned to " + entry.output + "." : "Could not return window. Check the display and try again.";
                    if (success) {
                        panel.lastMoved = null;
                        PluginService.setGlobalVar("presentationHub", "lastMoved", null);
                    }
                });
            }

            function daemonRequest(action, args) {
                const daemon = PluginService.pluginDaemonInstances["presentationHub"];
                if (!daemon || typeof daemon.request !== "function")
                    return "Presentation Hub is not ready. Check that the plugin is enabled.";
                try {
                    return String(daemon.request(action, args));
                } catch (error) {
                    console.warn("Presentation Hub: daemon request failed", action, error);
                    return "Could not contact Presentation Hub. Check that the plugin is enabled.";
                }
            }

            function displayCommand(action, output) {
                const result = daemonRequest(action, [output || ""]);
                const success = ["Audience covered", "Audience restored", "Identifying display", "Session ended"];
                if (!success.includes(result)) {
                    messageIsError = true;
                    message = result;
                }
            }

            function startPresentation() {
                if (busy || sessionInfo.active || sessionInfo.starting)
                    return;
                message = "";
                messageIsError = true;
                const result = daemonRequest("startPresentation", [target, mode, mirrorSource || "-", selectedWindow === null ? "-" : String(selectedWindow), sessionDnd ? "true" : "false"]);
                if (result !== "Session started" && result !== "Starting session")
                    message = result || "Could not start presentation.";
            }

            function mirrorCommand(action) {
                if (busy)
                    return;
                message = "";
                messageIsError = true;
                const result = daemonRequest(action, [mirrorSource, target]);
                if (!result.startsWith("Starting mirror") && !result.startsWith("Stopping mirror"))
                    message = result || "Mirror request failed.";
            }

            function checkMirrorDependency() {
                const result = daemonRequest("checkMirror", []);
                if (result !== "Checking wl-mirror")
                    message = result;
            }

            function displayDescription(output) {
                const name = ((output.make || "") + " " + (output.model || "")).trim();
                const internal = /^(edp|lvds|dsi)-/i.test(output.name);
                return name || (internal ? "Built-in display" : "External display");
            }

            headerText: "Presentation Hub"
            detailsText: "Your presentation, on the right screen"
            Component.onCompleted: {
                coverImagePath = String(pluginService.loadPluginData("presentationHub", "coverImage", "") || "");
                refresh();
            }

            MoveController {
                id: mover
            }

            Connections {
                function onScreensChanged() {
                    panel.refresh();
                }

                target: Quickshell
            }

            Connections {
                function onOutputsChanged() {
                    panel.refresh();
                }

                function onWorkspacesChanged() {
                    panel.refresh();
                }

                function onWindowsChanged() {
                    panel.refresh();
                }

                target: NiriService
            }

            FileBrowserModal {
                id: coverImageDialog
                browserTitle: "Choose audience cover image"
                bucket: "presentation-cover"
                filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.svg"]
                onAccepted: paths => {
                    if (!paths || paths.length === 0 || !String(paths[0]).startsWith("/")) {
                        panel.messageIsError = true;
                        panel.message = "Choose a local image file.";
                        return;
                    }
                    panel.coverImagePath = String(paths[0]);
                    pluginService.savePluginData("presentationHub", "coverImage", panel.coverImagePath);
                    if (panel.coverInfo.active)
                        panel.displayCommand("showCover", panel.coverInfo.output);
                }
            }

            Connections {
                function onGlobalVarChanged(id, name) {
                    if (id === "presentationHub" && name === "mirror")
                        panel.mirrorInfo = PluginService.getGlobalVar("presentationHub", "mirror", {
                        "state": "idle",
                        "message": ""
                    });

                    if (id === "presentationHub" && name === "lastMoved")
                        panel.lastMoved = PluginService.getGlobalVar("presentationHub", "lastMoved", null);

                    if (id === "presentationHub" && name === "session") {
                        const previous = panel.sessionInfo.active;
                        panel.sessionInfo = PluginService.getGlobalVar("presentationHub", "session", {
                            "active": false,
                            "output": ""
                        });
                        if (!previous && panel.sessionInfo.active)
                            panel.mode = "controls";

                    }
                    if (id === "presentationHub" && name === "cover")
                        panel.coverInfo = PluginService.getGlobalVar("presentationHub", "cover", {
                        "active": false,
                        "output": ""
                    });

                    if (id === "presentationHub" && name === "mirrorDependency")
                        panel.mirrorDependency = PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking");

                }

                target: PluginService
            }

            Item {
                width: parent.width
                implicitHeight: Math.max(100, root.popoutHeight - panel.headerHeight - panel.detailsHeight - Theme.spacingXL)

                DFlickable {
                    id: contentViewport

                    fadeEdges: false
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: contentColumn

                        width: contentViewport.width
                        spacing: Theme.spacingM

                        Rectangle {
                            width: parent.width
                            height: Theme.fontSizeMedium + Theme.spacingM * 3 + Theme.spacingXS
                            radius: Theme.cornerRadius
                            color: (panel.mirrorActive || panel.sessionInfo.active) ? Theme.primaryContainer : Theme.cardSurface

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingS

                                DIcon {
                                    name: panel.mirrorActive ? "screen_share" : "desktop_windows"
                                    size: Theme.iconSizeMedium
                                    color: (panel.mirrorActive || panel.sessionInfo.active) ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: Math.max(0, parent.width - Theme.iconSizeMedium - Theme.spacingS - (stopMirrorButton.visible ? stopMirrorButton.width + Theme.spacingS : 0))
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXXS

                                    StyledText {
                                        width: parent.width
                                        text: panel.sessionInfo.active ? "Presentation active" : (panel.mirrorInfo.state === "stopping" ? "Stopping mirror…" : (panel.mirrorActive ? "Duplicating display" : (panel.outputs.length > 1 ? (panel.target ? "Ready to present" : "Choose an audience display") : "Connect a display")))
                                        color: (panel.mirrorActive || panel.sessionInfo.active) ? Theme.onPrimaryContainer : Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: panel.sessionInfo.active ? (panel.sessionInfo.mode === "mirror" ? "Duplicate" : "Window") + " → " + panel.sessionInfo.output : panel.mirrorActive ? panel.mirrorInfo.source + " → " + panel.mirrorInfo.target : (panel.outputs.length > 1 ? panel.outputs.length + " displays connected" : "An external display is needed")
                                        color: (panel.mirrorActive || panel.sessionInfo.active) ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }

                                }

                                DButton {
                                    id: stopMirrorButton

                                    visible: panel.sessionInfo.active || panel.mirrorActive
                                    text: panel.sessionInfo.active ? "End" : "Stop"
                                    iconName: "stop"
                                    enabled: !panel.busy && panel.mirrorInfo.state !== "stopping"
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: panel.sessionInfo.active ? panel.displayCommand("endSession", "") : panel.mirrorCommand("stopMirror")
                                }

                            }

                        }

                        Rectangle {
                            width: parent.width
                            height: Theme.fieldHeight + Theme.spacingXS
                            radius: Theme.cornerRadius
                            color: Theme.cardSurface

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXS
                                spacing: Theme.spacingXS

                                ModeButton {
                                    label: "Windows"
                                    symbolName: "web_asset"
                                    selected: panel.mode === "window"
                                    onTriggered: panel.mode = "window"
                                }

                                ModeButton {
                                    label: "Duplicate"
                                    symbolName: "content_copy"
                                    selected: panel.mode === "mirror"
                                    onTriggered: {
                                        panel.mode = "mirror";
                                        panel.refresh();
                                        panel.checkMirrorDependency();
                                    }
                                }

                                ModeButton {
                                    label: "Controls"
                                    symbolName: "tune"
                                    selected: panel.mode === "controls"
                                    onTriggered: panel.mode = "controls"
                                }

                            }

                        }

                        Flow {
                            id: setupFlow

                            readonly property real columnWidth: width

                            visible: panel.mode !== "controls"
                            width: parent.width
                            spacing: Theme.spacingL

                            Column {
                                width: setupFlow.columnWidth
                                spacing: Theme.spacingS

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    DIcon {
                                        name: "screen_share"
                                        size: Theme.iconSizeMedium
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: "Audience display"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                }

                                StyledText {
                                    width: parent.width
                                    text: "Where your audience will see the presentation"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                StyledText {
                                    visible: panel.outputs.length === 0
                                    width: parent.width
                                    text: panel.busy ? "Looking for displays…" : "No active displays found. Refresh to try again."
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }

                                Flow {
                                    id: audienceChoices

                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Repeater {
                                        model: panel.outputs

                                        ChoiceRow {
                                            required property var modelData

                                            width: audienceChoices.width >= Theme.fontSizeMedium * 34 ? (audienceChoices.width - audienceChoices.spacing) / 2 : audienceChoices.width
                                            label: modelData.name
                                            detail: panel.displayDescription(modelData)
                                            symbolName: /^(edp|lvds|dsi)-/i.test(modelData.name) ? "laptop_mac" : "monitor"
                                            selected: panel.target === modelData.name
                                            enabled: !panel.mirrorActive && !panel.sessionInfo.active
                                            onTriggered: {
                                                panel.target = modelData.name;
                                                pluginService.savePluginData("presentationHub", "presentationOutput", modelData.name);
                                            }
                                        }

                                    }

                                }

                                StyledText {
                                    visible: panel.outputs.length === 1
                                    width: parent.width
                                    text: "Connect another display to get started."
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                            }

                            Column {
                                width: setupFlow.columnWidth
                                spacing: Theme.spacingL

                                Column {
                                    visible: panel.mode === "window"
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: "web_asset"
                                            size: Theme.iconSizeMedium
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: "Window to present"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Choose the slide or application window to move to the audience display."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    DListView {
                                        id: windowList

                                        readonly property real rowHeight: Theme.fontSizeMedium + Theme.spacingM * 3 + Theme.spacingXS
                                        readonly property int visibleRows: Math.min(count, root.popoutHeight >= 700 ? 4 : 3)

                                        fadeEdges: false
                                        width: parent.width
                                        height: visibleRows > 0 ? visibleRows * rowHeight + (visibleRows - 1) * spacing : 0
                                        clip: true
                                        spacing: Theme.spacingXS
                                        model: panel.windows
                                        boundsBehavior: Flickable.StopAtBounds
                                        activeFocusOnTab: true
                                        keyNavigationEnabled: true
                                        Accessible.role: Accessible.List
                                        Accessible.name: "Open windows"
                                        Keys.onReturnPressed: (event) => {
                                            if (currentItem)
                                                panel.selectedWindow = currentItem.modelData.id;

                                            event.accepted = true;
                                        }
                                        Keys.onEnterPressed: (event) => {
                                            if (currentItem)
                                                panel.selectedWindow = currentItem.modelData.id;

                                            event.accepted = true;
                                        }
                                        Keys.onSpacePressed: (event) => {
                                            if (currentItem)
                                                panel.selectedWindow = currentItem.modelData.id;

                                            event.accepted = true;
                                        }

                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index

                                            width: ListView.view.width
                                            height: windowList.rowHeight
                                            radius: Theme.cornerRadius
                                            color: panel.selectedWindow === modelData.id ? Theme.primaryContainer : (windowHover.hovered ? Theme.chipSurface : Theme.cardSurface)
                                            border.width: activeFocus || (windowList.activeFocus && windowList.currentIndex === index) ? Theme.spacingXXS : 0
                                            border.color: Theme.primary
                                            activeFocusOnTab: true
                                            Accessible.role: Accessible.Button
                                            Accessible.name: (modelData.title || modelData.app_id || "Untitled window") + ", " + (modelData.output || "Unknown display")
                                            Accessible.description: panel.selectedWindow === modelData.id ? "Selected" : "Select window"
                                            Accessible.onPressAction: panel.selectedWindow = modelData.id
                                            Keys.onReturnPressed: (event) => {
                                                panel.selectedWindow = modelData.id;
                                                event.accepted = true;
                                            }
                                            Keys.onEnterPressed: (event) => {
                                                panel.selectedWindow = modelData.id;
                                                event.accepted = true;
                                            }
                                            Keys.onSpacePressed: (event) => {
                                                panel.selectedWindow = modelData.id;
                                                event.accepted = true;
                                            }
                                            onActiveFocusChanged: {
                                                if (activeFocus)
                                                    ListView.view.positionViewAtIndex(index, ListView.Contain);

                                            }

                                            HoverHandler {
                                                id: windowHover
                                            }

                                            TapHandler {
                                                onTapped: panel.selectedWindow = modelData.id
                                            }

                                            DIcon {
                                                id: windowIcon

                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: "web_asset"
                                                size: Theme.iconSizeMedium
                                                color: panel.selectedWindow === modelData.id ? Theme.primary : Theme.surfaceVariantText
                                            }

                                            Column {
                                                anchors.left: windowIcon.right
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.right: parent.right
                                                anchors.rightMargin: Theme.spacingM
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: Theme.spacingXXS

                                                StyledText {
                                                    width: parent.width
                                                    text: modelData.title || modelData.app_id || "Untitled window"
                                                    color: Theme.surfaceText
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    font.weight: Font.Medium
                                                    wrapMode: Text.NoWrap
                                                    maximumLineCount: 1
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: (modelData.app_id || "Unknown app") + " · " + (modelData.output || "Unknown display")
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    wrapMode: Text.NoWrap
                                                    maximumLineCount: 1
                                                    elide: Text.ElideRight
                                                }

                                            }

                                        }

                                    }

                                    StyledText {
                                        visible: windowList.count > windowList.visibleRows
                                        width: parent.width
                                        text: "Scroll or use arrow keys to see more"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: !panel.busy && windowList.count === 0
                                        width: parent.width
                                        text: "No windows found. Refresh to try again."
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }

                                }

                                Column {
                                    visible: panel.mode === "mirror"
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Row {
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: "laptop_mac"
                                            size: Theme.iconSizeMedium
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: "Display to duplicate"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Everything on this display will appear on the audience display."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    Flow {
                                        id: sourceChoices

                                        width: parent.width
                                        spacing: Theme.spacingS

                                        Repeater {
                                            model: panel.outputs

                                            ChoiceRow {
                                                required property var modelData

                                                width: sourceChoices.width >= Theme.fontSizeMedium * 34 ? (sourceChoices.width - sourceChoices.spacing) / 2 : sourceChoices.width
                                                label: modelData.name
                                                detail: panel.displayDescription(modelData)
                                                symbolName: /^(edp|lvds|dsi)-/i.test(modelData.name) ? "laptop_mac" : "monitor"
                                                selected: panel.mirrorSource === modelData.name
                                                enabled: !panel.mirrorActive
                                                onTriggered: panel.mirrorSource = modelData.name
                                            }

                                        }

                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: privacyText.implicitHeight + Theme.spacingM * 2
                                        radius: Theme.cornerRadius
                                        color: Theme.cardSurface

                                        DIcon {
                                            id: privacyIcon

                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.top: parent.top
                                            anchors.topMargin: Theme.spacingM
                                            name: "visibility"
                                            size: Theme.iconSizeMedium
                                            color: Theme.surfaceVariantText
                                        }

                                        StyledText {
                                            id: privacyText

                                            anchors.left: privacyIcon.right
                                            anchors.leftMargin: Theme.spacingS
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Everything on the source display is visible to the audience, including notifications and notes."
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }

                                    }

                                    StyledText {
                                        visible: panel.mirrorDependency !== "available"
                                        width: parent.width
                                        text: panel.mirrorDependency === "missing" ? "Duplicate needs wl-mirror. Install it with your package manager (Arch/CachyOS: sudo pacman -S wl-mirror), then recheck. Other features remain available." : "Checking for wl-mirror…"
                                        color: panel.mirrorDependency === "missing" ? Theme.error : Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }

                                    DButton {
                                        visible: panel.mirrorDependency === "missing"
                                        text: "Recheck wl-mirror"
                                        onClicked: panel.checkMirrorDependency()
                                    }

                                    StyledText {
                                        visible: !panel.mirrorActive && panel.mirrorSource !== "" && panel.mirrorSource === panel.target
                                        width: parent.width
                                        text: "Choose different source and audience displays."
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: !panel.mirrorActive && panel.mirrorInfo.message !== ""
                                        width: parent.width
                                        text: panel.mirrorInfo.message
                                        color: panel.mirrorInfo.state === "error" ? Theme.error : Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                    }

                                }

                                Column {
                                    visible: panel.mode !== "controls" && !panel.sessionInfo.active
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    ChoiceRow {
                                        label: "Do Not Disturb"
                                        detail: panel.sessionDnd ? "Enabled during this session" : "Keep current notification settings"
                                        symbolName: "notifications_off"
                                        selected: panel.sessionDnd
                                        onTriggered: panel.sessionDnd = !panel.sessionDnd
                                    }

                                    DButton {
                                        text: panel.sessionInfo.starting ? "Starting…" : "Start presentation"
                                        iconName: "play_arrow"
                                        enabled: !panel.busy && !panel.sessionInfo.starting && panel.outputs.length > 1 && panel.target !== "" && (panel.mode === "window" ? panel.selectedWindow !== null && !panel.mirrorActive : (panel.mirrorDependency === "available" && !panel.mirrorActive && panel.mirrorSource !== "" && panel.mirrorSource !== panel.target))
                                        onClicked: panel.startPresentation()
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Keeps the session awake when supported. End the session to stop what it started."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                }

                                Column {
                                    visible: panel.mode === "window"
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: "Move a window manually"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Move the selected window to the audience display or back to your laptop. This does not start a session."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        DButton {
                                            backgroundColor: Theme.secondaryContainer
                                            textColor: Theme.onSecondaryContainer
                                            text: "Move to audience"
                                            enabled: !panel.busy && panel.selectedWindow !== null && panel.target !== "" && panel.outputs.length > 1
                                            onClicked: panel.move()
                                        }

                                        DButton {
                                            backgroundColor: Theme.secondaryContainer
                                            textColor: Theme.onSecondaryContainer
                                            text: "Move to built-in display"
                                            enabled: !panel.busy && panel.selectedWindow !== null && panel.outputs.some((o) => {
                                                return /^(edp|lvds|dsi)-/i.test(o.name);
                                            })
                                            onClicked: panel.bringSelectedBack()
                                        }

                                        DButton {
                                            backgroundColor: Theme.secondaryContainer
                                            textColor: Theme.onSecondaryContainer
                                            visible: panel.lastMoved !== null
                                            text: "Return last moved window"
                                            enabled: !panel.busy
                                            onClicked: panel.returnWindow()
                                        }

                                        DButton {
                                            backgroundColor: Theme.secondaryContainer
                                            textColor: Theme.onSecondaryContainer
                                            text: "Refresh"
                                            enabled: !panel.busy
                                            onClicked: panel.refresh()
                                        }

                                    }

                                }

                                Column {
                                    visible: panel.mode === "mirror" && !panel.mirrorActive
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: "Duplicate without a session"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Start mirroring without changing Do Not Disturb or requesting idle inhibition."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    DButton {
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        text: "Start mirroring"
                                        iconName: "screen_share"
                                        enabled: !panel.busy && panel.mirrorDependency === "available" && panel.mirrorSource !== "" && panel.target !== "" && panel.mirrorSource !== panel.target
                                        onClicked: panel.mirrorCommand("startMirror")
                                    }

                                }

                            }

                        }

                        Column {
                            visible: panel.mode === "controls"
                            width: parent.width
                            spacing: Theme.spacingL

                            // The destination is shared with the Windows and Duplicate tabs.
                            Rectangle {
                                width: parent.width
                                height: Theme.fontSizeMedium + Theme.spacingXL * 2
                                radius: Theme.cornerRadius
                                color: Theme.cardSurface

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingS

                                    DIcon {
                                        name: "monitor"
                                        size: Theme.iconSizeMedium
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        width: Math.max(0, parent.width - Theme.iconSizeMedium - Theme.spacingS * 2 - identifyButton.width)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingXXS

                                        StyledText {
                                            width: parent.width
                                            text: panel.target ? "Audience display · " + panel.target : "No audience display selected"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: panel.target ? "Selected in Windows or Duplicate" : "Select a display in Windows or Duplicate"
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                        }

                                    }

                                    DButton {
                                        id: identifyButton

                                        text: "Identify"
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        iconName: "monitor"
                                        enabled: panel.target !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: panel.displayCommand("identify", panel.target)
                                    }

                                }

                            }

                            Column {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    text: "Cover audience display"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                }

                                StyledText {
                                    width: parent.width
                                    text: panel.coverInfo.active ? "The audience is seeing your cover on " + panel.coverInfo.output + ". Resume to reveal the display." : "Temporarily show a black screen or an image instead of your presentation."
                                    color: panel.coverInfo.active ? Theme.primary : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                DButton {
                                    text: panel.coverInfo.active ? "Resume audience display" : "Show cover"
                                    iconName: panel.coverInfo.active ? "visibility" : "visibility_off"
                                    enabled: panel.coverInfo.active || panel.target !== ""
                                    onClicked: panel.displayCommand(panel.coverInfo.active ? "hideCover" : "showCover", panel.coverInfo.active ? "" : panel.target)
                                }

                                StyledText {
                                    visible: panel.coverInfo.active && panel.coverInfo.imageStatus === "error"
                                    width: parent.width
                                    text: "Image could not be loaded. The audience display is black; choose another image."
                                    color: Theme.error
                                    wrapMode: Text.WordWrap
                                }

                                StyledText {
                                    text: "Cover appearance"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(Theme.fontSizeMedium * 13, Math.max(Theme.fontSizeMedium * 8, width * 0.3))
                                    color: "black"
                                    radius: Theme.cornerRadius
                                    clip: true

                                    Image {
                                        id: coverThumbnail

                                        anchors.fill: parent
                                        source: panel.coverImagePath.startsWith("/") ? "file://" + panel.coverImagePath.split("/").map(encodeURIComponent).join("/") : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: panel.coverImagePath === "" || coverThumbnail.status === Image.Error
                                        width: coverLabel.implicitWidth + Theme.spacingM * 2
                                        height: coverLabel.implicitHeight + Theme.spacingS * 2
                                        radius: Theme.cornerRadius
                                        color: Theme.surface

                                        StyledText {
                                            id: coverLabel

                                            anchors.centerIn: parent
                                            text: panel.coverImagePath === "" ? "Black screen" : "Image unavailable"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                    }

                                }

                                StyledText {
                                    width: parent.width
                                    text: panel.coverImagePath ? "Image: " + panel.coverImagePath.split("/").pop() : "Using black screen"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideMiddle
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    DButton {
                                        text: panel.coverImagePath ? "Change image" : "Choose image"
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        iconName: "image"
                                        onClicked: coverImageDialog.open()
                                    }

                                    DButton {
                                        visible: panel.coverImagePath !== ""
                                        text: "Use black screen"
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        onClicked: {
                                            panel.coverImagePath = "";
                                            pluginService.savePluginData("presentationHub", "coverImage", "");
                                            if (panel.coverInfo.active)
                                                panel.displayCommand("showCover", panel.coverInfo.output);

                                        }
                                    }

                                }

                            }

                        }

                        StyledText {
                            visible: panel.message !== ""
                            width: parent.width
                            text: panel.message
                            color: panel.messageIsError ? Theme.error : Theme.surfaceText
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            width: 1
                            height: Theme.spacingS
                        }

                    }

                }


            }

            component ChoiceRow: DButton {
                id: choice

                property string label: ""
                property string detail: ""
                property string symbolName: "monitor"
                property bool selected: false

                signal triggered()

                width: parent.width
                height: Theme.fontSizeMedium + Theme.spacingXL * 2
                backgroundColor: selected ? Theme.primaryContainer : Theme.cardSurface
                textColor: selected ? Theme.onPrimaryContainer : Theme.surfaceText
                Accessible.name: label + ", " + detail
                Accessible.description: selected ? "Selected" : "Select display"
                onClicked: triggered()

                Rectangle {
                    id: iconBox

                    width: Theme.iconSizeMedium + Theme.spacingS * 2
                    height: width
                    radius: Theme.cornerRadius
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    color: choice.selected ? Theme.primary : Theme.chipSurface

                    DIcon {
                        anchors.centerIn: parent
                        name: choice.symbolName
                        size: Theme.iconSizeMedium
                        color: choice.selected ? Theme.onPrimary : Theme.surfaceText
                    }

                }

                Column {
                    anchors.left: iconBox.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: checkIcon.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: choice.label
                        color: choice.selected ? Theme.onPrimaryContainer : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: choice.detail
                        color: choice.selected ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                }

                DIcon {
                    id: checkIcon

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: choice.selected ? "check_circle" : "radio_button_unchecked"
                    size: Theme.iconSizeMedium
                    color: choice.selected ? Theme.primary : Theme.surfaceVariantText
                }

            }

            component ModeButton: DButton {
                id: modeButton

                property string label: ""
                property string symbolName: ""
                property bool selected: false

                signal triggered()

                width: (parent.width - 2 * Theme.spacingXS) / 3
                height: Theme.iconSizeMedium + Theme.spacingM * 2
                backgroundColor: selected ? Theme.primaryContainer : Theme.cardSurface
                textColor: selected ? Theme.onPrimaryContainer : Theme.surfaceText
                Accessible.name: label
                Accessible.description: selected ? "Selected" : "Switch mode"
                onClicked: triggered()

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DIcon {
                        name: modeButton.symbolName
                        size: Theme.iconSizeMedium
                        color: modeButton.selected ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modeButton.label
                        color: modeButton.selected ? Theme.onPrimaryContainer : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }

                }

            }

        }

    }

}
