import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "WorkspaceModel.js" as WorkspaceModel
import "components"

Item {
    id: root

    // Properties injected by Omarchy Shell host
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null

    // Live dock surfaces, one per screen, in creation order. The controller owns
    // the model and the settings; anything that has to happen "on every dock" or
    // "on the dock you are looking at" goes through this registry.
    property var dockViews: []

    function registerView(instance) {
        if (!instance) return
        var next = root.dockViews.slice()
        if (next.indexOf(instance) === -1) next.push(instance)
        root.dockViews = next
    }

    function unregisterView(instance) {
        var next = []
        for (var i = 0; i < root.dockViews.length; i++) {
            if (root.dockViews[i] !== instance) next.push(root.dockViews[i])
        }
        root.dockViews = next
    }

    function forEachView(fn) {
        var views = root.dockViews
        for (var i = 0; i < views.length; i++) {
            if (views[i]) fn(views[i])
        }
    }

    // The output Hyprland has focused, which is the dock a keyboard shortcut or
    // a bar-widget toggle means. Empty until Hyprland reports one, which leaves
    // callers on their fallback instead of guessing at an output.
    function focusedScreenName() {
        var monitor = (typeof Hyprland !== "undefined") ? Hyprland.focusedMonitor : null
        return monitor ? String(monitor.name || "") : ""
    }

    // The surface a per-dock action applies to: the focused screen's, falling
    // back to the only dock when there is one, and to the first otherwise.
    function focusedView() {
        var views = root.dockViews
        if (views.length === 0) return null
        var focused = root.focusedScreenName()
        if (focused) {
            for (var i = 0; i < views.length; i++) {
                var candidate = views[i]
                if (candidate && candidate.dockScreen && String(candidate.dockScreen.name || "") === focused) return candidate
            }
        }
        return views[0]
    }

    // Dock state & Multi-source Live Bar Position Tracking
    property bool opened: true
    property bool pluginEnabled: true
    property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    property string detectedBarPosition: "top"
    property bool detectedBarTransparent: false

    // Live bar position (only used to position the dock on the opposite side of the screen)
    property string barPosition: {
        if (shell && shell.bar && shell.bar.position) return shell.bar.position
        if (shell && shell.barConfig && shell.barConfig.position) return shell.barConfig.position
        return detectedBarPosition
    }
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"

    // Live dock edge on screen (opposite to system status bar)
    readonly property string dockScreenPosition: {
        if (root.barPosition === "top") return "bottom"
        if (root.barPosition === "bottom") return "top"
        if (root.barPosition === "left") return "right"
        if (root.barPosition === "right") return "left"
        return "bottom"
    }

    // Live Bar & Tray Transparency Tracking (Auto-syncs dock with bar & tray glassmorphism)
    readonly property bool isBarTransparent: {
        if (shell && shell.bar && shell.bar.transparent !== undefined) return (shell.bar.transparent === true)
        if (shell && shell.barConfig && shell.barConfig.transparent !== undefined) return (shell.barConfig.transparent === true)
        return detectedBarTransparent
    }

    // Static Standard Dock Geometry (Strictly stable, no jumping/twitching on window state)
    readonly property real slotSize: 42
    readonly property real iconBaseSize: 24

    // Live 1D Rail Displacement for Main Dock Bar
    function getDockVisualSlot(itemIdx, dragIdx, targetIdx) {
        if (dragIdx < 0 || targetIdx < 0 || dragIdx === targetIdx) return itemIdx;
        if (itemIdx === dragIdx) return dragIdx;
        if (dragIdx < targetIdx) {
            if (itemIdx > dragIdx && itemIdx <= targetIdx) return itemIdx - 1;
        } else {
            if (itemIdx >= targetIdx && itemIdx < dragIdx) return itemIdx + 1;
        }
        return itemIdx;
    }

    // Live 2D Rail Displacement inside Folder Grid
    function getFolderVisualSlot(itemIdx, dragIdx, targetIdx) {
        if (dragIdx < 0 || targetIdx < 0 || dragIdx === targetIdx) return itemIdx;
        if (itemIdx === dragIdx) return dragIdx;
        if (dragIdx < targetIdx) {
            if (itemIdx > dragIdx && itemIdx <= targetIdx) return itemIdx - 1;
        } else {
            if (itemIdx >= targetIdx && itemIdx < dragIdx) return itemIdx + 1;
        }
        return itemIdx;
    }

    // Direct IPC handler for rosakodu.dock target
    IpcHandler {
        target: "rosakodu.dock"
        function open(): string { root.open(""); return "ok" }
        function close(): string { root.close(); return "ok" }
        function toggle(): string { root.toggle(); return "ok" }
        function refresh(): string { return root.refresh() }
        function openWidgetPicker(): string {
            root.opened = true
            var picker = root.focusedView()
            if (picker) picker.widgetPicker.opened = true
            return "ok"
        }
        function addWidget(widgetId: string): string { root.addDockWidget(widgetId); return "ok" }
        function removeWidget(widgetId: string): string { root.removeDockWidget(widgetId, ""); return "ok" }
        function setShowAppMenu(val: string): string { root.setShowAppMenu(val === "true" || val === "1"); return "ok" }
        function setAppMenuPosition(pos: string): string { root.setAppMenuPosition(pos); return "ok" }
        function setWidgetsEnabled(val: string): string { root.setWidgetsEnabled(val === "true" || val === "1"); return "ok" }
        function setWidgetPosition(pos: string): string { root.setWidgetPosition(pos); return "ok" }
        function setEditMode(val: string): string {
            var target = root.focusedView()
            if (target) target.isEditMode = (val === "true" || val === "1")
            return target ? "ok" : "no-dock"
        }
        function setDockEnabled(val: string): string { root.dockEnabled = (val === "true" || val === "1"); root.saveSettings(); return "ok" }
        function setAutohide(val: string): string { root.autohide = (val === "true" || val === "1"); root.saveSettings(); return "ok" }
        function setAutohideEdgeDepth(val: string): string { var n = parseInt(val, 10); if (!isNaN(n) && n >= 1 && n <= 64) { root.autohideEdgeDepth = n; root.saveSettings(); } return "ok" }
        function setShowFolderTitles(val: string): string { root.showFolderTitles = (val === "true" || val === "1"); root.saveSettings(); return "ok" }
        function setShowBadges(val: string): string { root.showBadges = (val === "true" || val === "1"); root.saveSettings(); return "ok" }
        function setGroupByWorkspace(val: string): string { root.setGroupByWorkspace(val === "true" || val === "1"); return "ok" }
        function setShowEmptyWorkspaces(val: string): string { root.showEmptyWorkspaces = (val === "true" || val === "1"); root.saveSettings(); root.updateDockItems(); return "ok" }
        function setMaxEmptyWorkspaces(val: string): string {
            var maxEmpty = parseInt(val, 10)
            if (isNaN(maxEmpty) || maxEmpty < -1 || maxEmpty > 20) return "invalid"
            root.maxEmptyWorkspaces = maxEmpty
            root.saveSettings()
            root.updateDockItems()
            return "ok"
        }
        function setWorkspaceScope(val: string): string { root.workspaceScope = (val === "monitor") ? "monitor" : "all"; root.saveSettings(); root.updateDockItems(); return "ok" }
        // Comma-separated monitor names, or an empty string to clear.
        function setExcludeMonitors(val: string): string { root.setExcludeMonitors(String(val || "")); return "ok" }
        function setWorkspaceStride(val: string): string {
            var stride = parseInt(val, 10)
            if (isNaN(stride) || stride < 0 || stride > 100) return "invalid"
            root.workspaceStride = stride
            root.saveSettings()
            root.updateDockItems()
            return "ok"
        }
        function setMonitorEnabled(val: string): string {
            var parts = String(val || "").split(":")
            if (parts.length < 2) return "usage: <monitor>:<true|false>"
            root.setMonitorEnabled(parts[0], parts[1] === "true" || parts[1] === "1")
            return "ok"
        }
        function toggleMonitor(): string { root.toggleFocusedMonitor(); return "ok" }
        function listMonitors(): string {
            var out = []
            var mons = (Hyprland.monitors && Hyprland.monitors.values) ? Hyprland.monitors.values : []
            for (var i = 0; i < mons.length; i++) out.push(String(mons[i].name))
            return out.join(",")
        }
        function ping(): string { return "ok" }
    }

    function openWidgetPicker() {
        root.opened = true
        var picker = root.focusedView()
        if (picker) picker.widgetPicker.opened = true
    }

    // Methods called by shell.summon / shell.hide / shell.toggle
    function open(payloadJson) {
        root.opened = true
        if (payloadJson) {
            try {
                var p = (typeof payloadJson === "string") ? JSON.parse(payloadJson) : payloadJson
                if (p && p.action === "openWidgetPicker") {
                    var openPicker = root.focusedView()
                    if (openPicker) openPicker.widgetPicker.opened = true
                } else if (p && p.action === "closeWidgetPicker") {
                    var closePicker = root.focusedView()
                    if (closePicker) closePicker.widgetPicker.opened = false
                }
            } catch(e) {}
        }
    }

    function close() {
        root.opened = false
        root.forEachView(function(instance) { instance.resetInteraction() })
    }

    function toggle() {
        root.opened = !root.opened
        root.forEachView(function(instance) { instance.resetInteraction() })
    }

    // Persistent stable chronological window registry (never reordered on focus or workspace switch)
    property var knownWindows: []
    property string pendingFocusAppId: ""
    property double pendingFocusTimestamp: 0

    function requestFocusOnLaunch(appId) {
        var clean = DockModel.stripDesktop(appId || "").toLowerCase()
        if (!clean) return
        root.pendingFocusAppId = clean
        root.pendingFocusTimestamp = Date.now()
    }

    function syncKnownWindows() {
        var live = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
        var nextKnown = []
        // 1. Preserve existing known windows in their original creation order if still alive
        for (var i = 0; i < root.knownWindows.length; i++) {
            var k = root.knownWindows[i]
            for (var j = 0; j < live.length; j++) {
                if (live[j] === k) {
                    nextKnown.push(k)
                    break
                }
            }
        }
        // 2. Append newly opened windows to the end
        for (var l = 0; l < live.length; l++) {
            var cand = live[l]
            if (cand && nextKnown.indexOf(cand) === -1) {
                nextKnown.push(cand)
            }
        }
        root.knownWindows = nextKnown
        return root.knownWindows
    }

    function activateAppWindow(appId, winIndex) {
        root.syncKnownWindows()
        var tops = root.knownWindows
        var matched = []
        for (var i = 0; i < tops.length; i++) {
            var t = tops[i]
            if (t && DockModel.matchToplevel(t, appId, null)) {
                matched.push(t)
            }
        }
        if (winIndex >= 0 && winIndex < matched.length && matched[winIndex] && matched[winIndex].activate) {
            matched[winIndex].activate()
        }
    }

    // Deterministic Right-Click Menu Toggle (Only for Folders / Stacks icon selection)
    // Standalone plugin lifecycle: enabled by default, disabled ONLY if in disabledPlugins
    function updatePluginEnabled() {
        var reg = root.pluginRegistry || (shell ? shell.pluginRegistry : null)
        if (reg && typeof reg.isEnabled === "function") {
            root.pluginEnabled = reg.isEnabled("rosakodu.dock")
            return
        }
        try {
            var raw = shellConfigFile.text()
            if (raw && raw.length > 0) {
                var cfg = JSON.parse(raw)
                if (cfg) {
                    if (Array.isArray(cfg.disabledPlugins) && cfg.disabledPlugins.indexOf("rosakodu.dock") !== -1) {
                        root.pluginEnabled = false
                        return
                    }
                    if (Array.isArray(cfg.plugins)) {
                        for (var p = 0; p < cfg.plugins.length; p++) {
                            if (cfg.plugins[p] && (cfg.plugins[p].id === "rosakodu.dock" || cfg.plugins[p] === "rosakodu.dock")) {
                                root.pluginEnabled = true
                                return
                            }
                        }
                    }
                    if (cfg.bar && cfg.bar.layout) {
                        for (var s in cfg.bar.layout) {
                            var arr = cfg.bar.layout[s] || []
                            for (var k = 0; k < arr.length; k++) {
                                var entry = arr[k]
                                if (entry && (entry.id === "rosakodu.dock" || entry === "rosakodu.dock")) {
                                    root.pluginEnabled = true
                                    return
                                }
                            }
                        }
                    }
                }
            }
        } catch(e) {}
        root.pluginEnabled = true
    }

    FileView {
        id: shellConfigFile
        path: root.shellConfigPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.updatePluginEnabled()
            try {
                var cfg = JSON.parse(text())
                if (cfg && cfg.bar) {
                    if (cfg.bar.position) root.detectedBarPosition = cfg.bar.position
                    if (cfg.bar.transparent !== undefined) root.detectedBarTransparent = (cfg.bar.transparent === true)
                }
            } catch(e) {}
        }
        onFileChanged: {
            reload()
            root.updatePluginEnabled()
            try {
                var cfg = JSON.parse(text())
                if (cfg && cfg.bar) {
                    if (cfg.bar.position) root.detectedBarPosition = cfg.bar.position
                    if (cfg.bar.transparent !== undefined) root.detectedBarTransparent = (cfg.bar.transparent === true)
                }
            } catch(e) {}
            root.refreshLayers()
        }
    }

    // Autohide Dock & Folder Settings Configuration
    property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/dock-settings.json"
    property bool dockEnabled: true
    property bool autohide: false
    property int autohideEdgeDepth: 1  // pixels from screen edge that trigger dock reveal
    property bool showFolderTitles: true
    property bool showBadges: true
    // Workspace grouping: running windows are laid out per Hyprland workspace,
    // each on its own clickable plate, instead of as one flat pinned rail.
    property bool groupByWorkspace: false
    property bool showEmptyWorkspaces: true
    // Cap on empty plates. A run of untouched workspaces says nothing beyond
    // "there is somewhere free to go", so one is shown by default and the rest
    // are dropped. -1 shows every empty workspace.
    property int maxEmptyWorkspaces: 1
    property int paddedWorkspaceCount: 5
    // "all" shows every workspace; "monitor" restricts the rail to workspaces
    // that currently live on the monitor the dock is displayed on.
    property string workspaceScope: "all"
    // Monitor names (as Hyprland reports them, e.g. "eDP-1") whose workspaces
    // are left off the rail entirely.
    property var excludeMonitors: []
    // Monitors the user has switched the dock off on. Opt-out rather than
    // opt-in, so a newly connected screen gets a dock without being configured
    // first, and an unknown name here is simply inert.
    property var disabledMonitors: []
    // Spanning workspaces. Hyprland cannot put one workspace on two monitors,
    // so multi-monitor setups pair them by offset: workspace 2 on the main
    // screen and 12 on the second are two halves of one idea. Set this to that
    // offset (usually 10) and each plate represents the pair; 0 keeps one
    // plate per workspace.
    property int workspaceStride: 0
    readonly property bool showAppMenu: root.widgetsEnabled && root.dockWidgets && (root.dockWidgets.indexOf("omarchy.apps") !== -1)
    property string appMenuPosition: "left"
    property bool widgetsEnabled: true
    property string widgetPosition: "right"
    property var dockWidgets: []
    property var widgetSavedPositions: ({})
    function getActiveWorkspaceWindowCount() {
        var activeId = -1
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id !== undefined) {
            activeId = Hyprland.focusedWorkspace.id
        } else if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace && Hyprland.focusedMonitor.activeWorkspace.id !== undefined) {
            activeId = Hyprland.focusedMonitor.activeWorkspace.id
        }
        if (activeId === -1) return 0

        var wsList = (Hyprland.workspaces && Hyprland.workspaces.values) ? Hyprland.workspaces.values : []
        for (var i = 0; i < wsList.length; i++) {
            var ws = wsList[i]
            if (ws && ws.id === activeId) {
                if (ws.toplevels && ws.toplevels.values) {
                    return ws.toplevels.values.length
                }
                return 0
            }
        }
        return 0
    }

    property int activeWorkspaceWindowCount: root.getActiveWorkspaceWindowCount()

    function refreshActiveWorkspaceWindowCount() {
        root.activeWorkspaceWindowCount = root.getActiveWorkspaceWindowCount()
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.refreshActiveWorkspaceWindowCount()
            if (root.groupByWorkspace) root.updateDockItems()
        }
        // Workspace switches and window moves change the grouped rail without
        // changing the toplevel list, so the grouped model refreshes on the
        // compositor event stream too (debounced by updateDockItems()).
        function onRawEvent(event) {
            root.refreshActiveWorkspaceWindowCount()
            if (root.groupByWorkspace) root.updateDockItems()
        }
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.refreshActiveWorkspaceWindowCount() }
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.refreshActiveWorkspaceWindowCount() }
    }

    Timer {
        id: workspaceCheckTimer
        interval: 200
        running: root.autohide
        repeat: true
        onTriggered: root.refreshActiveWorkspaceWindowCount()
    }

    readonly property bool isWorkspaceEmpty: root.activeWorkspaceWindowCount === 0
    readonly property var widgetLayout: DockModel.getDockWidgetLayout(root.showAppMenu, root.appMenuPosition, root.widgetsEnabled, root.dockWidgets, root.widgetPosition)
    readonly property var leftWidgetsList: widgetLayout.leftWidgets || []
    readonly property var rightWidgetsList: widgetLayout.rightWidgets || []
    readonly property bool hasLeftWidgets: leftWidgetsList.length > 0
    readonly property bool hasRightWidgets: rightWidgetsList.length > 0
    readonly property bool hasWidgets: hasLeftWidgets || hasRightWidgets

    readonly property bool hasClockOnLeft: hasLeftWidgets && leftWidgetsList.indexOf("omarchy.clock") !== -1
    readonly property bool hasClockOnRight: hasRightWidgets && rightWidgetsList.indexOf("omarchy.clock") !== -1
    readonly property bool hasClockWidget: hasClockOnLeft || hasClockOnRight

    property string clockDisplayText: ""

    TextMetrics {
        id: clockMetrics
        font.family: Style.font.family
        font.pixelSize: 12
        font.weight: Font.Medium
        text: root.clockDisplayText !== "" ? root.clockDisplayText : Qt.formatDateTime(new Date(), "dddd HH:mm")
    }

    readonly property real clockSlotWidth: (hasClockWidget && !root.isVertical)
        ? Math.max(root.slotSize, clockMetrics.advanceWidth + 24)
        : root.slotSize

    function getLeftWidgetOffset(index) {
        var offset = 0
        for (var i = 0; i < index; i++) {
            var id = root.leftWidgetsList[i]
            var dim = (id === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
            offset += dim
        }
        return offset
    }

    function getRightWidgetOffset(index) {
        var offset = 0
        for (var i = 0; i < index; i++) {
            var id = root.rightWidgetsList[i]
            var dim = (id === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
            offset += dim
        }
        return offset
    }

    readonly property real leftWidgetsWidth: {
        if (!hasLeftWidgets) return 0
        var total = 0
        for (var i = 0; i < leftWidgetsList.length; i++) {
            var id = leftWidgetsList[i]
            total += (id === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
        }
        return total
    }

    readonly property real rightWidgetsWidth: {
        if (!hasRightWidgets) return 0
        var total = 0
        for (var i = 0; i < rightWidgetsList.length; i++) {
            var id = rightWidgetsList[i]
            total += (id === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
        }
        return total
    }

    readonly property real leftSeparatorSize: hasLeftWidgets ? 8 : 0
    readonly property real rightSeparatorSize: hasRightWidgets ? 8 : 0
    // Dynamic max items limit for dock bar based on logical screen dimensions & scale (15 items on 1080p @ 1.6x, scales dynamically for Ultrawide 21:9 / 32:9)
    // How many items a dock of this size can hold, once the hosted widgets have
    // taken their slots. Each surface asks for its own screen; the shared model
    // is built to the largest answer so no screen is starved, and a narrower
    // dock renders the prefix that fits it.
    function itemCapacityFor(screenWidth, screenHeight) {
        var used = (hasLeftWidgets ? (leftWidgetsWidth + leftSeparatorSize) : 0)
                 + (hasRightWidgets ? (rightSeparatorSize + rightWidgetsWidth) : 0)
        var available = Math.max(0, (root.isVertical ? screenHeight : screenWidth) - used)
        return Math.max(3, Math.floor(available / root.slotSize))
    }

    readonly property int maxDockItems: {
        var screens = Quickshell.screens
        var best = 3
        for (var i = 0; i < screens.length; i++) {
            var candidate = root.itemCapacityFor(screens[i].width, screens[i].height)
            if (candidate > best) best = candidate
        }
        return best
    }

    onDockEnabledChanged: {
        if (!dockEnabled) root.forEachView(function(instance) { instance.resetInteraction() })
    }

    property bool isSavingSettings: false

    FileView {
        id: settingsFile
        path: root.settingsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.readSettings()
        onFileChanged: {
            if (!root.isSavingSettings) {
                reload()
                root.readSettings()
            }
        }
    }

    Timer {
        id: saveSettingsTimer
        interval: 300
        repeat: false
        onTriggered: root.isSavingSettings = false
    }

    function readSettings() {
        if (root.isSavingSettings) return
        try {
            var txt = settingsFile.text()
            if (txt && txt.trim().length > 0) {
                var s = JSON.parse(txt)
                if (!s || typeof s !== "object") return
                if (s.dockEnabled !== undefined) {
                    root.dockEnabled = (s.dockEnabled === true)
                }
                if (s.autohide !== undefined) {
                    root.autohide = (s.autohide === true)
                }
                if (s.autohideEdgeDepth !== undefined) {
                    var depth = parseInt(s.autohideEdgeDepth, 10)
                    if (!isNaN(depth) && depth >= 1 && depth <= 64) root.autohideEdgeDepth = depth
                }
                if (s.showFolderTitles !== undefined) {
                    root.showFolderTitles = (s.showFolderTitles === true)
                }
                if (s.showBadges !== undefined) {
                    root.showBadges = (s.showBadges === true)
                }
                if (s.groupByWorkspace !== undefined) {
                    root.groupByWorkspace = (s.groupByWorkspace === true)
                }
                if (s.showEmptyWorkspaces !== undefined) {
                    root.showEmptyWorkspaces = (s.showEmptyWorkspaces === true)
                }
                if (s.maxEmptyWorkspaces !== undefined) {
                    var maxEmpty = parseInt(s.maxEmptyWorkspaces, 10)
                    if (!isNaN(maxEmpty) && maxEmpty >= -1 && maxEmpty <= 20) root.maxEmptyWorkspaces = maxEmpty
                }
                if (s.paddedWorkspaceCount !== undefined) {
                    var padCount = parseInt(s.paddedWorkspaceCount, 10)
                    if (!isNaN(padCount) && padCount >= 0 && padCount <= 20) root.paddedWorkspaceCount = padCount
                }
                if (s.workspaceScope !== undefined) {
                    root.workspaceScope = (s.workspaceScope === "monitor") ? "monitor" : "all"
                }
                if (s.excludeMonitors !== undefined && Array.isArray(s.excludeMonitors)) {
                    root.excludeMonitors = s.excludeMonitors
                }
                if (s.disabledMonitors !== undefined && Array.isArray(s.disabledMonitors)) {
                    root.disabledMonitors = s.disabledMonitors
                }
                if (s.workspaceStride !== undefined) {
                    var stride = parseInt(s.workspaceStride, 10)
                    if (!isNaN(stride) && stride >= 0 && stride <= 100) root.workspaceStride = stride
                }
                if (s.appMenuPosition !== undefined) {
                    root.appMenuPosition = s.appMenuPosition
                }
                if (s.widgetPosition !== undefined) {
                    root.widgetPosition = s.widgetPosition
                }
                if (s.widgetsEnabled !== undefined) {
                    root.widgetsEnabled = (s.widgetsEnabled === true)
                }
                if (s.dockWidgets !== undefined && Array.isArray(s.dockWidgets)) {
                    if (!root.widgetsEnabled) {
                        root.dockWidgets = []
                    } else {
                        root.dockWidgets = s.dockWidgets.slice(0, 2)
                    }
                } else if (root.widgetsEnabled) {
                    root.dockWidgets = ["omarchy.apps"]
                }
                if (s.widgetSavedPositions !== undefined && typeof s.widgetSavedPositions === "object") {
                    root.widgetSavedPositions = s.widgetSavedPositions
                }
            }
        } catch(e) {}
    }

    function saveSettings() {
        root.isSavingSettings = true
        saveSettingsTimer.restart()
        var jsonStr = JSON.stringify({
            dockEnabled: root.dockEnabled,
            autohide: root.autohide,
            autohideEdgeDepth: root.autohideEdgeDepth,
            showFolderTitles: root.showFolderTitles,
            showBadges: root.showBadges,
            groupByWorkspace: root.groupByWorkspace,
            showEmptyWorkspaces: root.showEmptyWorkspaces,
            maxEmptyWorkspaces: root.maxEmptyWorkspaces,
            paddedWorkspaceCount: root.paddedWorkspaceCount,
            workspaceScope: root.workspaceScope || "all",
            excludeMonitors: root.excludeMonitors || [],
            disabledMonitors: root.disabledMonitors || [],
            workspaceStride: root.workspaceStride,
            widgetsEnabled: root.widgetsEnabled,
            appMenuPosition: root.appMenuPosition || "left",
            widgetPosition: root.widgetPosition || "right",
            dockWidgets: (root.widgetsEnabled && root.dockWidgets) ? root.dockWidgets.slice(0, 2) : [],
            widgetSavedPositions: root.widgetSavedPositions || {}
        }, null, 2)
        settingsFile.setText(jsonStr + "\n")
    }

    function setShowAppMenu(val) {
        if (val) {
            root.addDockWidget("omarchy.apps")
        } else {
            root.removeDockWidget("omarchy.apps", "")
        }
    }

    function setWidgetsEnabled(val) {
        root.widgetsEnabled = val
        saveSettings()
    }

    function setAppMenuPosition(pos) {
        root.appMenuPosition = (pos === "right") ? "right" : "left"
        saveSettings()
    }

    function setWidgetPosition(pos) {
        root.widgetPosition = (pos === "left") ? "left" : "right"
        saveSettings()
    }

    function addDockWidget(widgetId) {
        root.widgetsEnabled = true
        var currentSaved = JSON.parse(JSON.stringify(root.widgetSavedPositions || {}))

        if (widgetId !== "omarchy.apps") {
            var prevIds = []
            if (root.dockWidgets && root.dockWidgets.length > 0) {
                for (var i = 0; i < root.dockWidgets.length; i++) {
                    var prevId = root.dockWidgets[i]
                    if (prevId && prevId !== "omarchy.apps" && prevId !== widgetId) {
                        prevIds.push(prevId)
                    }
                }
            }
            currentSaved = DockModel.switchDockWidgetInBar(root.shell, widgetId, prevIds, currentSaved, shellConfigFile)
        }

        root.dockWidgets = DockModel.addWidgetToDockList(root.dockWidgets, widgetId)
        root.widgetSavedPositions = currentSaved
        saveSettings()
    }

    function removeDockWidget(widgetId, targetRegion) {
        var next = DockModel.removeWidgetFromDockList(root.dockWidgets, widgetId)
        root.dockWidgets = next.slice()
        if (widgetId !== "omarchy.apps") {
            var currentSaved = JSON.parse(JSON.stringify(root.widgetSavedPositions || {}))
            currentSaved = DockModel.switchDockWidgetInBar(root.shell, "", [widgetId], currentSaved, shellConfigFile)
            root.widgetSavedPositions = currentSaved
        }
        saveSettings()
    }

    function getWidgetSource(widgetId) {
        if (!widgetId || widgetId === "omarchy.apps") return ""
        var manifest = (root.shell && root.shell.pluginRegistry && root.shell.pluginRegistry.installedPlugins) ? root.shell.pluginRegistry.installedPlugins[widgetId] : null
        if (manifest && root.shell && root.shell.pluginRegistry) {
            var ep = root.shell.pluginRegistry.entryPointUrl(manifest, "barWidget")
            if (ep && ep.length > 0) return ep
            var epPanel = root.shell.pluginRegistry.entryPointUrl(manifest, "panel")
            if (epPanel && epPanel.length > 0) return epPanel
        }
        var parts = widgetId.split(".")
        var name = parts.length > 1 ? parts[1] : parts[0]
        if (name === "audio" || name === "bluetooth" || name === "network" || name === "power" || name === "monitor" || name === "tailscale") {
            return "file:///usr/share/omarchy/shell/plugins/panels/" + name + "/Panel.qml"
        }
        return "file:///usr/share/omarchy/shell/plugins/panels/" + name + "/BarWidget.qml"
    }

    function getWidgetIcon(widgetId, item) {
        if (!widgetId) return "󰒓"
        if (widgetId === "omarchy.apps") return "󰀻"
        if (widgetId === "omarchy.monitor") {
            return (Quickshell.screens && Quickshell.screens.length > 1) ? "󰍺" : "󰍹"
        }
        if (widgetId === "omarchy.clock") return "󰥔"
        if (widgetId === "omarchy.tailscale") return "󰖂"
        if (widgetId === "omarchy.network") {
            if (item && item.icon) return item.icon
            return "󰖩"
        }
        if (widgetId === "omarchy.audio") {
            if (item && typeof item.outputIcon === "function") {
                var _snk = item.sink
                var _vol = item.outputVolume
                var _mut = item.outputMuted
                return item.outputIcon()
            }
            return "󰕾"
        }
        if (widgetId === "omarchy.power") {
            if (item && typeof item.batteryIcon === "function") {
                var _chg = item.charging
                var _dis = item.discharging
                var _bf = item.batteryFraction
                return item.batteryIcon()
            }
            return "󰁹"
        }
        if (widgetId === "omarchy.bluetooth") {
            if (item && item.icon) return item.icon
            return "󰂯"
        }
        if (widgetId === "omarchy.weather") {
            if (item) {
                if (item.panelLoader && item.panelLoader.item && item.panelLoader.item.label) return item.panelLoader.item.label
                if (item.label) return item.label
                if (item.symbol) return item.symbol
            }
            return "󰖐"
        }
        if (item && item.icon) return item.icon
        return "󰒓"
    }

    Connections {
        target: root.pluginRegistry ? root.pluginRegistry : (shell ? shell.pluginRegistry : null)
        ignoreUnknownSignals: true
        function onPluginsChanged() { root.updatePluginEnabled() }
    }

    // Safe compositor unmap-remap sequence on orientation shift
    Timer {
        id: remapTimer
        interval: 100
        repeat: false
    }

    onBarPositionChanged: {
        remapTimer.restart()
    }

    // Periodic sync timer for guaranteed real-time layer alignment
    Timer {
        id: syncPollTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.refreshLayers()
        }
    }

    // Real-time Bar Position detection via Hyprland layer shell
    Process {
        id: layersProc
        running: true
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    for (var mon in data) {
                        var levels = data[mon].levels || {}
                        for (var lvl in levels) {
                            var layers = levels[lvl] || []
                            for (var i = 0; i < layers.length; i++) {
                                var l = layers[i]
                                if (l.namespace === "omarchy-bar") {
                                    var newPos = (l.w < l.h) ? (l.x === 0 ? "left" : "right") : (l.y === 0 ? "top" : "bottom")
                                    if (root.detectedBarPosition !== newPos) {
                                        root.detectedBarPosition = newPos
                                    }
                                    return
                                }
                            }
                        }
                    }
                } catch(e) {}
            }
        }
    }

    function refreshLayers() {
        if (!layersProc.running) layersProc.running = true
    }

    // Dynamic system tiling border size & rounding
    property int systemBorderSize: 2
    property int systemRounding: Style.cornerRadius >= 0 ? Style.cornerRadius : 12

    // Unified Edit Mode State (Jiggle Mode across dock and open folders)
    function closeAppWindows(appIdOrItem) {
        if (!appIdOrItem) return
        var toplevels = []
        if (typeof appIdOrItem === "string") {
            for (var i = 0; i < root.dockItems.length; i++) {
                if (root.dockItems[i].appId === appIdOrItem && root.dockItems[i].toplevels) {
                    toplevels = root.dockItems[i].toplevels
                    break
                }
            }
        } else if (appIdOrItem.toplevels) {
            toplevels = appIdOrItem.toplevels
        }
        for (var t = 0; t < toplevels.length; t++) {
            if (toplevels[t].close) toplevels[t].close()
        }
    }

    // Right-Click Menu State

    // Pinned apps persistence
    property string userPinnedPath: Quickshell.env("HOME") + "/.config/omarchy/dock-pinned.json"
    property int iconRevision: 0
    property var pinnedIds: []
    property var dockItems: []

    // Workspace-grouped model. Built from the same window registry as
    // dockItems, so both rails agree on what is running; only the layout and
    // grouping differ.

    // Gap between two workspace plates on the grouped rail.
    readonly property real workspaceGroupGap: 6


    // Workspace id currently under a dragged tile, or -1. Drives the plate
    // highlight and is the drop target when the pointer is released.
    // Which plate sits under a point in window coordinates. The rail's plates
    // are the only children carrying groupData, so the Repeater itself and any
    // future siblings are skipped rather than mis-hit.
    // A tile stands for "this application on this workspace", so dragging it
    // moves every window it represents. `follow = false` keeps the gesture an
    // organising one: the windows move, the user stays where they are.
    // Real workspace a window should land on when dropped on a plate. Without
    // spanning that is just the plate. With spanning, the window keeps the
    // screen it is already on: its current workspace names the screen's block,
    // and only the position within that block changes.
    function targetWorkspaceFor(plateId, currentWorkspaceId) {
        if (root.workspaceStride <= 0) return plateId
        var current = Number(currentWorkspaceId)
        if (!isFinite(current) || current < 1) return plateId
        var block = Math.floor((current - 1) / root.workspaceStride)
        return plateId + block * root.workspaceStride
    }

    function moveItemToWorkspace(itemData, workspaceId) {
        var addresses = (itemData && itemData.addresses) ? itemData.addresses : []
        var sourceIds = (itemData && itemData.workspaceIds) ? itemData.workspaceIds : []
        var moved = 0
        for (var i = 0; i < addresses.length; i++) {
            var address = String(addresses[i] || "")
            if (!address) continue
            var target = root.targetWorkspaceFor(Number(workspaceId), sourceIds[i])
            if (Hyprland.usingLua === true) {
                Hyprland.dispatch("hl.dsp.window.move({ window = \"address:" + address
                    + "\", workspace = \"" + target + "\", follow = false })")
            } else {
                Hyprland.dispatch("movetoworkspacesilent " + target + ",address:" + address)
            }
            moved++
        }
        if (moved === 0) return
        try { Hyprland.refreshToplevels() } catch (e) {}
        root.updateDockItems()
    }

    // Activate one real workspace, preferring the live compositor object and
    // falling back to a dispatch for a workspace that does not exist yet.
    function activateWorkspaceId(realId, liveWorkspaces) {
        var id = Number(realId)
        if (!isFinite(id) || id <= 0) return
        var list = liveWorkspaces || []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && Number(list[i].id) === id && typeof list[i].activate === "function") {
                list[i].activate()
                return
            }
        }
        root.dispatchWorkspace(id)
    }

    // Hyprland configured in Lua (Omarchy's default) no longer parses the
    // legacy `workspace N` dispatcher, so the form has to match the config
    // language the compositor reports.
    function dispatchWorkspace(id) {
        try {
            if (Hyprland.usingLua === true) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
            } else {
                Hyprland.dispatch("workspace " + id)
            }
        } catch (e) {
            Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })")
                + " || hyprctl dispatch workspace " + id)
        }
    }

    // Switching workspace goes through the compositor object when Hyprland
    // knows the workspace, and falls back to a dispatch for a padded workspace
    // that has never been opened and therefore has no object yet.
    function activateWorkspace(groupData) {
        if (!groupData) return

        // A spanning plate holds one workspace per screen. Walk them from the
        // highest id down so focus lands on the lowest - the main screen's
        // half - rather than on whichever screen happened to sort last.
        //
        // The walk uses the plate's expected ids, not only the ones Hyprland
        // has already created: an untouched plate's far half does not exist
        // yet, and skipping it would move just one screen.
        var expected = groupData.expectedRealIds
        if (expected && expected.length > 1) {
            var ordered = []
            for (var i = 0; i < expected.length; i++) ordered.push(Number(expected[i]))
            ordered.sort(function(a, b) { return b - a })
            for (var j = 0; j < ordered.length; j++) {
                root.activateWorkspaceId(ordered[j], groupData.workspaces)
            }
            return
        }

        var ws = groupData.workspace
        if (ws && typeof ws.activate === "function") {
            ws.activate()
            return
        }
        root.dispatchWorkspace(Number(groupData.workspaceId))
    }

    onGroupByWorkspaceChanged: {
        // Quickshell populates the Hyprland toplevel list lazily; ask for it
        // explicitly the moment the grouped rail starts depending on it.
        if (root.groupByWorkspace) {
            try {
                Hyprland.refreshToplevels()
                Hyprland.refreshWorkspaces()
            } catch (e) {}
        }
        root.forEachView(function(instance) { instance.resetInteraction() })
        root.updateDockItems()
    }

    onShowEmptyWorkspacesChanged: root.updateDockItems()
    onWorkspaceScopeChanged: root.updateDockItems()
    onExcludeMonitorsChanged: root.updateDockItems()
    onWorkspaceStrideChanged: root.updateDockItems()
    onMaxEmptyWorkspacesChanged: root.updateDockItems()

    // Turn the dock on or off for one screen. Named rather than indexed so the
    // setting survives monitors being unplugged and reconnected in another order.
    function setMonitorEnabled(monitorName, enabled) {
        var name = String(monitorName || "")
        if (!name) return
        var next = []
        for (var i = 0; i < root.disabledMonitors.length; i++) {
            if (String(root.disabledMonitors[i]) !== name) next.push(root.disabledMonitors[i])
        }
        if (!enabled) next.push(name)
        root.disabledMonitors = next
        root.saveSettings()
    }

    function isMonitorEnabled(monitorName) {
        var name = String(monitorName || "")
        if (!name) return true
        return root.disabledMonitors.indexOf(name) === -1
    }

    // What the bar widget's per-monitor row acts on.
    function toggleFocusedMonitor() {
        var name = root.focusedScreenName()
        if (!name) return
        root.setMonitorEnabled(name, !root.isMonitorEnabled(name))
    }

    function setExcludeMonitors(raw) {
        var parts = String(raw || "").split(",")
        var next = []
        for (var i = 0; i < parts.length; i++) {
            var name = parts[i].trim()
            if (name.length > 0 && next.indexOf(name) === -1) next.push(name)
        }
        root.excludeMonitors = next
        root.saveSettings()
        root.updateDockItems()
    }

    function setGroupByWorkspace(val) {
        root.groupByWorkspace = (val === true)
        root.saveSettings()
    }
    property var appRows: (shell && shell.appLibrary) ? shell.appLibrary.sortedEntries("") : []

    // Curated available symbols for folder icon personalization (Clean monochrome vector glyphs)
    readonly property var availableFolderIcons: ["󰉋", "󰒓", "󰞷", "󰝚", "󰊴", "󰏘", "󰭹", "󰖟", "󰕧", "󰈔", "󰍹", "󰖩", "󰌾", "♥"]

    function resolveIcon(itemObj) {
        if (!itemObj) return Quickshell.iconPath("application-x-executable", true)
        var raw = (typeof itemObj === "string") ? itemObj : (itemObj.rawIcon || itemObj.icon || itemObj.appId || itemObj.id || "")
        if (!raw) return Quickshell.iconPath("application-x-executable", true)
        if (raw.indexOf("://") >= 0) return raw
        if (raw.indexOf("/") === 0) return "file://" + raw

        var cands = (typeof itemObj === "string")
            ? DockModel.getCandidates(itemObj, itemObj, itemObj)
            : DockModel.getCandidates(itemObj.rawIcon, itemObj.icon, itemObj.appId || itemObj.id)

        for (var i = 0; i < cands.length; i++) {
            var c = cands[i]
            if (shell && shell.appLibrary && typeof shell.appLibrary.iconSource === "function") {
                var src = shell.appLibrary.iconSource(c)
                if (src && src.length > 0 && src !== Quickshell.iconPath("application-x-executable", true)) {
                    return src
                }
            }
            var qs = Quickshell.iconPath(c, true)
            if (qs && qs.length > 0 && qs !== Quickshell.iconPath("application-x-executable", true)) {
                return qs
            }
        }

        if (shell && shell.appLibrary && typeof shell.appLibrary.iconSource === "function") {
            var f = shell.appLibrary.iconSource(cands[0])
            if (f && f.length > 0) return f
        }
        var f2 = Quickshell.iconPath(cands[0], true)
        if (f2 && f2.length > 0) return f2
        return Quickshell.iconPath("application-x-executable", true)
    }

    // Exact Geometric Horizontal Center for Stack Popup Card (100% centered over folder icon in dock)
    // Auto-dismiss open folders, folder icon editor, widget panels and edit mode when system notifications / OSD appear
    readonly property var notifService: (root.shell && typeof root.shell.serviceFor === "function") ? root.shell.serviceFor("omarchy.notifications") : null
    readonly property var notifPopupModel: (root.notifService && root.notifService.popupModel) ? root.notifService.popupModel : null
    readonly property int notifPopupCount: notifPopupModel ? notifPopupModel.count : 0

    onNotifPopupCountChanged: {
        if (notifPopupCount > 0) {
            root.forEachView(function(instance) { instance.closePopups() })
        }
    }

    Connections {
        target: root.notifPopupModel ? root.notifPopupModel : null
        ignoreUnknownSignals: true
        function onRowsInserted() {
            root.forEachView(function(instance) { instance.closePopups() })
        }
        function onCountChanged() {
            if (root.notifPopupCount > 0) {
                root.forEachView(function(instance) { instance.closePopups() })
            }
        }
    }

    readonly property bool isOsdOpen: {
        if (!root.shell) return false
        if (root.shell.openPanelIds && root.shell.openPanelIds["omarchy.osd"]) return true
        if (root.shell.appLibrary && root.shell.appLibrary.launchOsdOpen) return true
        if (typeof root.shell.isPluginOpen === "function" && root.shell.isPluginOpen("omarchy.osd")) return true
        return false
    }

    onIsOsdOpenChanged: {
        if (isOsdOpen) {
            root.forEachView(function(instance) { instance.closePopups() })
        }
    }

    readonly property var osdLoader: (root.shell && root.shell.panelLoaders) ? root.shell.panelLoaders["omarchy.osd"] : null
    readonly property var osdItem: (osdLoader && osdLoader.item) ? osdLoader.item : null
    readonly property bool osdItemOpened: (osdItem && osdItem.opened !== undefined) ? osdItem.opened : false

    onOsdItemOpenedChanged: {
        if (osdItemOpened) {
            root.forEachView(function(instance) { instance.closePopups() })
        }
    }

    Connections {
        target: root.shell ? root.shell : null
        function onOpenPanelIdsChanged() {
            if (root.shell && root.shell.openPanelIds) {
                if (root.shell.openPanelIds["omarchy.osd"] || root.shell.openPanelIds["omarchy.notifications"]) {
                    root.forEachView(function(instance) { instance.closePopups() })
                }
            }
        }
    }

    Connections {
        target: (root.shell && root.shell.appLibrary) ? root.shell.appLibrary : null
        function onLaunchOsdOpenChanged() {
            if (root.shell && root.shell.appLibrary && root.shell.appLibrary.launchOsdOpen) {
                root.forEachView(function(instance) { instance.closePopups() })
            }
        }
    }

    function refresh() {
        root.pinnedIds = DockModel.parsePinned(userPinnedFile.text() || "")
        root.refreshLayers()
        root.updatePluginEnabled()
        root.updateDockItems()
        return "ok"
    }

    // Coalescing debounce timer to prevent signal storm while keeping UI instantaneous
    Timer {
        id: batchUpdateTimer
        interval: 16
        repeat: false
        onTriggered: root.doUpdateDockItems()
    }

    function updateDockItems() {
        batchUpdateTimer.restart()
    }

    NotificationTracker {
        id: notifTracker
        shell: root.shell
        knownWindows: root.knownWindows
        onBadgeChanged: root.doUpdateDockItems()
    }

    function clearBadge(itemData) {
        if (notifTracker) notifTracker.clearBadge(itemData)
    }

    function doUpdateDockItems() {
        root.syncKnownWindows()
        var toplevels = root.knownWindows
        var active = ToplevelManager.activeToplevel
        var lib = root.shell ? root.shell.appLibrary : null
        var allEntries = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications && DesktopEntries.applications.values && DesktopEntries.applications.values.length > 0)
            ? DesktopEntries.applications.values
            : (lib && typeof lib.sortedEntries === "function" ? lib.sortedEntries("") : root.appRows)
        root.dockItems = DockModel.buildDockItems(root.pinnedIds, toplevels, active, allEntries, lib, notifTracker.canonicalCounts, notifTracker.canonicalUrgent, root.maxDockItems)
        root.forEachView(function(instance) { instance.rebuildWorkspaceGroups() })

        root.forEachView(function(instance) { instance.refreshOpenPopups() })
    }

    onPinnedIdsChanged: updateDockItems()
    onAppRowsChanged: updateDockItems()
    onShellChanged: {
        root.appRows = (shell && shell.appLibrary) ? shell.appLibrary.sortedEntries("") : []
        root.updateDockItems()
        root.checkAndApplyTheme()
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.updateDockItems() }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root.updateDockItems() }
    }

    Connections {
        target: (typeof Hyprland !== "undefined") ? Hyprland : null
        function onActiveToplevelChanged() { root.updateDockItems() }
        function onRawEvent(event) {
            if (!event || !root.pendingFocusAppId) return
            var name = String(event.name || "")
            if (name === "openwindow") {
                if (Date.now() - root.pendingFocusTimestamp > 8000) {
                    root.pendingFocusAppId = ""
                    return
                }
                var args = String(event.args || "")
                var parts = args.split(",")
                if (parts.length >= 3) {
                    var addr = parts[0].trim()
                    var winClass = parts[2].trim().toLowerCase()
                    var pending = root.pendingFocusAppId.toLowerCase()
                    var normClass = winClass.replace(/[^a-z0-9]/g, "")
                    var normPending = pending.replace(/[^a-z0-9]/g, "")
                    if (winClass === pending || (normPending.length > 0 && (normClass.indexOf(normPending) !== -1 || normPending.indexOf(normClass) !== -1))) {
                        root.pendingFocusAppId = ""
                        var cleanAddr = (addr.indexOf("0x") === 0) ? addr : ("0x" + addr)
                        Util.execDetached("hyprctl dispatch focuswindow address:" + cleanAddr)
                    }
                }
            }
        }
    }

    Connections {
        target: Color
        function onAccentChanged() {
            if (shell && shell.appLibrary && typeof shell.appLibrary.refreshIcons === "function") {
                shell.appLibrary.refreshIcons()
            }
            root.appRows = (shell && shell.appLibrary) ? shell.appLibrary.sortedEntries("") : []
            root.doUpdateDockItems()
        }
        function onForegroundChanged() { root.doUpdateDockItems() }
        function onBackgroundChanged() { root.doUpdateDockItems() }
    }

    Connections {
        target: Style
        function onCornerRadiusChanged() {
            root.systemRounding = Style.cornerRadius > 0 ? Style.cornerRadius : 12
            root.doUpdateDockItems()
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.appRows = (shell && shell.appLibrary) ? shell.appLibrary.sortedEntries("") : (DesktopEntries.applications.values || [])
            root.iconRevision++
            root.updateDockItems()
        }
    }

    Connections {
        target: shell ? shell.appLibrary : null
        enabled: target !== null
        function onAppsChanged() {
            root.appRows = shell.appLibrary.sortedEntries("")
            root.iconRevision++
            root.updateDockItems()
        }
        function onIconIndexChanged() {
            root.iconRevision++
            root.doUpdateDockItems()
        }
    }

    FileView {
        id: themeWatcher
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            if (shell && shell.appLibrary && typeof shell.appLibrary.refreshIcons === "function") {
                shell.appLibrary.refreshIcons()
            }
            root.appRows = (shell && shell.appLibrary) ? shell.appLibrary.sortedEntries("") : []
            root.iconRevision++
            root.doUpdateDockItems()
        }
    }

    property bool isGtkSettingsLoaded: false

    FileView {
        id: gtkSettingsFile
        path: Quickshell.env("HOME") + "/.config/gtk-3.0/settings.ini"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.isGtkSettingsLoaded = true
            root.checkAndApplyTheme()
        }
        onFileChanged: {
            reload()
            root.isGtkSettingsLoaded = true
            root.iconsReady = false
            root.checkAndApplyTheme()
        }
    }

    readonly property string configuredIconTheme: {
        var txt = gtkSettingsFile.text()
        if (!txt) return ""
        var m = txt.match(/gtk-icon-theme-name\s*=\s*([^\r\n]+)/)
        return m ? m[1].trim() : ""
    }

    readonly property bool hasCustomIconTheme: {
        var t = root.configuredIconTheme.toLowerCase()
        return t.length > 0 && t !== "hicolor" && t !== "adwaita" && t !== "gnome"
    }

    property bool isPinnedLoaded: false
    property bool iconsReady: false
    property bool isDockVisualReady: false

    property string activeThemeName: ""

    function checkAndApplyTheme() {
        var txt = gtkSettingsFile.text()
        if (!txt || txt.trim().length === 0) {
            return
        }

        var m = txt.match(/gtk-icon-theme-name\s*=\s*([^\r\n]+)/)
        if (!m) {
            return
        }

        var themeName = m[1].trim()
        var isCustom = themeName.length > 0 && themeName.toLowerCase() !== "hicolor" && themeName.toLowerCase() !== "adwaita" && themeName.toLowerCase() !== "gnome"

        // 1. В первую очередь — проверка сторонних иконок темы, если тема установлена
        if (isCustom) {
            if (shell && shell.appLibrary && shell.appLibrary.iconIndex) {
                var keys = Object.keys(shell.appLibrary.iconIndex)
                if (keys && keys.length > 50) {
                    var curThemeLower = themeName.toLowerCase()
                    var hasThemeIcons = false
                    for (var i = 0; i < keys.length; i++) {
                        var pth = shell.appLibrary.iconIndex[keys[i]]
                        if (pth && pth.toLowerCase().indexOf(curThemeLower) >= 0) {
                            hasThemeIcons = true
                            break
                        }
                    }
                    if (hasThemeIcons) {
                        root.activeThemeName = themeName
                        root.iconRevision++
                        root.doUpdateDockItems()
                        root.iconsReady = true
                        return
                    }
                }
            }
            return
        }

        // 2. Если сторонней темы нет — отображаем стандартные системные иконки
        root.activeThemeName = themeName
        root.doUpdateDockItems()
        root.iconsReady = true
    }

    Timer {
        id: themePollTimer
        interval: 50
        running: !root.iconsReady
        repeat: true
        onTriggered: root.checkAndApplyTheme()
    }

    // Защитный таймер: если фоновый поиск темы затянулся, показываем доступные иконки
    Timer {
        id: iconsSafetyTimer
        interval: 10000
        running: !root.iconsReady
        repeat: false
        onTriggered: {
            if (!root.iconsReady) {
                root.iconRevision++
                root.doUpdateDockItems()
                root.iconsReady = true
            }
        }
    }

    // Задержка показа дока после поднятия плитки окон Hyprland (220мс на анимацию тайлинга)
    Timer {
        id: dockVisualAppearTimer
        interval: 220
        running: root.iconsReady && !root.isDockVisualReady
        repeat: false
        onTriggered: {
            root.isDockVisualReady = true
        }
    }

    Connections {
        target: (shell && shell.appLibrary) ? shell.appLibrary : null
        function onIconIndexChanged() {
            if (!root.iconsReady) {
                root.checkAndApplyTheme()
            } else {
                root.iconRevision++
                root.doUpdateDockItems()
            }
        }
        function onAppsChanged() {
            root.iconRevision++
            root.doUpdateDockItems()
        }
    }

    Component.onCompleted: {
        try {
            var scTxt = shellConfigFile.text()
            if (scTxt && scTxt.trim().length > 0) {
                var sc = JSON.parse(scTxt)
                if (sc && sc.bar) {
                    if (sc.bar.position) root.detectedBarPosition = sc.bar.position
                    if (sc.bar.transparent !== undefined) root.detectedBarTransparent = (sc.bar.transparent === true)
                }
            }
        } catch(e) {}
        try {
            var txt = userPinnedFile.text()
            if (txt && txt.trim().length > 0) {
                var parsed = DockModel.parsePinned(txt)
                if (parsed && parsed.length > 0) {
                    root.pinnedIds = parsed
                    root.isPinnedLoaded = true
                }
            }
        } catch(e) {}
        root.readSettings()
        if (shell && shell.appLibrary && typeof shell.appLibrary.refreshIcons === "function") {
            shell.appLibrary.refreshIcons()
        }
        root.doUpdateDockItems()
    }

    FileView {
        id: userPinnedFile
        path: root.userPinnedPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            var txt = text()
            if (txt && txt.trim().length > 0) {
                var parsed = DockModel.parsePinned(txt)
                root.pinnedIds = parsed
                root.isPinnedLoaded = true
                root.doUpdateDockItems()
            } else {
                root.isPinnedLoaded = true
            }
        }
        onLoadFailed: {
            root.isPinnedLoaded = true
            root.doUpdateDockItems()
        }
        onFileChanged: userPinnedFile.reload()
    }

    function savePinned() {
        var json = DockModel.serializePinned(root.pinnedIds)
        userPinnedFile.setText(json + "\n")
    }

    function setPinned(next) {
        root.pinnedIds = next
        root.savePinned()
        root.doUpdateDockItems()
    }

    readonly property var activeToplevel: ToplevelManager.activeToplevel

    // ---------------------------------------------------------------- per screen
    // One dock surface, and everything that describes *this* dock rather than the
    // plugin as a whole: what the pointer is over, what is being dragged, which
    // folder is open, how wide this screen's rail came out.
    //
    // Sharing any of that across screens is what makes a second dock feel broken -
    // hovering one would reveal the other, and a drag would displace both rails.
    // Everything genuinely common (settings, the pinned list, the item model)
    // stays on the controller and is read from here as root.*.
    component DockScreenView: Item {
        id: view

        // The screen this surface belongs to. Both windows bind to it, so a dock
        // lands on a known output instead of wherever Quickshell defaults to.
        property var dockScreen: null

        readonly property bool monitorEnabled: {
            var name = view.dockScreen ? String(view.dockScreen.name || "") : ""
            if (!name) return true
            return root.disabledMonitors.indexOf(name) === -1
        }

        // This screen's own item cap. The shared model is built to the widest
        // screen's capacity, so a narrower dock takes the prefix that fits it.
        readonly property int maxDockItems: root.itemCapacityFor(view.logicalScreenWidth, view.logicalScreenHeight)
        readonly property var visibleDockItems: root.dockItems.slice(0, view.maxDockItems)

        // Drop every transient interaction. Used when the dock is hidden or
        // disabled, so a surface never comes back mid-drag or mid-edit.
        function resetInteraction() {
            view.activeStackItem = null
            view.activeMenuItem = null
            view.isEditMode = false
            view.isEditingFolderTitle = false
            view.dockDragActiveIndex = -1
            view.dockDragTargetIndex = -1
            view.currentMergeTargetIndex = -1
            view.folderDragActiveIndex = -1
            view.folderDragTargetIndex = -1
            view.workspaceDropTargetId = -1
        }

        // Keep an open folder or window menu pointed at live model data, or
        // close it when the thing it was showing is gone. Per surface: each
        // dock has its own open popup.
        function refreshOpenPopups() {
            var toplevels = root.knownWindows
            var active = ToplevelManager.activeToplevel
            // Refresh active stack item contents if open
            if (view.activeStackItem) {
                var found = false
                for (var i = 0; i < root.dockItems.length; i++) {
                    var it = root.dockItems[i]
                    if (it && (it.id === view.activeStackItem.id || it.appId === view.activeStackItem.appId)) {
                        if (it.isStack && it.subApps && it.subApps.length >= 2) {
                            view.activeStackItem = it
                            view.activeStackItemIndex = i
                            found = true
                        }
                        break
                    }
                }
                if (!found) {
                    view.activeStackItem = null
                    view.folderDragActiveIndex = -1
                    view.folderDragTargetIndex = -1
                }
            }

            // Refresh active menu item (multi-window menu) if open
            if (view.activeMenuItem && !view.activeMenuItem.isStack && view.activeMenuItem.windows) {
                var mAppId = view.activeMenuItem.appId
                var mWinList = []
                for (var mw = 0; mw < toplevels.length; mw++) {
                    var mTop = toplevels[mw]
                    if (mTop && DockModel.matchToplevel(mTop, mAppId, null)) {
                        var mActive = (active && mTop === active)
                        mWinList.push({
                            index: mWinList.length,
                            title: mTop.title || view.activeMenuItem.name || "",
                            isActive: !!mActive
                        })
                    }
                }
                if (mWinList.length === 0) {
                    view.activeMenuItem = null
                } else {
                    view.activeMenuItem = {
                        id: view.activeMenuItem.id,
                        appId: view.activeMenuItem.appId,
                        name: view.activeMenuItem.name,
                        icon: view.activeMenuItem.icon,
                        rawIcon: view.activeMenuItem.rawIcon,
                        isStack: false,
                        windows: mWinList
                    }
                }
            }
        }

        // Grouped-workspace model. Per surface, because a rail scoped to its own
        // monitor has to group that monitor's workspaces - one shared answer
        // cannot be right for both screens at once.
        property var workspaceGroups: []

        onActiveStackItemChanged: {
            if (activeStackItem) {
                if (stackWindow && stackWindow.stackCard) stackWindow.stackCard.forceActiveFocus()
            } else {
                view.isEditingFolderTitle = false
            }
        }

        function rebuildWorkspaceGroups() {
            if (!root.groupByWorkspace) {
                if (view.workspaceGroups.length > 0) view.workspaceGroups = []
                return
            }
            var lib = root.shell ? root.shell.appLibrary : null
            var allEntries = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications && DesktopEntries.applications.values && DesktopEntries.applications.values.length > 0)
                ? DesktopEntries.applications.values
                : (lib && typeof lib.sortedEntries === "function" ? lib.sortedEntries("") : root.appRows)
            var hyprTops = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
            var wsList = (Hyprland.workspaces && Hyprland.workspaces.values) ? Hyprland.workspaces.values : []

            view.workspaceGroups = WorkspaceModel.buildWorkspaceGroups(
                hyprTops,
                wsList,
                root.knownWindows,
                ToplevelManager.activeToplevel,
                allEntries,
                lib,
                notifTracker.canonicalCounts,
                notifTracker.canonicalUrgent,
                {
                    showEmpty: root.showEmptyWorkspaces,
                    maxEmptyPlates: root.maxEmptyWorkspaces,
                    padTo: root.paddedWorkspaceCount,
                    monitorName: (root.workspaceScope === "monitor") ? view.dockMonitorName : "",
                    excludeMonitors: root.excludeMonitors,
                    stride: root.workspaceStride,
                    screenCount: (Hyprland.monitors && Hyprland.monitors.values) ? Hyprland.monitors.values.length : 1,
                    maxItemsPerGroup: 0
                })
        }

        // ------------------------------------------------ controller passthrough
        // The folder popup, window menu and widget picker are handed this view as
        // their `root`, so they reach per-surface state directly. Everything they
        // need that belongs to the plugin as a whole is forwarded here, which keeps
        // those three components unchanged.
        readonly property var controller: root
        readonly property var appMenuPosition: root.appMenuPosition
        readonly property var availableFolderIcons: root.availableFolderIcons
        readonly property var barPosition: root.barPosition
        readonly property var dockEnabled: root.dockEnabled
        readonly property var dockWidgets: root.dockWidgets
        readonly property var iconRevision: root.iconRevision
        readonly property var isBarTransparent: root.isBarTransparent
        readonly property var isVertical: root.isVertical
        readonly property var opened: root.opened
        readonly property var pinnedIds: root.pinnedIds
        readonly property var pluginEnabled: root.pluginEnabled
        readonly property var showBadges: root.showBadges
        readonly property var showFolderTitles: root.showFolderTitles
        readonly property var systemBorderSize: root.systemBorderSize
        readonly property var systemRounding: root.systemRounding
        readonly property var widgetPosition: root.widgetPosition
        function addDockWidget(widgetId) { return root.addDockWidget(widgetId) }
        function clearBadge(itemData) { return root.clearBadge(itemData) }
        function getFolderVisualSlot(itemIdx, dragIdx, targetIdx) { return root.getFolderVisualSlot(itemIdx, dragIdx, targetIdx) }
        function removeDockWidget(widgetId, targetRegion) { return root.removeDockWidget(widgetId, targetRegion) }
        function requestFocusOnLaunch(appId) { return root.requestFocusOnLaunch(appId) }
        function resolveIcon(itemObj) { return root.resolveIcon(itemObj) }
        function setAppMenuPosition(pos) { return root.setAppMenuPosition(pos) }
        function setPinned(next) { return root.setPinned(next) }
        function setWidgetPosition(pos) { return root.setWidgetPosition(pos) }

        onMonitorEnabledChanged: if (!view.monitorEnabled) view.resetInteraction()

        Component.onCompleted: root.registerView(view)
        Component.onDestruction: root.unregisterView(view)

        property int dockDragActiveIndex: -1
        property int dockDragTargetIndex: -1
        property int currentMergeTargetIndex: -1
        property int folderDragActiveIndex: -1
        property int folderDragTargetIndex: -1
        function toggleStack(item, index) {
            view.activeMenuItem = null
            if (!item) {
                view.activeStackItem = null
                return
            }
            var itemId = item.id || item.appId || ""
            if (view.activeStackItem && (view.activeStackItem.id === itemId || view.activeStackItem.appId === itemId || view.activeStackItemIndex === index)) {
                view.activeStackItem = null
            } else {
                view.activeStackItemIndex = index
                if (item.isStack) {
                    view.activeStackItem = item
                }
            }
        }
        function toggleMenu(item, index, fromFolder) {
            if (!item || !item.isStack) {
                view.activeMenuItem = null
                return
            }
            var appId = item.appId || item.id || ""
            if (view.activeMenuItem && view.activeMenuItem.appId === appId) {
                view.activeMenuItem = null
            } else {
                view.activeStackItem = null
                view.isMenuFromFolder = false
                view.activeMenuItemIndex = index
                view.activeMenuItem = item
            }
        }
        property bool isDockHovered: false
        property bool isStackHovered: false
        property bool isMenuHovered: false
        property bool isWidgetPanelHovered: false
        property var loadedWidgetItems: []
        function checkWidgetPanelsOpen() {
            for (var i = 0; i < view.loadedWidgetItems.length; i++) {
                var w = view.loadedWidgetItems[i]
                if (w) {
                    if (w.opened === true) return true
                    if (w.panelLoader && w.panelLoader.item && w.panelLoader.item.opened === true) return true
                    if (w.panel && w.panel.open === true) return true
                }
            }
            return false
        }
        function evaluateHoverState() {
            var anyOpenWidget = checkWidgetPanelsOpen()
            var isDockWinHovered = (!root.autohide || !view.shouldSlideOut) && dockHoverHandler && dockHoverHandler.hovered
            var anyHover = isDockWinHovered || view.isStackHovered || view.isMenuHovered || view.isWidgetPanelHovered || anyOpenWidget
            if (anyHover) {
                autohideLeaveTimer.stop()
                view.isDockHovered = true
            } else {
                autohideLeaveTimer.restart()
            }
        }
        readonly property bool isDockActive: view.isDockHovered || view.isStackHovered || view.isMenuHovered || view.isWidgetPanelHovered || view.checkWidgetPanelsOpen() || (view.dockDragActiveIndex >= 0)
        readonly property bool shouldSlideOut: root.autohide && !view.isDockActive && !root.isWorkspaceEmpty
        function closeAllWidgetPanels() {
            for (var i = 0; i < view.loadedWidgetItems.length; i++) {
                var w = view.loadedWidgetItems[i]
                if (w) {
                    if (typeof w.close === "function") {
                        w.close()
                    }
                    if (w.panelLoader && w.panelLoader.item && typeof w.panelLoader.item.close === "function") {
                        w.panelLoader.item.close()
                    }
                    if (w.panel && typeof w.panel.close === "function") {
                        w.panel.close()
                    }
                }
            }
        }
        onShouldSlideOutChanged: {
            if (shouldSlideOut) {
                view.activeStackItem = null
                view.activeMenuItem = null
                view.isEditingFolderTitle = false
                view.isEditMode = false
                view.closeAllWidgetPanels()
            }
        }
        readonly property real groupedRailExtent: root.isVertical ? workspaceRail.implicitHeight : workspaceRail.implicitWidth
        readonly property real itemsWidth: root.groupByWorkspace
            ? view.groupedRailExtent
            : (root.dockItems.length * root.slotSize)
        readonly property var activeScreen: (dockWindow && dockWindow.screen) ? dockWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        readonly property real logicalScreenWidth: (activeScreen && activeScreen.width > 0) ? activeScreen.width : 1200
        readonly property real logicalScreenHeight: (activeScreen && activeScreen.height > 0) ? activeScreen.height : 675
        readonly property real totalDockDimension: Math.max(root.slotSize,
            (hasLeftWidgets ? (leftWidgetsWidth + leftSeparatorSize) : 0) +
            itemsWidth +
            (hasRightWidgets ? (rightSeparatorSize + rightWidgetsWidth) : 0))
        property bool isEditMode: false
        property var activeMenuItem: null
        property int activeMenuItemIndex: 0
        property bool isMenuFromFolder: false
        property int activeMenuItemFolderIndex: 0
        readonly property bool isMenuOpen: activeMenuItem !== null
        property var activeStackItem: null
        property int activeStackItemIndex: 0
        property bool isEditingFolderTitle: false
        readonly property bool isStackOpen: activeStackItem !== null
        readonly property string dockMonitorName: {
            try {
                if (dockWindow && dockWindow.screen && dockWindow.screen.name) return String(dockWindow.screen.name)
            } catch (e) {}
            return ""
        }
        property int workspaceDropTargetId: -1
        function workspaceGroupAt(sceneX, sceneY) {
            var kids = workspaceRail.children
            for (var i = 0; i < kids.length; i++) {
                var candidate = kids[i]
                if (!candidate || candidate.groupData === undefined || candidate.groupData === null) continue
                var local = candidate.mapFromItem(null, sceneX, sceneY)
                if (local.x >= 0 && local.y >= 0 && local.x < candidate.width && local.y < candidate.height)
                    return candidate
            }
            return null
        }
        function updateWorkspaceDropTarget(sceneX, sceneY) {
            var group = view.workspaceGroupAt(sceneX, sceneY)
            var id = (group && group.groupData) ? Number(group.groupData.workspaceId) : -1
            view.workspaceDropTargetId = isFinite(id) ? id : -1
        }
        function finishWorkspaceDrag(itemData, sourceWorkspaceId, sceneX, sceneY) {
            var target = view.workspaceDropTargetId
            view.workspaceDropTargetId = -1
            if (!itemData || target <= 0) return
            if (target === Number(sourceWorkspaceId)) return
            root.moveItemToWorkspace(itemData, target)
        }
        readonly property real calculatedStackLeft: {
            var screenW = (dockWindow && dockWindow.screen) ? dockWindow.screen.width : 1920
            var dockW = root.isVertical ? (root.slotSize + 4) : (view.totalDockDimension + 8)
            var dockLeft = (screenW - dockW) / 2
            var appBaseOffset = (root.widgetPosition === "left" && root.hasWidgets) ? (root.widgetsWidth + root.separatorSize) : 0
            var iconCenterX = dockLeft + 4 + appBaseOffset + view.activeStackItemIndex * root.slotSize + (root.slotSize / 2)
            var cardW = (stackWindow && stackWindow.stackCard) ? stackWindow.stackCard.width : 180
            return Math.round(Math.max(6, Math.min(screenW - cardW - 6, iconCenterX - cardW / 2)))
        }
        readonly property real calculatedStackTop: {
            var screenH = (dockWindow && dockWindow.screen) ? dockWindow.screen.height : 1080
            var dockH = root.isVertical ? (view.totalDockDimension + 8) : (root.slotSize + 4)
            var dockTop = (screenH - dockH) / 2
            var appBaseOffset = (root.widgetPosition === "left" && root.hasWidgets) ? (root.widgetsWidth + root.separatorSize) : 0
            var iconCenterY = dockTop + 4 + appBaseOffset + view.activeStackItemIndex * root.slotSize + (root.slotSize / 2)
            var cardH = (stackWindow && stackWindow.stackCard) ? stackWindow.stackCard.height : 180
            return Math.round(Math.max(6, Math.min(screenH - cardH - 6, iconCenterY - cardH / 2)))
        }
        function closePopups() {
            view.activeStackItem = null
            view.activeMenuItem = null
            view.isEditMode = false
            view.isEditingFolderTitle = false
            view.folderDragActiveIndex = -1
            view.folderDragTargetIndex = -1
            view.currentMergeTargetIndex = -1
            if (widgetPicker) widgetPicker.opened = false
            view.closeAllWidgetPanels()
        }


        // 1. Outside-click dismissal for Context Menu (closes ONLY the menu)
        HyprlandFocusGrab {
            id: menuGrab
            active: view.isMenuOpen
            windows: [menuWindow]
            onCleared: {
                view.activeMenuItem = null
            }
        }

        // 3. Outside-click & Escape dismissal for Edit Mode
        HyprlandFocusGrab {
            id: editGrab
            active: view.isEditMode && !view.isStackOpen && !view.isMenuOpen
            windows: [dockWindow]
            onCleared: {
                view.isEditMode = false
            }
        }

        onIsEditModeChanged: {
            if (isEditMode) {
                dockSurface.forceActiveFocus()
            }
        }

        onIsStackOpenChanged: {
            if (isStackOpen) {
                if (stackWindow && stackWindow.stackCard) stackWindow.stackCard.forceActiveFocus()
            }
        }

        onIsMenuOpenChanged: {
            if (isMenuOpen) {
                if (menuWindow && menuWindow.menuCard) {
                    menuWindow.menuCard.forceActiveFocus()
                    if (view.activeMenuItem && view.activeMenuItem.isStack) {
                        var curIcon = view.activeMenuItem.icon || "grid"
                        var foundIdx = root.availableFolderIcons.indexOf(curIcon)
                        menuWindow.menuCard.selectedIndex = (foundIdx >= 0) ? foundIdx : 0
                    } else {
                        menuWindow.menuCard.selectedIndex = -1
                    }
                }
            }
        }

        // 1. The Main Solid Dock Window
        PanelWindow {
            id: dockWindow
            screen: view.dockScreen
            visible: root.opened && root.pluginEnabled && root.dockEnabled && view.monitorEnabled
                     && root.isPinnedLoaded && !remapTimer.running

            WlrLayershell.namespace: "omarchy-dock"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: view.isEditMode ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: (root.opened && root.pluginEnabled && root.dockEnabled && root.isPinnedLoaded && visible && (!root.autohide || !view.shouldSlideOut)) ? ExclusionMode.Auto : ExclusionMode.Ignore
            color: "transparent"

            anchors {
                top: root.barPosition === "bottom"
                bottom: root.barPosition === "top"
                left: root.barPosition === "right"
                right: root.barPosition === "left"
            }

            margins {
                bottom: (!root.isVertical && root.barPosition === "top") ? (Style.gapsOut || 5) : 0
                top: (!root.isVertical && root.barPosition === "bottom") ? (Style.gapsOut || 5) : 0
                right: (root.isVertical && root.barPosition === "left") ? (Style.gapsOut || 5) : 0
                left: (root.isVertical && root.barPosition === "right") ? (Style.gapsOut || 5) : 0
            }

            implicitWidth: root.isVertical ? (root.slotSize + 8) : Math.max(root.slotSize + 8, view.totalDockDimension + 14)
            implicitHeight: root.isVertical ? Math.max(root.slotSize + 8, view.totalDockDimension + 14) : (root.slotSize + 8)

            HoverHandler {
                id: dockHoverHandler
                enabled: !root.autohide || !view.shouldSlideOut
                onHoveredChanged: {
                    view.evaluateHoverState()
                }
            }

            // 1.5-second delay before dock autohides when cursor leaves all dock/folder/widget elements
            Timer {
                id: autohideLeaveTimer
                interval: 1500
                repeat: false
                onTriggered: {
                    var anyOpenWidget = view.checkWidgetPanelsOpen()
                    var anyHover = (dockHoverHandler && dockHoverHandler.hovered) || view.isStackHovered || view.isMenuHovered || view.isWidgetPanelHovered || anyOpenWidget
                    if (!anyHover) {
                        view.isDockHovered = false
                    }
                }
            }

            // Main Visual Dock Card
            Rectangle {
                id: dockSurface
                anchors.centerIn: parent
                width: root.isVertical ? (root.slotSize + 4) : Math.max(root.slotSize + 4, view.totalDockDimension + 8)
                height: root.isVertical ? Math.max(root.slotSize + 4, view.totalDockDimension + 8) : (root.slotSize + 4)
                visible: root.opened && root.pluginEnabled && root.dockEnabled && view.monitorEnabled
                         && root.isPinnedLoaded && !remapTimer.running
                opacity: root.isDockVisualReady ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                focus: view.isEditMode

                Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    if (view.isStackOpen) {
                        view.activeStackItem = null
                    }
                    view.isEditMode = false
                }

                color: root.isBarTransparent
                    ? Util.alpha(Color.bar.background, 0.25)
                    : Color.bar.background
                border.width: root.isBarTransparent ? 0 : root.systemBorderSize
                border.color: root.isBarTransparent ? "transparent" : Color.accent
                radius: root.systemRounding
                antialiasing: true
                smooth: true

                Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                Behavior on border.color { ColorAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                Behavior on border.width { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: (view.dockDragActiveIndex >= 0) ? Qt.BlankCursor : (view.isEditMode ? Qt.PointingHandCursor : Qt.ArrowCursor)
                    onClicked: {
                        view.isEditMode = false
                        view.activeMenuItem = null
                        view.activeStackItem = null
                    }
                }

                transform: Translate {
                    id: autohideTranslate
                    x: {
                        if (!root.autohide || !view.shouldSlideOut) return 0
                        if (root.barPosition === "right") return -56
                        if (root.barPosition === "left") return 56
                        return 0
                    }
                    y: {
                        if (!root.autohide || !view.shouldSlideOut) return 0
                        if (root.barPosition === "top") return 56
                        if (root.barPosition === "bottom") return -56
                        return 0
                    }
                    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                Behavior on radius { NumberAnimation { duration: 200 } }

                Item {
                    id: dockContent
                    anchors.centerIn: parent
                    width: root.isVertical ? root.slotSize : view.totalDockDimension
                    height: root.isVertical ? view.totalDockDimension : root.slotSize

                    // 1. Left Dock Active Bar/Tray Widgets
                    Repeater {
                        model: root.leftWidgetsList

                        Item {
                            id: leftWidgetSlotRoot
                            required property string modelData
                            required property int index

                            readonly property real widgetSlotDimension: (modelData === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
                            readonly property real widgetPos: root.getLeftWidgetOffset(index)
                            x: root.isVertical ? 0 : widgetPos
                            y: root.isVertical ? widgetPos : 0
                            width: root.isVertical ? root.slotSize : widgetSlotDimension
                            height: root.isVertical ? widgetSlotDimension : root.slotSize
                            z: 1

                            Item {
                                id: leftWidgetWrapper
                                x: Math.round((parent.width - width) / 2)
                                y: Math.round((parent.height - height) / 2) - 1
                                width: (modelData === "omarchy.clock" && !root.isVertical) ? (leftWidgetSlotRoot.width - 10) : root.iconBaseSize
                                height: (modelData === "omarchy.clock" && root.isVertical) ? (root.slotSize - 8) : root.iconBaseSize
                                scale: leftWidgetSlotMouse.containsMouse ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                Text {
                                    id: leftClockHorizontalLabel
                                    visible: modelData === "omarchy.clock" && !root.isVertical
                                    anchors.centerIn: parent
                                    text: (leftWidgetLoader.item && leftWidgetLoader.item.displayText) ? leftWidgetLoader.item.displayText : (root.clockDisplayText !== "" ? root.clockDisplayText : Qt.formatDateTime(new Date(), "dddd HH:mm"))
                                    font.family: Style.font.family
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: leftWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                    renderType: Text.CurveRendering
                                    font.hintingPreference: Font.PreferNoHinting
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Column {
                                    id: leftClockVerticalCol
                                    visible: modelData === "omarchy.clock" && root.isVertical
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Repeater {
                                        model: (leftWidgetLoader.item && leftWidgetLoader.item.verticalLines && leftWidgetLoader.item.verticalLines.length > 0)
                                               ? leftWidgetLoader.item.verticalLines
                                               : [Qt.formatDateTime(new Date(), "HH"), Qt.formatDateTime(new Date(), "mm")]

                                        Text {
                                            required property string modelData
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData
                                            font.family: Style.font.family
                                            font.pixelSize: modelData.length > 3 ? 9 : 10
                                            font.weight: Font.Medium
                                            color: leftWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                            renderType: Text.CurveRendering
                                            font.hintingPreference: Font.PreferNoHinting
                                        }
                                    }
                                }

                                DockGlyph {
                                    id: leftWidgetGlyph
                                    visible: modelData !== "omarchy.clock"
                                    anchors.centerIn: parent
                                    width: root.iconBaseSize
                                    height: root.iconBaseSize
                                    text: root.getWidgetIcon(modelData, leftWidgetLoader.item)
                                    fontFamily: Style.font.family
                                    fontSize: 22
                                    color: leftWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Loader {
                                    id: leftWidgetLoader
                                    anchors.fill: parent
                                    opacity: 0.0
                                    source: root.getWidgetSource(modelData)
                                    onLoaded: {
                                        if (item) {
                                            view.configureHostedWidget(item, modelData)
                                            if (modelData === "omarchy.clock") {
                                                if (item.displayText !== undefined) root.clockDisplayText = item.displayText
                                                if (item.displayTextChanged) {
                                                    item.displayTextChanged.connect(function() {
                                                        root.clockDisplayText = item.displayText
                                                    })
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: leftWidgetSlotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: view.isEditMode ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (view.isEditMode) {
                                        if (mouse.button === Qt.RightButton) {
                                            view.isEditMode = false
                                        }
                                        return
                                    }
                                    if (modelData === "omarchy.apps") {
                                        if (mouse.button === Qt.RightButton) {
                                            Util.execDetached("omarchy-menu toggle root")
                                        } else {
                                            Util.execDetached("omarchy-menu toggle apps")
                                        }
                                        return
                                    }
                                    var target = leftWidgetLoader.item
                                    if (target) {
                                        view.configureHostedWidget(target, modelData)
                                        if (mouse.button === Qt.RightButton) {
                                            if (typeof target.cycleFormat === "function") {
                                                target.cycleFormat()
                                            }
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            if (target.bar && typeof target.bar.run === "function") {
                                                target.bar.run("omarchy-menu-timezone")
                                            } else {
                                                Util.execDetached("omarchy-menu-timezone")
                                            }
                                        } else {
                                            if (typeof target.togglePanel === "function") {
                                                target.togglePanel()
                                            } else if (typeof target.toggle === "function") {
                                                target.toggle()
                                            } else if (typeof target.open === "function") {
                                                if (target.opened) target.close()
                                                else target.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2. Left Sleek Separator between Left Widgets and Apps
                    Item {
                        id: leftDockSeparator
                        visible: root.hasLeftWidgets
                        opacity: root.hasLeftWidgets ? 1.0 : 0.0
                        x: root.isVertical ? 0 : root.leftWidgetsWidth
                        y: root.isVertical ? root.leftWidgetsWidth : 0
                        width: root.isVertical ? root.slotSize : root.leftSeparatorSize
                        height: root.isVertical ? root.leftSeparatorSize : root.slotSize
                        z: 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.isVertical ? (root.slotSize - 18) : 1.5
                            height: root.isVertical ? 1.5 : (root.slotSize - 18)
                            radius: 0.75
                            color: Color.composed("popups.border", "popups.border-alpha", Color.border, 0.45)
                        }
                    }

                    // 3. Applications & Folders
                    Repeater {
                        model: root.groupByWorkspace ? [] : view.visibleDockItems

                        DockItem {
                            itemData: modelData
                            itemIndex: index
                            totalCount: view.visibleDockItems.length
                            barPosition: root.barPosition
                            shell: root.shell
                            slotSize: root.slotSize
                            iconBaseSize: root.iconBaseSize
                            iconRevision: root.iconRevision
                            iconsReady: root.iconsReady
                            systemBorderSize: root.systemBorderSize
                            systemRounding: root.systemRounding
                            isSelected: (!view.isMenuFromFolder && view.activeMenuItem && (view.activeMenuItem.appId === modelData.appId || view.activeMenuItem.id === modelData.id)) || (view.activeStackItem && (view.activeStackItem.id === modelData.id || view.activeStackItem.appId === modelData.appId))
                            isMergeTarget: (view.currentMergeTargetIndex === index)

                            // 1D Live Rail Displacement (with Left Widget offset)
                            readonly property real appBaseOffset: (root.hasLeftWidgets ? (root.leftWidgetsWidth + root.leftSeparatorSize) : 0)
                            readonly property int visualSlot: (view.dockDragActiveIndex === index) ? index : root.getDockVisualSlot(index, view.dockDragActiveIndex, view.dockDragTargetIndex)
                            x: root.isVertical ? 0 : (appBaseOffset + visualSlot * root.slotSize)
                            y: root.isVertical ? (appBaseOffset + visualSlot * root.slotSize) : 0

                            Behavior on x { enabled: view.dockDragActiveIndex >= 0; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: view.dockDragActiveIndex >= 0; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            isEditMode: view.isEditMode
                            showBadges: root.showBadges
                            dockDragActiveIndex: view.dockDragActiveIndex

                            onEditModeRequested: {
                                view.isEditMode = true
                                view.activeMenuItem = null
                            }

                            onEditModeExitRequested: {
                                view.isEditMode = false
                            }

                            onTogglePinRequested: function(appId) {
                                root.setPinned(DockModel.togglePinned(root.pinnedIds, appId, view.maxDockItems))
                            }

                            onOriginalAppLaunched: function(appId) {
                                root.requestFocusOnLaunch(appId)
                            }

                            onDissolveRequested: function(stackId) {
                                root.setPinned(DockModel.dissolveStack(root.pinnedIds, stackId))
                                view.isEditMode = false
                            }

                            onItemLeftClicked: function(item) {
                                if (item && !item.isStack) {
                                    root.clearBadge(item)
                                }
                                if (item && item.isStack) {
                                    view.toggleStack(item, index)
                                } else {
                                    view.activeStackItem = null
                                    view.activeMenuItem = null
                                    if (view.isEditMode) return
                                }
                            }

                            onItemRightClicked: function(item, targetItem) {
                                if (view.isEditMode) {
                                    view.isEditMode = false
                                    return
                                }
                                if (item && (item.isStack || (item.isRunning && item.toplevels && item.toplevels.length >= 2))) {
                                    view.toggleMenu(item, index, false)
                                }
                            }

                            onDragStarted: function(fromIdx) {
                                view.dockDragActiveIndex = fromIdx
                            }

                            onDragHoverChanged: function(fromIdx, targetIdx, isMergeIntent) {
                                view.dockDragActiveIndex = (targetIdx >= 0) ? fromIdx : -1
                                view.dockDragTargetIndex = isMergeIntent ? -1 : targetIdx
                                view.currentMergeTargetIndex = isMergeIntent ? targetIdx : -1
                            }

                            onMoveRequested: function(fromIdx, toIdx) {
                                view.dockDragActiveIndex = -1
                                view.dockDragTargetIndex = -1
                                view.currentMergeTargetIndex = -1
                                root.setPinned(DockModel.reorderPinned(root.pinnedIds, root.dockItems, fromIdx, toIdx))
                            }

                            onMergeRequested: function(fromIdx, targetIdx) {
                                view.dockDragActiveIndex = -1
                                view.dockDragTargetIndex = -1
                                view.currentMergeTargetIndex = -1
                                root.setPinned(DockModel.mergeIntoStack(root.pinnedIds, root.dockItems, fromIdx, targetIdx))
                            }
                        }
                    }

                    // 3b. Workspace-grouped rail. A positioner rather than the
                    // absolute slot maths of the flat rail: plate width varies with
                    // how many applications a workspace holds, and itemsWidth reads
                    // the measured extent back so separators and the right-hand
                    // widgets keep lining up.
                    Grid {
                        id: workspaceRail
                        visible: root.groupByWorkspace
                        readonly property real railBaseOffset: (root.hasLeftWidgets ? (root.leftWidgetsWidth + root.leftSeparatorSize) : 0)
                        x: root.isVertical ? 0 : railBaseOffset
                        y: root.isVertical ? railBaseOffset : 0
                        z: 1
                        spacing: root.workspaceGroupGap
                        // One row along a horizontal dock, one column along a
                        // vertical one - the same positioner serves both.
                        columns: root.isVertical ? 1 : Math.max(1, view.workspaceGroups.length)

                        Repeater {
                            model: root.groupByWorkspace ? view.workspaceGroups : []

                            WorkspaceGroup {
                                required property var modelData

                                groupData: modelData
                                barPosition: root.barPosition
                                shell: root.shell
                                slotSize: root.slotSize
                                iconBaseSize: root.iconBaseSize
                                iconRevision: root.iconRevision
                                iconsReady: root.iconsReady
                                systemBorderSize: root.systemBorderSize
                                systemRounding: root.systemRounding
                                showBadges: root.showBadges
                                isDropTarget: view.workspaceDropTargetId > 0
                                    && view.workspaceDropTargetId === Number(modelData.workspaceId)

                                onWorkspaceActivated: function(group) { root.activateWorkspace(group) }
                                onItemLaunched: function(appId) { root.requestFocusOnLaunch(appId) }
                                onItemDragMoved: function(itemData, sourceWorkspaceId, sceneX, sceneY) {
                                    view.updateWorkspaceDropTarget(sceneX, sceneY)
                                }
                                onItemDragDropped: function(itemData, sourceWorkspaceId, sceneX, sceneY) {
                                    view.finishWorkspaceDrag(itemData, sourceWorkspaceId, sceneX, sceneY)
                                }
                                onItemDragCanceled: view.workspaceDropTargetId = -1
                            }
                        }
                    }

                    // 4. Right Sleek Separator between Apps and Right Widgets
                    Item {
                        id: rightDockSeparator
                        visible: root.hasRightWidgets
                        opacity: root.hasRightWidgets ? 1.0 : 0.0
                        readonly property real rSepOffset: (root.hasLeftWidgets ? (root.leftWidgetsWidth + root.leftSeparatorSize) : 0) + view.itemsWidth
                        x: root.isVertical ? 0 : rSepOffset
                        y: root.isVertical ? rSepOffset : 0
                        width: root.isVertical ? root.slotSize : root.rightSeparatorSize
                        height: root.isVertical ? root.rightSeparatorSize : root.slotSize
                        z: 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.isVertical ? (root.slotSize - 18) : 1.5
                            height: root.isVertical ? 1.5 : (root.slotSize - 18)
                            radius: 0.75
                            color: Color.composed("popups.border", "popups.border-alpha", Color.border, 0.45)
                        }
                    }

                    // 5. Right Dock Active Bar/Tray Widgets
                    Repeater {
                        model: root.rightWidgetsList

                        Item {
                            id: rightWidgetSlotRoot
                            required property string modelData
                            required property int index

                            readonly property real rWidgetBaseOffset: (root.hasLeftWidgets ? (root.leftWidgetsWidth + root.leftSeparatorSize) : 0) + view.itemsWidth + root.rightSeparatorSize
                            readonly property real rWidgetSlotDimension: (modelData === "omarchy.clock" && !root.isVertical) ? root.clockSlotWidth : root.slotSize
                            readonly property real rWidgetPos: rWidgetBaseOffset + root.getRightWidgetOffset(index)
                            x: root.isVertical ? 0 : rWidgetPos
                            y: root.isVertical ? rWidgetPos : 0
                            width: root.isVertical ? root.slotSize : rWidgetSlotDimension
                            height: root.isVertical ? rWidgetSlotDimension : root.slotSize
                            z: 1

                            Item {
                                id: rightWidgetWrapper
                                x: Math.round((parent.width - width) / 2)
                                y: Math.round((parent.height - height) / 2) - 1
                                width: (modelData === "omarchy.clock" && !root.isVertical) ? (rightWidgetSlotRoot.width - 10) : root.iconBaseSize
                                height: (modelData === "omarchy.clock" && root.isVertical) ? (root.slotSize - 8) : root.iconBaseSize
                                scale: rightWidgetSlotMouse.containsMouse ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                Text {
                                    id: rightClockHorizontalLabel
                                    visible: modelData === "omarchy.clock" && !root.isVertical
                                    anchors.centerIn: parent
                                    text: (rightWidgetLoader.item && rightWidgetLoader.item.displayText) ? rightWidgetLoader.item.displayText : (root.clockDisplayText !== "" ? root.clockDisplayText : Qt.formatDateTime(new Date(), "dddd HH:mm"))
                                    font.family: Style.font.family
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: rightWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                    renderType: Text.CurveRendering
                                    font.hintingPreference: Font.PreferNoHinting
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Column {
                                    id: rightClockVerticalCol
                                    visible: modelData === "omarchy.clock" && root.isVertical
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Repeater {
                                        model: (rightWidgetLoader.item && rightWidgetLoader.item.verticalLines && rightWidgetLoader.item.verticalLines.length > 0)
                                               ? rightWidgetLoader.item.verticalLines
                                               : [Qt.formatDateTime(new Date(), "HH"), Qt.formatDateTime(new Date(), "mm")]

                                        Text {
                                            required property string modelData
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData
                                            font.family: Style.font.family
                                            font.pixelSize: modelData.length > 3 ? 9 : 10
                                            font.weight: Font.Medium
                                            color: rightWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                            renderType: Text.CurveRendering
                                            font.hintingPreference: Font.PreferNoHinting
                                        }
                                    }
                                }

                                DockGlyph {
                                    id: rightWidgetGlyph
                                    visible: modelData !== "omarchy.clock"
                                    anchors.centerIn: parent
                                    width: root.iconBaseSize
                                    height: root.iconBaseSize
                                    text: root.getWidgetIcon(modelData, rightWidgetLoader.item)
                                    fontFamily: Style.font.family
                                    fontSize: 22
                                    color: rightWidgetSlotMouse.containsMouse ? Color.accent : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.95)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Loader {
                                    id: rightWidgetLoader
                                    anchors.fill: parent
                                    opacity: 0.0
                                    source: root.getWidgetSource(modelData)
                                    onLoaded: {
                                        if (item) {
                                            view.configureHostedWidget(item, modelData)
                                            if (modelData === "omarchy.clock") {
                                                if (item.displayText !== undefined) root.clockDisplayText = item.displayText
                                                if (item.displayTextChanged) {
                                                    item.displayTextChanged.connect(function() {
                                                        root.clockDisplayText = item.displayText
                                                    })
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: rightWidgetSlotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: view.isEditMode ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (view.isEditMode) {
                                        if (mouse.button === Qt.RightButton) {
                                            view.isEditMode = false
                                        }
                                        return
                                    }
                                    if (modelData === "omarchy.apps") {
                                        if (mouse.button === Qt.RightButton) {
                                            Util.execDetached("omarchy-menu toggle root")
                                        } else {
                                            Util.execDetached("omarchy-menu toggle apps")
                                        }
                                        return
                                    }
                                    var target = rightWidgetLoader.item
                                    if (target) {
                                        view.configureHostedWidget(target, modelData)
                                        if (mouse.button === Qt.RightButton) {
                                            if (typeof target.cycleFormat === "function") {
                                                target.cycleFormat()
                                            }
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            if (target.bar && typeof target.bar.run === "function") {
                                                target.bar.run("omarchy-menu-timezone")
                                            } else {
                                                Util.execDetached("omarchy-menu-timezone")
                                            }
                                        } else {
                                            if (typeof target.togglePanel === "function") {
                                                target.togglePanel()
                                            } else if (typeof target.toggle === "function") {
                                                target.toggle()
                                            } else if (typeof target.open === "function") {
                                                if (target.opened) target.close()
                                                else target.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Invisible anchor for strictly center-of-screen popup panels
                Item {
                    id: screenCenterAnchor
                    anchors.centerIn: parent
                    width: root.slotSize
                    height: root.slotSize
                    visible: false
                }
            }
        }

        function configureHostedWidget(item, widgetId) {
            if (!item) return
            if (view.loadedWidgetItems.indexOf(item) === -1) view.loadedWidgetItems.push(item)
            if ("bar" in item) item.bar = dockBarContext
            if ("moduleName" in item) item.moduleName = widgetId

            function applyToPanel(p) {
                if (!p) return
                if ("centerOnBar" in p) {
                    p.centerOnBar = true
                }
                if ("bar" in p) {
                    p.bar = dockBarContext
                }
                if ("anchorItem" in p) {
                    p.anchorItem = screenCenterAnchor
                }
                if ("opened" in p && p.openedChanged) {
                    p.openedChanged.connect(function() {
                        view.evaluateHoverState()
                    })
                }
                if ("open" in p && p.openChanged) {
                    p.openChanged.connect(function() {
                        view.evaluateHoverState()
                    })
                }
            }

            function scan(obj) {
                if (!obj) return
                applyToPanel(obj)
                if (obj.panel) {
                    applyToPanel(obj.panel)
                }
                if (obj.data) {
                    for (var i = 0; i < obj.data.length; i++) {
                        var d = obj.data[i]
                        if (d) {
                            applyToPanel(d)
                            if (d.panel) applyToPanel(d.panel)
                        }
                    }
                }
                if (obj.children) {
                    for (var j = 0; j < obj.children.length; j++) {
                        var c = obj.children[j]
                        if (c) {
                            applyToPanel(c)
                            if (c.panel) applyToPanel(c.panel)
                        }
                    }
                }
            }

            scan(item)

            if (item.panelLoader) {
                var handlePanelLoader = function() {
                    if (item.panelLoader && item.panelLoader.item) {
                        scan(item.panelLoader.item)
                    }
                }
                handlePanelLoader()
                item.panelLoader.loaded.connect(handlePanelLoader)
            }
        }

        // Proxy Bar context for hosted widgets (places popup strictly in screen center horizontally/vertically, with Style.gapsOut)
        QtObject {
            id: dockBarContext
            property bool vertical: root.isVertical
            property int barSize: root.slotSize + 8
            property int barH: root.slotSize + 8
            property int barW: root.slotSize + 8
            property string position: root.dockScreenPosition
            property var screen: (root.dockWindow && root.dockWindow.screen) ? root.dockWindow.screen : null
            property var shell: root.shell
            property color foreground: Color.composed("bar.text", "bar.text-alpha", Color.text, 0.9)
            property color barForeground: Color.composed("bar.text", "bar.text-alpha", Color.text, 0.9)
            property color urgent: Color.urgent
            property color muted: Color.muted
            property color accent: Color.accent
            property bool foregroundAnimationEnabled: true
            property string fontFamily: Style.font.family
            property var activePopout: null
            function showTooltip(item, text) {}
            function hideTooltip(item) {}
            function requestPopout(key) { activePopout = key }
            function releasePopout(key) { if (activePopout === key) activePopout = null }
            function isBarWidgetOpen(id) { return false }
            function switchPanelFrom(panel, dir) { return false }
            function run(cmd) { Util.execDetached(cmd) }
        }

        // 2. The Isolated Action Card Popup Overlay Window (Folder Icon Picker)
        FolderMenu {
            id: menuWindow
            root: view
            dockWindow: dockWindow
            stackWindow: stackWindow
        }

        // 3. macOS Stacks Folder Grid Overlay Window (Folder Contents Popup)
        FolderPopup {
            id: stackWindow
            root: view
            dockWindow: dockWindow
        }

        // 4. Widget Picker Popup Menu
        WidgetPickerPopup {
            id: widgetPicker
            root: view
            dockWindow: dockWindow
            shell: root.shell
        }

        // 5. Autohide Edge Trigger — thin invisible strip at screen edge, activates dock reveal
        //    Width/height = autohideEdgeDepth px (1–64). Active only when dock is hidden (shouldSlideOut).
        PanelWindow {
            id: edgeTriggerWindow
            screen: view.dockScreen
            visible: root.opened && root.pluginEnabled && root.dockEnabled && view.monitorEnabled
                     && root.isPinnedLoaded
                     && root.autohide && view.shouldSlideOut

            WlrLayershell.namespace: "omarchy-dock-edge"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            // Anchor to the same edge as the dock, no margins — hug the screen edge
            anchors {
                top:    root.dockScreenPosition === "top"
                bottom: root.dockScreenPosition === "bottom"
                left:   root.dockScreenPosition === "left"
                right:  root.dockScreenPosition === "right"
            }

            margins {
                top: 0
                bottom: 0
                left: 0
                right: 0
            }

            implicitWidth:  root.isVertical ? root.autohideEdgeDepth : Math.max(root.slotSize + 8, view.totalDockDimension + 14)
            implicitHeight: root.isVertical ? Math.max(root.slotSize + 8, view.totalDockDimension + 14) : root.autohideEdgeDepth

            HoverHandler {
                id: edgeTriggerHover
                onHoveredChanged: {
                    if (hovered) {
                        // Cursor reached the screen edge — show the dock
                        view.isDockHovered = true
                        autohideLeaveTimer.stop()
                    }
                }
            }
        }
    }

    // One surface per connected screen. New monitors get a dock by default;
    // disabledMonitors subtracts the ones the user turned off.
    Variants {
        model: Quickshell.screens

        delegate: Component {
            DockScreenView {
                required property var modelData

                dockScreen: modelData
            }
        }
    }

}
