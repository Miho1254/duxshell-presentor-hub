// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string corePath: decodeURIComponent(Qt.resolvedUrl("bin/presentation-hub-core").toString().replace(/^file:\/\//, ""))
    property var knownOutputs: []
    property bool initialized: false
    property bool checking: false
    property int checks: 0
    property string lastError: ""
    property var pendingOutputs: []
    property var pendingWindows: []
    property var knownWindows: []
    property var suggestedIds: []
    property var fullscreenIds: []
    property var fullscreenStarted: ({
    })
    property var readyFullscreenIds: []
    property bool moving: false
    property string mirrorSource: ""
    property string mirrorTarget: ""
    property bool mirrorStopping: false
    property string mirrorStopMessage: ""
    property bool mirrorActive: false
    property bool mirrorDependencyChecking: false
    property string coverOutput: ""
    property string coverImageUrl: ""
    property string identifyOutput: ""
    property string sessionOutput: ""
    property string sessionMode: ""
    property bool sessionMirrorOwned: false
    property bool sessionCoverOwned: false
    property bool sessionDndOwned: false
    property bool changingDnd: false
    property bool sessionStarting: false
    property int sessionGeneration: 0
    readonly property var sessionScreen: Quickshell.screens.find((screen) => {
        return screen.name === sessionOutput;
    }) || null
    readonly property var coverScreen: Quickshell.screens.find((screen) => {
        return screen.name === coverOutput;
    }) || null
    readonly property var identifyScreen: Quickshell.screens.find((screen) => {
        return screen.name === identifyOutput;
    }) || null

    function publishSession() {
        PluginService.setGlobalVar("presentationHub", "session", {
            "active": sessionOutput !== "",
            "output": sessionOutput,
            "mode": sessionMode,
            "starting": sessionStarting,
            "dnd": sessionDndOwned
        });
    }

    function activateSession(output, mode, dnd) {
        sessionOutput = output;
        sessionMode = mode;
        sessionStarting = false;
        if (dnd && !SessionData.doNotDisturb) {
            changingDnd = true;
            SessionData.setDoNotDisturb(true);
            changingDnd = false;
            sessionDndOwned = SessionData.doNotDisturb && SessionData.doNotDisturbUntil === 0;
        }
        publishSession();
    }

    // Release only the state created by this session. External changes to DND
    // relinquish ownership in the SessionData connections below.
    function endSession() {
        sessionGeneration++;
        sessionStarting = false;
        sessionOutput = "";
        sessionMode = "";
        if (sessionCoverOwned)
            hideCover();

        sessionCoverOwned = false;
        if (sessionMirrorOwned && mirrorProcess.running)
            stopMirror("Presentation session ended; mirror stopped.");

        sessionMirrorOwned = false;
        if (sessionDndOwned && SessionData.doNotDisturb && SessionData.doNotDisturbUntil === 0 && !SessionData.doNotDisturbHeldByScreenShare) {
            changingDnd = true;
            SessionData.setDoNotDisturb(false);
            changingDnd = false;
        }
        sessionDndOwned = false;
        publishSession();
    }

    function publishCover() {
        PluginService.setGlobalVar("presentationHub", "cover", {
            "active": coverOutput !== "",
            "output": coverOutput,
            "imageStatus": coverImageUrl === "" ? "black" : (coverImage.status === Image.Ready ? "ready" : coverImage.status === Image.Error ? "error" : "loading")
        });
    }

    function hideCover() {
        coverOutput = "";
        sessionCoverOwned = false;
        publishCover();
    }

    function suggestionMode() {
        const mode = String(PluginService.loadPluginData("presentationHub", "suggestionMode", "") || "");
        if (mode === "always" || mode === "session" || mode === "manual")
            return mode;

        return PluginService.loadPluginData("presentationHub", "suggestFullscreen", "yes") === "no" ? "manual" : "always";
    }

    function browserAllowed(appId) {
        const app = String(appId || "").toLowerCase();
        const list = String(PluginService.loadPluginData("presentationHub", "browserFilterIds", "") || "").split(",").map((s) => {
            return s.trim().toLowerCase();
        }).filter((s) => {
            return s;
        });
        const filter = String(PluginService.loadPluginData("presentationHub", "browserFilter", "all") || "all");
        return filter === "only" ? list.includes(app) : filter === "exclude" ? !list.includes(app) : true;
    }

    function checkMirrorDependency(showNotice) {
        if (mirrorDependencyChecking)
            return;

        mirrorDependencyChecking = true;
        PluginService.setGlobalVar("presentationHub", "mirrorDependency", "checking");
        Proc.runCommand("presentationHub.mirrorDependency", ["sh", "-c", "command -v wl-mirror >/dev/null 2>&1"], (out, code) => {
            root.mirrorDependencyChecking = false;
            const state = code === 0 ? "available" : "missing";
            PluginService.setGlobalVar("presentationHub", "mirrorDependency", state);
            if (showNotice && state === "missing")
                ToastService.showInfo("Duplicate needs wl-mirror", "Install wl-mirror to enable Duplicate. Window moving is still available.");

        });
    }

    function publishMirror(state, message) {
        mirrorActive = state === "starting" || state === "running" || state === "stopping";
        if (mirrorActive) {
            // Do not surface queued suggestions during or just after duplication.
            pendingWindows = [];
            for (const window of knownWindows) {
                if ((window.presentation_candidate || fullscreenIds.includes(window.id)) && !suggestedIds.includes(window.id))
                    suggestedIds = suggestedIds.concat([window.id]);

            }
            if (windowPrompt.shouldBeVisible && !moving)
                windowPrompt.close();

        }
        PluginService.setGlobalVar("presentationHub", "mirror", {
            "state": state,
            "source": mirrorSource,
            "target": mirrorTarget,
            "message": message || ""
        });
    }

    function stopMirror(reason) {
        if (!mirrorProcess.running)
            return;

        mirrorStopping = true;
        mirrorStopMessage = reason || "Mirror stopped.";
        publishMirror("stopping", "Stopping mirror…");
        mirrorProcess.running = false;
    }

    function askForOutput(name) {
        if (displayPrompt.shouldBeVisible && displayPrompt.outputName === name)
            return;

        if (!pendingOutputs.includes(name))
            pendingOutputs = pendingOutputs.concat([name]);

        nextPrompt();
    }

    function nextPrompt() {
        if (displayPrompt.shouldBeVisible || windowPrompt.shouldBeVisible)
            return;

        while (pendingOutputs.length > 0) {
            const name = pendingOutputs[0];
            pendingOutputs = pendingOutputs.slice(1);
            if (knownOutputs.includes(name)) {
                displayPrompt.outputName = name;
                displayPrompt.open();
                return;
            }
        }
        if (mirrorActive)
            return;

        const target = PluginService.loadPluginData("presentationHub", "presentationOutput", "");
        if (suggestionMode() === "manual") {
            pendingWindows = [];
            return;
        }
        while (pendingWindows.length > 0) {
            const candidate = pendingWindows[0];
            pendingWindows = pendingWindows.slice(1);
            const current = knownWindows.find((w) => {
                return w.id === candidate.id;
            });
            const fullscreenAllowed = suggestionMode() === "always" || (suggestionMode() === "session" && sessionOutput !== "");
            const eligible = current && (current.presentation_candidate || (fullscreenAllowed && readyFullscreenIds.includes(current.id)));
            if (target && knownOutputs.includes(target) && eligible && current.output && current.output !== target) {
                windowPrompt.windowId = current.id;
                windowPrompt.windowTitle = current.title || current.app_id || "Untitled window";
                windowPrompt.targetOutput = target;
                windowPrompt.isFullscreenBrowser = fullscreenIds.includes(current.id);
                windowPrompt.errorMessage = "";
                windowPrompt.open();
                return;
            }
        }
    }

    function isExternal(name) {
        const lower = name.toLowerCase();
        return !lower.startsWith("edp-") && !lower.startsWith("lvds-") && !lower.startsWith("dsi-");
    }

    function isBrowser(appId) {
        const app = (appId || "").toLowerCase();
        const configured = String(PluginService.loadPluginData("presentationHub", "additionalBrowserAppIds", "") || "").split(",").map((value) => {
            return value.trim().toLowerCase();
        }).filter((value) => {
            return value !== "";
        });
        if (configured.includes(app))
            return true;

        return ["firefox", "chrom", "brave", "vivaldi", "microsoft-edge", "zen", "floorp", "librewolf", "waterfox", "tor-browser", "epiphany", "opera", "qutebrowser", "falkon"].some((name) => {
            return app.includes(name);
        });
    }

    // Wayland toplevel handles do not expose the Niri window ID. Only join
    // when app ID and title identify exactly one window on both sides.
    function fullscreenBrowserIds(windows) {
        const tops = Array.from(ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []);
        const result = [];
        for (const top of tops) {
            if (!top.fullscreen || !top.title || !isBrowser(top.appId) || !browserAllowed(top.appId))
                continue;

            const matches = windows.filter((w) => {
                return w.app_id === top.appId && w.title === top.title;
            });
            const peers = tops.filter((t) => {
                return t.appId === top.appId && t.title === top.title;
            });
            if (matches.length === 1 && peers.length === 1)
                result.push(matches[0].id);

        }
        return result;
    }

    // Proc uses a stable ID, and `checking` prevents overlapping polls.
    // This keeps the 3-second watchdog bounded when Niri is slow to reply.
    function refreshOutputs() {
        if (checking)
            return;

        checking = true;
        Proc.runCommand("presentationHub.watchOutputs", [corePath, "snapshot"], (out, code) => {
            root.checking = false;
            root.checks++;
            if (code !== 0) {
                root.lastError = "Core snapshot failed: " + code;
                return;
            }
            root.lastError = "";
            try {
                const state = JSON.parse(out);
                const outputs = state.outputs.map((o) => {
                    return o.name;
                });
                const previous = root.knownOutputs;
                root.knownOutputs = outputs;
                if (root.sessionOutput && !outputs.includes(root.sessionOutput))
                    root.endSession();

                if (root.coverOutput && !outputs.includes(root.coverOutput))
                    root.hideCover();

                if (root.identifyOutput && !outputs.includes(root.identifyOutput))
                    root.identifyOutput = "";

                if (mirrorProcess.running && (!outputs.includes(root.mirrorSource) || !outputs.includes(root.mirrorTarget)))
                    root.stopMirror("Display disconnected; mirror stopped.");

                root.knownWindows = state.windows;
                root.fullscreenIds = root.fullscreenBrowserIds(state.windows);
                const now = Date.now();
                const starts = {
                };
                let waiting = false;
                for (const id of root.fullscreenIds) {
                    starts[id] = root.fullscreenStarted[id] || now;
                    if (now - starts[id] < 450)
                        waiting = true;

                }
                root.fullscreenStarted = starts;
                root.readyFullscreenIds = root.fullscreenIds.filter((id) => {
                    return now - starts[id] >= 450;
                });
                if (waiting && !fullscreenSettle.running)
                    fullscreenSettle.start();

                const ids = state.windows.map((w) => {
                    return w.id;
                });
                // Prompts can remain open while windows/displays disappear.
                // Drop stale queue entries on every snapshot to bound their lifetime.
                root.pendingOutputs = root.pendingOutputs.filter(name => outputs.includes(name));
                root.pendingWindows = root.pendingWindows.filter(candidate => ids.includes(candidate.id));
                root.suggestedIds = root.suggestedIds.filter((id) => {
                    return state.windows.some((w) => {
                        return w.id === id && (w.presentation_candidate || root.fullscreenIds.includes(id));
                    });
                });
                if (root.mirrorActive) {
                    for (const window of state.windows) {
                        if ((window.presentation_candidate || root.fullscreenIds.includes(window.id)) && !root.suggestedIds.includes(window.id))
                            root.suggestedIds = root.suggestedIds.concat([window.id]);

                    }
                }
                if (root.initialized) {
                    for (const name of outputs) {
                        if (!previous.includes(name) && root.isExternal(name))
                            root.askForOutput(name);

                    }
                    const target = PluginService.loadPluginData("presentationHub", "presentationOutput", "");
                    const suggestMode = root.suggestionMode();
                    const suggestFullscreen = suggestMode === "always" || (suggestMode === "session" && root.sessionOutput !== "");
                    if (!root.mirrorActive && target && outputs.includes(target)) {
                        for (const window of state.windows) {
                            if (((suggestMode !== "manual" && window.presentation_candidate) || (suggestFullscreen && root.readyFullscreenIds.includes(window.id))) && window.output && window.output !== target && !root.suggestedIds.includes(window.id)) {
                                root.suggestedIds = root.suggestedIds.concat([window.id]);
                                if (!root.pendingWindows.some(candidate => candidate.id === window.id)) {
                                    root.pendingWindows = root.pendingWindows.concat([{ "id": window.id }]);
                                }
                            }
                        }
                    }
                } else {
                    root.suggestedIds = state.windows.filter((w) => {
                        return w.presentation_candidate || root.fullscreenIds.includes(w.id);
                    }).map((w) => {
                        return w.id;
                    });
                }
                if (root.initialized && JSON.stringify(previous) !== JSON.stringify(outputs))
                    console.info("Presentation Hub: outputs changed", JSON.stringify(outputs));

                if (displayPrompt.shouldBeVisible && !outputs.includes(displayPrompt.outputName))
                    displayPrompt.close();

                if (windowPrompt.shouldBeVisible && (!outputs.includes(windowPrompt.targetOutput) || !ids.includes(windowPrompt.windowId) || (windowPrompt.isFullscreenBrowser && !root.fullscreenIds.includes(windowPrompt.windowId))))
                    windowPrompt.close();

                root.initialized = true;
                root.nextPrompt();
            } catch (e) {
                console.warn("Presentation Hub: invalid display snapshot", e);
            }
        });
    }

    Component.onDestruction: {
        if (sessionOutput || sessionStarting) {
            endSession();
        }
    }
    Component.onCompleted: {
        if (!PluginService.loadPluginData("presentationHub", "suggestionMode", "") && PluginService.loadPluginData("presentationHub", "suggestFullscreen", "yes") === "no")
            PluginService.savePluginData("presentationHub", "suggestionMode", "manual");

        publishMirror("idle", "");
        publishCover();
        publishSession();
        refreshOutputs();
        checkMirrorDependency(true);
    }

    Connections {
        function onDoNotDisturbChanged() {
            if (!root.changingDnd && root.sessionDndOwned)
                root.sessionDndOwned = false;

        }

        function onDoNotDisturbUntilChanged() {
            if (!root.changingDnd && root.sessionDndOwned)
                root.sessionDndOwned = false;

        }

        target: SessionData
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refreshOutputs()
    }

    Timer {
        id: fullscreenSettle

        interval: 500
        repeat: false
        onTriggered: root.refreshOutputs()
    }

    Timer {
        id: fullscreenDebounce

        interval: 150
        repeat: false
        onTriggered: root.refreshOutputs()
    }

    Connections {
        function onActiveToplevelChanged() {
            fullscreenDebounce.restart();
        }

        target: ToplevelManager
    }

    Connections {
        function onFullscreenChanged() {
            fullscreenDebounce.restart();
        }

        function onTitleChanged() {
            fullscreenDebounce.restart();
        }

        target: ToplevelManager.activeToplevel
    }

    Process {
        id: mirrorProcess

        // Arguments are passed separately: output names cannot become shell code.
        // Discard stderr rather than collecting an unbounded log for a long session.
        command: ["sh", "-c", "exec wl-mirror --fullscreen-output \"$2\" \"$1\" 2>/dev/null", "presentation-hub", root.mirrorSource, root.mirrorTarget]
        onStarted: root.publishMirror("running", "Mirror process running")
        onExited: (exitCode) => {
            const wasStopped = root.mirrorStopping;
            root.mirrorStopping = false;
            if (wasStopped) {
                root.publishMirror("idle", root.mirrorStopMessage);
            } else {
                if (root.sessionMirrorOwned)
                    root.endSession();

                root.publishMirror("error", exitCode === 127 ? "wl-mirror is not installed. Install it and try again." : "Mirror stopped unexpectedly (exit " + exitCode + "). Check wl-mirror and display availability.");
                if (exitCode === 127)
                    root.checkMirrorDependency(false);

            }
        }

    }

    PanelWindow {
        id: sessionWindow

        screen: root.sessionScreen
        visible: root.sessionOutput !== "" && root.sessionScreen !== null
        color: "transparent"
        implicitWidth: 1
        implicitHeight: 1
        WlrLayershell.namespace: "presentation-hub:session"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusiveZone: -1

        anchors {
            top: true
            left: true
        }

        mask: Region {
        }

    }

    IdleInhibitor {
        window: sessionWindow
        enabled: sessionWindow.visible
    }

    PanelWindow {
        id: coverWindow

        screen: root.coverScreen
        visible: root.coverOutput !== "" && root.coverScreen !== null
        color: "black"
        WlrLayershell.namespace: "presentation-hub:audience-cover"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Image {
            id: coverImage

            anchors.fill: parent
            onStatusChanged: root.publishCover()
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: root.coverImageUrl
        }

    }

    PanelWindow {
        screen: root.identifyScreen
        visible: root.identifyOutput !== "" && root.identifyScreen !== null
        color: "transparent"
        WlrLayershell.namespace: "presentation-hub:identify"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, identifyLabel.implicitWidth + 80)
            height: 110
            radius: 16
            color: "#eb111318"

            Text {
                id: identifyLabel

                anchors.centerIn: parent
                text: root.identifyOutput
                color: "white"
                font.pixelSize: 36
                font.bold: true
            }

        }

    }

    Timer {
        id: identifyTimer

        interval: 3000
        onTriggered: root.identifyOutput = ""
    }

    IpcHandler {
        function status() : string {
            return JSON.stringify({
                "session": PluginService.getGlobalVar("presentationHub", "session", {
                    "active": false
                }),
                "cover": PluginService.getGlobalVar("presentationHub", "cover", {
                    "active": false
                }),
                "ready": root.initialized,
                "outputs": root.knownOutputs,
                "checks": root.checks,
                "lastError": root.lastError,
                "fullscreenIds": root.fullscreenIds,
                "suggestedIds": root.suggestedIds,
                "windowPromptVisible": windowPrompt.shouldBeVisible,
                "promptedWindowId": windowPrompt.shouldBeVisible ? windowPrompt.windowId : null,
                "mirror": PluginService.getGlobalVar("presentationHub", "mirror", {
                    "state": "idle"
                }),
                "mirrorDependency": PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking")
            });
        }

        function startPresentation(output: string, mode: string, source: string, windowId: string, dnd: string) : string {
            if (root.sessionOutput || root.sessionStarting)
                return "Session already active or starting";

            if (!output || !root.knownOutputs.includes(output) || !Quickshell.screens.some((screen) => {
                return screen.name === output;
            }))
                return "Display not connected";

            if (mode !== "window" && mode !== "mirror")
                return "Choose a presentation mode";

            if (mode === "mirror") {
                if (!source || source === output || !root.knownOutputs.includes(source))
                    return "Choose different connected displays";

                if (root.mirrorActive || mirrorProcess.running)
                    return "Stop the current mirror before starting a session";

                if (PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking") !== "available")
                    return "wl-mirror is unavailable";

                root.mirrorSource = source;
                root.mirrorTarget = output;
                root.mirrorStopping = false;
                root.sessionMirrorOwned = true;
                root.activateSession(output, mode, dnd === "true");
                root.publishMirror("starting", "Starting mirror…");
                mirrorProcess.running = true;
                return "Session started";
            }
            if (root.mirrorActive || mirrorProcess.running)
                return "Stop the current mirror before sharing a window";

            const id = Number(windowId);
            const window = root.knownWindows.find((w) => {
                return w.id === id;
            });
            if (!window || !window.output)
                return "Window unavailable; refresh and try again";

            root.sessionStarting = true;
            // A delayed IPC reply must not resurrect a session that already ended.
            const generation = ++root.sessionGeneration;
            root.publishSession();
            Proc.runCommand("presentationHub.sessionMove", [root.corePath, "move", "--window", String(id), "--output", output], (out, code) => {
                if (generation !== root.sessionGeneration)
                    return;

                if (code !== 0 || !root.knownOutputs.includes(output)) {
                    root.sessionStarting = false;
                    root.publishSession();
                    ToastService.showInfo("Presentation not started", "Could not move the selected window. Check the window and display.");
                    return;
                }
                if (window.output !== output)
                    PluginService.setGlobalVar("presentationHub", "lastMoved", {
                    "id": id,
                    "output": window.output,
                    "target": output
                });

                root.activateSession(output, mode, dnd === "true");
                root.refreshOutputs();
            });
            return "Starting session";
        }

        function endSession() : string {
            root.endSession();
            return "Session ended";
        }

        function showCover(output: string) : string {
            if (!output || !root.knownOutputs.includes(output) || !Quickshell.screens.some((screen) => {
                return screen.name === output;
            }))
                return "Display not connected";

            const path = String(PluginService.loadPluginData("presentationHub", "coverImage", "") || "").trim();
            root.coverImageUrl = path.startsWith("/") ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
            if (root.sessionOutput && !root.coverOutput)
                root.sessionCoverOwned = true;

            root.coverOutput = output;
            root.publishCover();
            return "Audience covered";
        }

        function hideCover() : string {
            root.hideCover();
            return "Audience restored";
        }

        function identify(output: string) : string {
            if (!output || !root.knownOutputs.includes(output) || !Quickshell.screens.some((screen) => {
                return screen.name === output;
            }))
                return "Display not connected";

            root.identifyOutput = output;
            identifyTimer.restart();
            return "Identifying display";
        }

        function testPrompt(output: string) : string {
            if (!root.knownOutputs.includes(output))
                return "Display not connected";

            root.askForOutput(output);
            return "Prompt requested";
        }

        function startMirror(source: string, target: string) : string {
            if (mirrorProcess.running || root.mirrorStopping)
                return "Mirror already running or stopping";

            if (!source || !target || source === target)
                return "Select two different displays";

            if (!root.knownOutputs.includes(source) || !root.knownOutputs.includes(target))
                return "Display not connected; refresh and try again";

            root.mirrorSource = source;
            root.mirrorTarget = target;
            root.mirrorStopping = false;
            if (root.sessionOutput)
                root.sessionMirrorOwned = true;

            root.publishMirror("starting", "Starting mirror…");
            mirrorProcess.running = true;
            return "Starting mirror";
        }

        function checkMirror() : string {
            root.checkMirrorDependency(false);
            return "Checking wl-mirror";
        }

        function stopMirror() : string {
            if (!mirrorProcess.running)
                return "No active mirror";

            root.stopMirror("");
            return "Stopping mirror";
        }

        target: "presentationHub"
    }

    DankModal {
        id: displayPrompt

        property string outputName: ""

        layerNamespace: "dms:plugins:presentationHub"
        useOverlayLayer: true
        modalWidth: 420
        modalHeight: 185
        positioning: "center"
        onBackgroundClicked: () => {
            return close();
        }
        onShouldBeVisibleChanged: {
            if (!shouldBeVisible) {
                Qt.callLater(root.nextPrompt);
            }
        }

        content: Component {
            Item {
                implicitHeight: 185
                width: displayPrompt.modalWidth

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    StyledText {
                        text: "Display connected"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: "Use " + displayPrompt.outputName + " for presentations?"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceVariantText
                    }

                    Row {
                        spacing: Theme.spacingS

                        DButton {
                            text: "Not now"
                            onClicked: displayPrompt.close()
                        }

                        DButton {
                            text: "Use for presentations"
                            onClicked: {
                                if (root.knownOutputs.includes(displayPrompt.outputName))
                                    PluginService.savePluginData("presentationHub", "presentationOutput", displayPrompt.outputName);

                                displayPrompt.close();
                            }
                        }

                    }

                }

            }

        }

    }

    DankModal {
        id: windowPrompt

        property var windowId: null
        property string windowTitle: ""
        property string targetOutput: ""
        property string errorMessage: ""
        property bool isFullscreenBrowser: false

        layerNamespace: "dms:plugins:presentationHub-window"
        useOverlayLayer: true
        modalWidth: 440
        modalHeight: 225
        positioning: "center"
        onBackgroundClicked: () => {
            if (!root.moving)
                close();

        }
        onShouldBeVisibleChanged: {
            if (!shouldBeVisible) {
                Qt.callLater(root.nextPrompt);
            }
        }

        content: Component {
            Item {
                implicitHeight: 225
                width: windowPrompt.modalWidth

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    StyledText {
                        text: windowPrompt.isFullscreenBrowser ? "Fullscreen browser detected" : "Presentation window detected"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: windowPrompt.windowTitle
                        width: parent.width
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: "Move this window to " + windowPrompt.targetOutput + "?"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        visible: windowPrompt.errorMessage !== ""
                        text: windowPrompt.errorMessage
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.error
                    }

                    Row {
                        spacing: Theme.spacingS

                        DButton {
                            text: "Not now"
                            enabled: !root.moving
                            onClicked: windowPrompt.close()
                        }

                        DButton {
                            text: root.moving ? "Moving…" : "Move window"
                            enabled: !root.moving
                            onClicked: {
                                root.moving = true;
                                const id = windowPrompt.windowId;
                                const output = windowPrompt.targetOutput;
                                const original = root.knownWindows.find((w) => {
                                    return w.id === id;
                                });
                                const origin = original ? original.output : "";
                                Proc.runCommand("presentationHub.suggestedMove", [root.corePath, "move", "--window", String(id), "--output", output], (out, code) => {
                                    root.moving = false;
                                    if (code === 0) {
                                        if (origin && origin !== output)
                                            PluginService.setGlobalVar("presentationHub", "lastMoved", {
                                            "id": id,
                                            "output": origin,
                                            "target": output
                                        });

                                        windowPrompt.close();
                                        root.refreshOutputs();
                                    } else {
                                        windowPrompt.errorMessage = "Could not move the window. Check that it and the display are still available.";
                                    }
                                });
                            }
                        }

                    }

                }

            }

        }

    }

}
