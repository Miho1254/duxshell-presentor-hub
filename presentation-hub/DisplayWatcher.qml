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
    property var fullscreenStarted: ({})
    property var readyFullscreenIds: []
    property bool moving: false
    property string mirrorSource: ""
    property string mirrorTarget: ""
    property bool mirrorStopping: false
    property string mirrorStopMessage: ""
    property bool mirrorActive: false
    property bool mirrorDependencyChecking: false

    function checkMirrorDependency(showNotice) {
        if (mirrorDependencyChecking) return
        mirrorDependencyChecking = true
        PluginService.setGlobalVar("presentationHub", "mirrorDependency", "checking")
        Proc.runCommand("presentationHub.mirrorDependency", ["sh", "-c", "command -v wl-mirror >/dev/null 2>&1"], (out, code) => {
            root.mirrorDependencyChecking = false
            const state = code === 0 ? "available" : "missing"
            PluginService.setGlobalVar("presentationHub", "mirrorDependency", state)
            if (showNotice && state === "missing")
                ToastService.showInfo("Duplicate needs wl-mirror", "Install wl-mirror to enable Duplicate. Window moving is still available.")
        })
    }

    function publishMirror(state, message) {
        mirrorActive = state === "starting" || state === "running" || state === "stopping"
        if (mirrorActive) {
            // Do not surface queued suggestions during or just after duplication.
            pendingWindows = []
            for (const window of knownWindows) {
                if ((window.presentation_candidate || fullscreenIds.includes(window.id)) && !suggestedIds.includes(window.id))
                    suggestedIds = suggestedIds.concat([window.id])
            }
            if (windowPrompt.shouldBeVisible && !moving) windowPrompt.close()
        }
        PluginService.setGlobalVar("presentationHub", "mirror", { state: state, source: mirrorSource, target: mirrorTarget, message: message || "" })
    }

    function stopMirror(reason) {
        if (!mirrorProcess.running) return
        mirrorStopping = true
        mirrorStopMessage = reason || "Mirror stopped."
        publishMirror("stopping", "Stopping mirror…")
        mirrorProcess.running = false
    }

    function askForOutput(name) {
        if (displayPrompt.shouldBeVisible && displayPrompt.outputName === name) return
        if (!pendingOutputs.includes(name)) pendingOutputs = pendingOutputs.concat([name])
        nextPrompt()
    }

    function nextPrompt() {
        if (displayPrompt.shouldBeVisible || windowPrompt.shouldBeVisible) return
        while (pendingOutputs.length > 0) {
            const name = pendingOutputs[0]
            pendingOutputs = pendingOutputs.slice(1)
            if (knownOutputs.includes(name)) {
                displayPrompt.outputName = name
                displayPrompt.open()
                return
            }
        }
        if (mirrorActive) return
        const target = PluginService.loadPluginData("presentationHub", "presentationOutput", "")
        while (pendingWindows.length > 0) {
            const candidate = pendingWindows[0]
            pendingWindows = pendingWindows.slice(1)
            const current = knownWindows.find(w => w.id === candidate.id)
            const eligible = current && (current.presentation_candidate || readyFullscreenIds.includes(current.id))
            if (target && knownOutputs.includes(target) && eligible && current.output && current.output !== target) {
                windowPrompt.windowId = current.id
                windowPrompt.windowTitle = current.title || current.app_id || "Untitled window"
                windowPrompt.targetOutput = target
                windowPrompt.isFullscreenBrowser = fullscreenIds.includes(current.id)
                windowPrompt.errorMessage = ""
                windowPrompt.open()
                return
            }
        }
    }

    function isExternal(name) {
        const lower = name.toLowerCase()
        return !lower.startsWith("edp-") && !lower.startsWith("lvds-") && !lower.startsWith("dsi-")
    }

    function isBrowser(appId) {
        const app = (appId || "").toLowerCase()
        const configured = String(PluginService.loadPluginData("presentationHub", "additionalBrowserAppIds", "") || "")
            .split(",").map(value => value.trim().toLowerCase()).filter(value => value !== "")
        if (configured.includes(app)) return true
        return ["firefox", "chrom", "brave", "vivaldi", "microsoft-edge", "zen", "floorp", "librewolf", "waterfox", "tor-browser", "epiphany", "opera", "qutebrowser", "falkon"].some(name => app.includes(name))
    }

    // Wayland toplevel handles do not expose the Niri window ID. Only join
    // when app ID and title identify exactly one window on both sides.
    function fullscreenBrowserIds(windows) {
        const tops = Array.from(ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [])
        const result = []
        for (const top of tops) {
            if (!top.fullscreen || !top.title || !isBrowser(top.appId)) continue
            const matches = windows.filter(w => w.app_id === top.appId && w.title === top.title)
            const peers = tops.filter(t => t.appId === top.appId && t.title === top.title)
            if (matches.length === 1 && peers.length === 1) result.push(matches[0].id)
        }
        return result
    }

    function refreshOutputs() {
        if (checking) return
        checking = true
        Proc.runCommand("presentationHub.watchOutputs", [corePath, "snapshot"], (out, code) => {
            root.checking = false
            root.checks++
            if (code !== 0) { root.lastError = "Core snapshot failed: " + code; return }
            root.lastError = ""
            try {
                const state = JSON.parse(out)
                const outputs = state.outputs.map(o => o.name)
                const previous = root.knownOutputs
                root.knownOutputs = outputs
                if (mirrorProcess.running && (!outputs.includes(root.mirrorSource) || !outputs.includes(root.mirrorTarget)))
                    root.stopMirror("Display disconnected; mirror stopped.")
                root.knownWindows = state.windows
                root.fullscreenIds = root.fullscreenBrowserIds(state.windows)
                const now = Date.now()
                const starts = {}
                let waiting = false
                for (const id of root.fullscreenIds) {
                    starts[id] = root.fullscreenStarted[id] || now
                    if (now - starts[id] < 450) waiting = true
                }
                root.fullscreenStarted = starts
                root.readyFullscreenIds = root.fullscreenIds.filter(id => now - starts[id] >= 450)
                if (waiting && !fullscreenSettle.running) fullscreenSettle.start()
                const ids = state.windows.map(w => w.id)
                root.suggestedIds = root.suggestedIds.filter(id => state.windows.some(w => w.id === id && (w.presentation_candidate || root.fullscreenIds.includes(id))))
                if (root.mirrorActive) {
                    for (const window of state.windows) {
                        if ((window.presentation_candidate || root.fullscreenIds.includes(window.id)) && !root.suggestedIds.includes(window.id))
                            root.suggestedIds = root.suggestedIds.concat([window.id])
                    }
                }
                if (root.initialized) {
                    for (const name of outputs) {
                        if (!previous.includes(name) && root.isExternal(name)) {
                            root.askForOutput(name)
                        }
                    }
                    const target = PluginService.loadPluginData("presentationHub", "presentationOutput", "")
                    if (!root.mirrorActive && target && outputs.includes(target)) {
                        for (const window of state.windows) {
                            if ((window.presentation_candidate || root.readyFullscreenIds.includes(window.id)) && window.output && window.output !== target && !root.suggestedIds.includes(window.id)) {
                                root.suggestedIds = root.suggestedIds.concat([window.id])
                                root.pendingWindows = root.pendingWindows.concat([{ id: window.id }])
                            }
                        }
                    }
                } else {
                    root.suggestedIds = state.windows.filter(w => w.presentation_candidate || root.fullscreenIds.includes(w.id)).map(w => w.id)
                }
                if (root.initialized && JSON.stringify(previous) !== JSON.stringify(outputs))
                    console.info("Presentation Hub: outputs changed", JSON.stringify(outputs))
                if (displayPrompt.shouldBeVisible && !outputs.includes(displayPrompt.outputName)) displayPrompt.close()
                if (windowPrompt.shouldBeVisible && (!outputs.includes(windowPrompt.targetOutput) || !ids.includes(windowPrompt.windowId) || (windowPrompt.isFullscreenBrowser && !root.fullscreenIds.includes(windowPrompt.windowId)))) windowPrompt.close()
                root.initialized = true
                root.nextPrompt()
            } catch (e) {
                console.warn("Presentation Hub: invalid display snapshot", e)
            }
        })
    }

    Timer { interval: 3000; running: true; repeat: true; onTriggered: root.refreshOutputs() }
    Timer { id: fullscreenSettle; interval: 500; repeat: false; onTriggered: root.refreshOutputs() }
    Timer { id: fullscreenDebounce; interval: 150; repeat: false; onTriggered: root.refreshOutputs() }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { fullscreenDebounce.restart() }
    }
    Connections {
        target: ToplevelManager.activeToplevel
        function onFullscreenChanged() { fullscreenDebounce.restart() }
        function onTitleChanged() { fullscreenDebounce.restart() }
    }
    Component.onCompleted: { publishMirror("idle", ""); refreshOutputs(); checkMirrorDependency(true) }

    Process {
        id: mirrorProcess
        // Arguments are passed separately: output names cannot become shell code.
        command: ["sh", "-c", "exec wl-mirror --fullscreen-output \"$2\" \"$1\"", "presentation-hub", root.mirrorSource, root.mirrorTarget]
        stderr: StdioCollector { id: mirrorError }
        onStarted: root.publishMirror("running", "Mirror process running")
        onExited: (exitCode) => {
            const wasStopped = root.mirrorStopping
            root.mirrorStopping = false
            if (wasStopped) root.publishMirror("idle", root.mirrorStopMessage)
            else {
                root.publishMirror("error", exitCode === 127 ? "wl-mirror is not installed. Install it and try again." : "Mirror stopped unexpectedly (exit " + exitCode + "). Check wl-mirror and display availability.")
                if (exitCode === 127) root.checkMirrorDependency(false)
            }
        }
    }

    IpcHandler {
        target: "presentationHub"
        function status(): string {
            return JSON.stringify({ ready: root.initialized, outputs: root.knownOutputs, checks: root.checks, lastError: root.lastError, fullscreenIds: root.fullscreenIds, suggestedIds: root.suggestedIds, windowPromptVisible: windowPrompt.shouldBeVisible, promptedWindowId: windowPrompt.shouldBeVisible ? windowPrompt.windowId : null, mirror: PluginService.getGlobalVar("presentationHub", "mirror", { state: "idle" }), mirrorDependency: PluginService.getGlobalVar("presentationHub", "mirrorDependency", "checking") })
        }
        function testPrompt(output: string): string {
            if (!root.knownOutputs.includes(output)) return "Display not connected"
            root.askForOutput(output)
            return "Prompt requested"
        }
        function startMirror(source: string, target: string): string {
            if (mirrorProcess.running || root.mirrorStopping) return "Mirror already running or stopping"
            if (!source || !target || source === target) return "Select two different displays"
            if (!root.knownOutputs.includes(source) || !root.knownOutputs.includes(target)) return "Display not connected; refresh and try again"
            root.mirrorSource = source
            root.mirrorTarget = target
            root.mirrorStopping = false
            root.publishMirror("starting", "Starting mirror…")
            mirrorProcess.running = true
            return "Starting mirror"
        }
        function checkMirror(): string {
            root.checkMirrorDependency(false)
            return "Checking wl-mirror"
        }
        function stopMirror(): string {
            if (!mirrorProcess.running) return "No active mirror"
            root.stopMirror("")
            return "Stopping mirror"
        }
    }

    DankModal {
        id: displayPrompt
        property string outputName: ""
        layerNamespace: "dms:plugins:presentationHub"
        useOverlayLayer: true
        modalWidth: 420
        modalHeight: 185
        positioning: "center"
        onBackgroundClicked: () => close()
        onShouldBeVisibleChanged: if (!shouldBeVisible) Qt.callLater(root.nextPrompt)
        content: Component {
            Item {
                implicitHeight: 185
                width: displayPrompt.modalWidth
                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM
                    StyledText { text: "Display connected"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium }
                    StyledText { text: "Use " + displayPrompt.outputName + " for presentations?"; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
                    Row {
                        spacing: Theme.spacingS
                        DButton { text: "Not now"; onClicked: displayPrompt.close() }
                        DButton {
                            text: "Use for presentations"
                            onClicked: {
                                if (root.knownOutputs.includes(displayPrompt.outputName))
                                    PluginService.savePluginData("presentationHub", "presentationOutput", displayPrompt.outputName)
                                displayPrompt.close()
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
        onBackgroundClicked: () => { if (!root.moving) close() }
        onShouldBeVisibleChanged: if (!shouldBeVisible) Qt.callLater(root.nextPrompt)
        content: Component {
            Item {
                implicitHeight: 225
                width: windowPrompt.modalWidth
                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM
                    StyledText { text: windowPrompt.isFullscreenBrowser ? "Fullscreen browser detected" : "Presentation window detected"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium }
                    StyledText { text: windowPrompt.windowTitle; width: parent.width; maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.WordWrap; color: Theme.surfaceText }
                    StyledText { text: "Move this window to " + windowPrompt.targetOutput + "?"; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
                    StyledText { visible: windowPrompt.errorMessage !== ""; text: windowPrompt.errorMessage; width: parent.width; wrapMode: Text.WordWrap; color: Theme.error }
                    Row {
                        spacing: Theme.spacingS
                        DButton { text: "Not now"; enabled: !root.moving; onClicked: windowPrompt.close() }
                        DButton {
                            text: root.moving ? "Moving…" : "Move window"
                            enabled: !root.moving
                            onClicked: {
                                root.moving = true
                                const id = windowPrompt.windowId
                                const output = windowPrompt.targetOutput
                                Proc.runCommand("presentationHub.suggestedMove", [root.corePath, "move", "--window", String(id), "--output", output], (out, code) => {
                                    root.moving = false
                                    if (code === 0) { windowPrompt.close(); root.refreshOutputs() }
                                    else windowPrompt.errorMessage = "Could not move the window. Check that it and the display are still available."
                                })
                            }
                        }
                    }
                }
            }
        }
    }
}
