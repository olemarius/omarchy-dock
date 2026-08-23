// WorkspaceModel.js — Workspace-grouped dock model for Omarchy Dock
//
// Builds the model behind the dock's "group by workspace" mode: running
// windows partitioned per Hyprland workspace, then grouped per application
// inside each workspace, so two browser windows on workspace 1 collapse into
// a single icon carrying a window count.
//
// The per-app item objects produced here are deliberately the same shape
// DockItem.qml already consumes in flat mode (appId/icon/toplevels/...), so
// the grouped rail reuses the existing tile, icon resolution, activation,
// wheel-cycling and badge behaviour instead of duplicating any of it.

.pragma library
.import "DockModel.js" as DockModel

// Hyprland names its scratchpad/special workspaces with negative ids. They are
// never part of the numbered rail, so they are filtered out everywhere.
function isNormalWorkspaceId(id) {
    var n = Number(id);
    return isFinite(n) && n > 0;
}

// Quickshell hands out its model contents as array-*like* objects rather than
// true Arrays, so Array.isArray() is not enough to recognise a window list.
//
// Order matters here: an array-like inherits Array.prototype.values (an
// iterator *function*), so probing `.values` before length would follow that
// function instead of the contents and quietly yield nothing.
function toArray(list) {
    if (!list) return [];
    if (Array.isArray(list)) return list;
    if (typeof list.length === "number") {
        var out = [];
        for (var i = 0; i < list.length; i++) out.push(list[i]);
        return out;
    }
    // A model object rather than its contents: unwrap it once.
    try {
        if (list.values && typeof list.values !== "function") return toArray(list.values);
    } catch (e) {}
    return [];
}

function safeGet(obj, prop, fallback) {
    try {
        var v = obj ? obj[prop] : undefined;
        return (v === undefined || v === null) ? fallback : v;
    } catch (e) {
        return fallback;
    }
}

// Pair every live Hyprland toplevel with the Wayland toplevel handle the rest
// of the dock speaks in. Hyprland owns the workspace association; Wayland owns
// activate()/close() and the appId, so the dock needs both halves.
function buildWindowWorkspaceIndex(hyprToplevels) {
    var tops = toArray(hyprToplevels);
    var index = { wayland: [], workspaceId: [], address: [] };

    for (var i = 0; i < tops.length; i++) {
        var t = tops[i];
        if (!t) continue;
        var wl = safeGet(t, "wayland", null);
        if (!wl) continue;
        var ws = safeGet(t, "workspace", null);
        index.wayland.push(wl);
        index.workspaceId.push(ws ? Number(safeGet(ws, "id", -1)) : -1);
        index.address.push(normalizeAddress(safeGet(t, "address", "")));
    }
    return index;
}

// Hyprland reports a toplevel address without the 0x its own dispatchers and
// `hyprctl clients` use. Normalise once here so callers can hand it straight
// to a window selector.
function normalizeAddress(address) {
    var a = String(address || "");
    if (!a) return "";
    return a.indexOf("0x") === 0 ? a : "0x" + a;
}

function workspaceIdForWindow(index, waylandToplevel) {
    if (!index || !waylandToplevel) return -1;
    var pos = index.wayland.indexOf(waylandToplevel);
    return pos === -1 ? -1 : index.workspaceId[pos];
}

// Identity used to collapse several windows of the same application into one
// tile. A resolved desktop entry is the strongest signal — it keeps two
// windows of the same app together even when their appIds differ in case —
// and the raw appId is the fallback for windows with no matching entry
// (browser web apps, for instance, keep their own per-app identity).
function appKeyFor(entry, appId) {
    var entryId = entry ? String(safeGet(entry, "id", "")) : "";
    if (entryId) return "entry:" + DockModel.stripDesktop(entryId).toLowerCase();
    return "class:" + String(appId || "").toLowerCase();
}

function findEntryFor(entries, appId) {
    try {
        return DockModel.findEntry(entries, appId);
    } catch (e) {
        return null;
    }
}

// One dock tile: every window of a single application living on a single
// workspace. Shape matches buildDockItems() output so DockItem.qml can render
// it unchanged.
function buildAppItem(appId, entry, windows, addresses, activeToplevel, appLibrary, badgeCounts, urgentCounts) {
    var rawIcon = (entry && entry.icon) ? entry.icon : (appId || "application-x-executable");
    var icon = appId;
    try {
        icon = DockModel.resolveIcon(entry, appId, appLibrary);
    } catch (e) {}
    var firstTitle = windows.length > 0 ? String(safeGet(windows[0], "title", "")) : "";
    var name = (entry && entry.name) ? entry.name : (appId || firstTitle || "App");
    var iconSource = (entry && entry.iconSource) ? entry.iconSource : "";
    var desktopId = (entry && entry.id)
        ? entry.id
        : (appId ? (appId.indexOf(".desktop") !== -1 ? appId : (appId + ".desktop")) : "");
    var exec = (entry && entry.exec) ? entry.exec : "";

    var isActive = false;
    var activeIndex = 0;
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        try {
            if ((activeToplevel && w === activeToplevel) || (w && (w.activated || w.active))) {
                isActive = true;
                activeIndex = i;
            }
        } catch (e) {}
    }

    var badge = { count: 0, hasUrgent: false };
    try {
        badge = DockModel.getBadgeInfo(badgeCounts, urgentCounts, appId, entry, name, desktopId);
    } catch (e) {}

    return {
        id: appId,
        appId: appId,
        desktopId: desktopId,
        exec: exec,
        name: name,
        icon: icon,
        rawIcon: rawIcon,
        iconSource: iconSource,
        isStack: false,
        isPinned: false,
        isDuplicate: false,
        isRunning: true,
        isActive: isActive,
        activeTopIndex: activeIndex,
        windowCount: windows.length,
        badgeCount: badge.count,
        hasUrgent: badge.hasUrgent,
        toplevels: windows,
        // Hyprland window addresses parallel to `toplevels`. The Wayland
        // handles drive focus and close; only Hyprland can move a window to
        // another workspace, and it needs an address to name one.
        addresses: addresses
    };
}

function isExcludedMonitor(excluded, monitorName) {
    if (!excluded || excluded.length === 0) return false;
    var name = String(monitorName || "");
    if (!name) return false;
    for (var i = 0; i < excluded.length; i++) {
        if (String(excluded[i] || "") === name) return true;
    }
    return false;
}

// Which workspaces get a plate, in rail order. Existing workspaces always
// appear; `showEmpty` pads the numbered range so the rail keeps a stable width
// instead of reflowing every time the last window of a workspace closes.
//
// Two independent filters can narrow that set: `monitorName` restricts the
// rail to one monitor, and `excludeMonitors` drops the workspaces of monitors
// the user does not want represented at all.
function workspaceIdsToRender(workspaces, options) {
    var opts = options || {};
    var showEmpty = opts.showEmpty !== false;
    var padTo = Number(opts.padTo);
    if (!isFinite(padTo) || padTo < 0) padTo = 5;
    var monitorName = String(opts.monitorName || "");
    var excluded = toArray(opts.excludeMonitors);

    var list = toArray(workspaces);
    var ids = [];
    var byId = {};
    // Ids that exist but were filtered out. Padding must not resurrect them as
    // empty plates, or excluding a monitor would only hide its windows and
    // leave its workspace numbers sitting on the rail.
    var suppressed = {};

    for (var i = 0; i < list.length; i++) {
        var ws = list[i];
        if (!ws) continue;
        var id = Number(safeGet(ws, "id", -1));
        if (!isNormalWorkspaceId(id)) continue;
        var mon = safeGet(ws, "monitor", null);
        var monName = mon ? String(safeGet(mon, "name", "")) : "";
        if (isExcludedMonitor(excluded, monName)) {
            suppressed[id] = true;
            continue;
        }
        if (monitorName && monName !== monitorName) {
            suppressed[id] = true;
            continue;
        }
        if (byId[id]) continue;
        byId[id] = ws;
        ids.push(id);
    }

    // Padding is only meaningful for the dock's own monitor scope when the
    // compositor has not created the workspace yet; a monitor-scoped rail
    // pads too, since an unopened workspace has no monitor to be filtered by.
    if (showEmpty) {
        for (var p = 1; p <= padTo; p++) {
            if (!byId[p] && !suppressed[p]) {
                byId[p] = null;
                ids.push(p);
            }
        }
    }

    ids.sort(function (a, b) { return a - b; });
    return { ids: ids, byId: byId };
}

// Main entry point.
//
// hyprToplevels  Hyprland.toplevels.values  (carries the workspace link)
// workspaces     Hyprland.workspaces.values
// knownWindows   the dock's stable chronological Wayland toplevel registry,
//                so tiles keep their position instead of reshuffling on focus
// returns        [{ key, workspaceId, name, workspace, isActive, isFocused,
//                   isUrgent, hasFullscreen, monitorName, windowCount, items }]
function buildWorkspaceGroups(hyprToplevels, workspaces, knownWindows, activeToplevel,
                              entries, appLibrary, badgeCounts, urgentCounts, options) {
    var opts = options || {};
    var maxItemsPerGroup = Number(opts.maxItemsPerGroup);
    if (!isFinite(maxItemsPerGroup) || maxItemsPerGroup <= 0) maxItemsPerGroup = 0;
    var hideEmptyPlates = opts.showEmpty === false;

    var index = buildWindowWorkspaceIndex(hyprToplevels);
    var rendered = workspaceIdsToRender(workspaces, opts);
    var windows = toArray(knownWindows);
    var entryList = toArray(entries);

    // Bucket the stable window registry by workspace in one pass.
    var buckets = {};
    for (var w = 0; w < windows.length; w++) {
        var win = windows[w];
        if (!win) continue;
        var pos = index.wayland.indexOf(win);
        if (pos === -1) continue;
        var wsId = index.workspaceId[pos];
        if (!isNormalWorkspaceId(wsId)) continue;
        if (!buckets[wsId]) buckets[wsId] = [];
        buckets[wsId].push({ wayland: win, address: index.address[pos] });
    }

    var groups = [];
    for (var i = 0; i < rendered.ids.length; i++) {
        var id = rendered.ids[i];
        var ws = rendered.byId[id];
        var bucket = buckets[id] || [];

        // Group this workspace's windows per application, preserving the order
        // in which each application's first window appeared.
        var order = [];
        var byKey = {};
        for (var b = 0; b < bucket.length; b++) {
            var top = bucket[b].wayland;
            var appId = String(safeGet(top, "appId", ""));
            var entry = findEntryFor(entryList, appId);
            var key = appKeyFor(entry, appId);
            if (!byKey[key]) {
                byKey[key] = { appId: appId, entry: entry, windows: [], addresses: [] };
                order.push(key);
            }
            byKey[key].windows.push(top);
            byKey[key].addresses.push(bucket[b].address);
        }

        var items = [];
        for (var o = 0; o < order.length; o++) {
            if (maxItemsPerGroup && items.length >= maxItemsPerGroup) break;
            var g = byKey[order[o]];
            items.push(buildAppItem(g.appId, g.entry, g.windows, g.addresses, activeToplevel,
                                    appLibrary, badgeCounts, urgentCounts));
        }

        if (hideEmptyPlates && items.length === 0) continue;

        var monitor = ws ? safeGet(ws, "monitor", null) : null;
        groups.push({
            key: "ws-" + id,
            workspaceId: id,
            name: ws ? String(safeGet(ws, "name", String(id))) : String(id),
            workspace: ws,
            isActive: ws ? safeGet(ws, "active", false) === true : false,
            isFocused: ws ? safeGet(ws, "focused", false) === true : false,
            isUrgent: ws ? safeGet(ws, "urgent", false) === true : false,
            hasFullscreen: ws ? safeGet(ws, "hasFullscreen", false) === true : false,
            monitorName: monitor ? String(safeGet(monitor, "name", "")) : "",
            windowCount: bucket.length,
            items: items
        });
    }

    return groups;
}

function totalItemCount(groups) {
    var list = Array.isArray(groups) ? groups : [];
    var total = 0;
    for (var i = 0; i < list.length; i++) {
        total += (list[i] && list[i].items) ? list[i].items.length : 0;
    }
    return total;
}
