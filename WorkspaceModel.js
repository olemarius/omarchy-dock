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
function buildAppItem(appId, entry, windows, addresses, workspaceIds, activeToplevel, appLibrary, badgeCounts, urgentCounts) {
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
        addresses: addresses,
        // The real workspace each window sits on, also parallel. On a spanning
        // rail this is what says which screen a window belongs to, so moving it
        // to another plate can keep it on its own screen.
        workspaceIds: workspaceIds
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

// Which plate a real workspace belongs to.
//
// With `stride` at 0 a plate is simply one workspace. With a stride the rail
// is showing *spanning* workspaces: Hyprland cannot put one workspace on two
// monitors, so a multi-monitor setup pairs them by offset - workspace 2 on the
// main screen and 12 on the second are two halves of the same idea. Those
// halves collapse onto one plate, so the rail shows what the user thinks of
// as "workspace 2" rather than both of its pieces.
//
// Returns 0 for ids outside the scheme, which keeps unrelated workspaces off
// the rail instead of folding them into an unrelated plate.
function plateIdFor(workspaceId, stride, plateCount) {
    var id = Number(workspaceId);
    if (!isFinite(id) || id < 1) return 0;
    if (!stride || stride <= 0) return id;
    var plate = ((id - 1) % stride) + 1;
    if (plateCount > 0 && plate > plateCount) return 0;
    return plate;
}

// Which plates the rail shows, in order, and which real workspaces feed each.
//
// Existing workspaces always appear; `showEmpty` pads the numbered range so
// the rail keeps a stable width instead of reflowing every time the last
// window of a workspace closes. Two filters can narrow the set: `monitorName`
// restricts the rail to one monitor, and `excludeMonitors` drops the
// workspaces of monitors the user does not want represented at all.
function platesToRender(workspaces, options) {
    var opts = options || {};
    var showEmpty = opts.showEmpty !== false;
    var padTo = Number(opts.padTo);
    if (!isFinite(padTo) || padTo < 0) padTo = 5;
    var stride = Number(opts.stride);
    if (!isFinite(stride) || stride < 0) stride = 0;
    var monitorName = String(opts.monitorName || "");
    var excluded = toArray(opts.excludeMonitors);
    var plateCount = stride > 0 ? (padTo > 0 ? padTo : stride) : 0;

    var list = toArray(workspaces);
    var ids = [];
    var members = {};
    // Real workspace ids dropped by a filter, so their windows can be kept off
    // the rail without also excluding windows on workspaces the compositor
    // simply has not told us about yet.
    var filtered = {};
    // Plates whose every real workspace was filtered out. Padding must not
    // resurrect them as empty plates, or excluding a monitor would only hide
    // its windows and leave its workspace numbers sitting on the rail.
    var suppressed = {};

    for (var i = 0; i < list.length; i++) {
        var ws = list[i];
        if (!ws) continue;
        var id = Number(safeGet(ws, "id", -1));
        if (!isNormalWorkspaceId(id)) continue;

        var plate = plateIdFor(id, stride, plateCount);
        if (plate < 1) continue;

        var mon = safeGet(ws, "monitor", null);
        var monName = mon ? String(safeGet(mon, "name", "")) : "";
        if (isExcludedMonitor(excluded, monName) || (monitorName && monName !== monitorName)) {
            if (!members[plate]) suppressed[plate] = true;
            filtered[id] = true;
            continue;
        }

        if (!members[plate]) {
            members[plate] = [];
            ids.push(plate);
        }
        delete suppressed[plate];
        members[plate].push(ws);
    }

    if (showEmpty) {
        for (var p = 1; p <= padTo; p++) {
            if (!members[p] && !suppressed[p]) {
                members[p] = [];
                ids.push(p);
            }
        }
    }

    ids.sort(function (a, b) { return a - b; });
    return { ids: ids, members: members, filtered: filtered, stride: stride, plateCount: plateCount };
}

// The real workspaces a plate stands for, whether or not the compositor has
// created them yet.
//
// Hyprland only reports workspaces it has actually opened, so the far screen's
// half of an untouched plate is usually absent from the workspace list. Its id
// is still perfectly predictable from the stride, and a plate has to know it:
// otherwise clicking an untouched plate would move only the screen whose half
// happened to exist.
function expectedRealIdsFor(plateId, stride, screenCount) {
    var plate = Number(plateId);
    if (!isFinite(plate) || plate < 1) return [];
    if (!stride || stride <= 0) return [plate];
    var screens = Number(screenCount);
    if (!isFinite(screens) || screens < 1) screens = 1;
    var out = [];
    for (var i = 0; i < screens; i++) out.push(plate + i * stride);
    return out;
}

// Main entry point.
//
// hyprToplevels  Hyprland.toplevels.values  (carries the workspace link)
// workspaces     Hyprland.workspaces.values
// knownWindows   the dock's stable chronological Wayland toplevel registry,
//                so tiles keep their position instead of reshuffling on focus
// returns        [{ key, workspaceId, name, workspace, workspaces, realIds,
//                   isActive, isFocused, isUrgent, hasFullscreen, monitorName,
//                   windowCount, items }]
function buildWorkspaceGroups(hyprToplevels, workspaces, knownWindows, activeToplevel,
                              entries, appLibrary, badgeCounts, urgentCounts, options) {
    var opts = options || {};
    var maxItemsPerGroup = Number(opts.maxItemsPerGroup);
    if (!isFinite(maxItemsPerGroup) || maxItemsPerGroup <= 0) maxItemsPerGroup = 0;
    // How many empty plates the rail is willing to show. A trailing run of
    // untouched workspaces carries no information beyond "there is somewhere
    // free to go", so one is enough; the rest only cost rail width.
    // -1 means no limit, 0 none at all.
    var maxEmptyPlates = opts.showEmpty === false ? 0 : Number(opts.maxEmptyPlates);
    if (!isFinite(maxEmptyPlates)) maxEmptyPlates = -1;
    var emptyShown = 0;

    var index = buildWindowWorkspaceIndex(hyprToplevels);
    var rendered = platesToRender(workspaces, opts);
    var windows = toArray(knownWindows);
    var entryList = toArray(entries);

    // Bucket the stable window registry per plate in one pass.
    var buckets = {};
    for (var w = 0; w < windows.length; w++) {
        var win = windows[w];
        if (!win) continue;
        var pos = index.wayland.indexOf(win);
        if (pos === -1) continue;
        var wsId = index.workspaceId[pos];
        if (!isNormalWorkspaceId(wsId)) continue;
        if (rendered.filtered[wsId]) continue;
        var bucketPlate = plateIdFor(wsId, rendered.stride, rendered.plateCount);
        if (bucketPlate < 1) continue;
        if (!buckets[bucketPlate]) buckets[bucketPlate] = [];
        buckets[bucketPlate].push({ wayland: win, address: index.address[pos], workspaceId: wsId });
    }

    var groups = [];
    for (var i = 0; i < rendered.ids.length; i++) {
        var id = rendered.ids[i];
        var memberWorkspaces = rendered.members[id] || [];
        var bucket = buckets[id] || [];

        // Group this plate's windows per application, preserving the order in
        // which each application's first window appeared.
        var order = [];
        var byKey = {};
        for (var b = 0; b < bucket.length; b++) {
            var top = bucket[b].wayland;
            var appId = String(safeGet(top, "appId", ""));
            var entry = findEntryFor(entryList, appId);
            var key = appKeyFor(entry, appId);
            if (!byKey[key]) {
                byKey[key] = { appId: appId, entry: entry, windows: [], addresses: [], workspaceIds: [] };
                order.push(key);
            }
            byKey[key].windows.push(top);
            byKey[key].addresses.push(bucket[b].address);
            byKey[key].workspaceIds.push(bucket[b].workspaceId);
        }

        var items = [];
        for (var o = 0; o < order.length; o++) {
            if (maxItemsPerGroup && items.length >= maxItemsPerGroup) break;
            var g = byKey[order[o]];
            items.push(buildAppItem(g.appId, g.entry, g.windows, g.addresses, g.workspaceIds,
                                    activeToplevel, appLibrary, badgeCounts, urgentCounts));
        }

        // A spanning plate is active or focused when any of its halves is, and
        // reports the monitor of whichever half currently has focus.
        var isActive = false, isFocused = false, isUrgent = false, hasFullscreen = false;
        var monitorName = "";
        var realIds = [];
        var primaryWorkspace = null;
        for (var v = 0; v < memberWorkspaces.length; v++) {
            var member = memberWorkspaces[v];
            realIds.push(Number(safeGet(member, "id", -1)));
            if (!primaryWorkspace) primaryWorkspace = member;
            if (safeGet(member, "active", false) === true) isActive = true;
            if (safeGet(member, "urgent", false) === true) isUrgent = true;
            if (safeGet(member, "hasFullscreen", false) === true) hasFullscreen = true;
            if (safeGet(member, "focused", false) === true) {
                isFocused = true;
                var focusedMon = safeGet(member, "monitor", null);
                monitorName = focusedMon ? String(safeGet(focusedMon, "name", "")) : "";
            }
        }
        if (!monitorName && primaryWorkspace) {
            var mon2 = safeGet(primaryWorkspace, "monitor", null);
            monitorName = mon2 ? String(safeGet(mon2, "name", "")) : "";
        }
        realIds.sort(function (a, b) { return a - b; });
        var expectedIds = expectedRealIdsFor(id, rendered.stride, opts.screenCount);

        // Plates are walked in ascending id order, so the empties that survive
        // the cap are the lowest-numbered ones - the next free workspace,
        // rather than an arbitrary one.
        //
        // The workspace being looked at right now is never dropped, however
        // empty it is: hiding it would leave the rail with nothing marked
        // while the user is standing on it, which reads as the dock having
        // lost track of where they are.
        if (items.length === 0 && !isActive && !isFocused) {
            if (maxEmptyPlates === 0) continue;
            if (maxEmptyPlates > 0 && emptyShown >= maxEmptyPlates) continue;
            emptyShown++;
        }

        groups.push({
            key: "ws-" + id,
            workspaceId: id,
            name: String(id),
            workspace: primaryWorkspace,
            workspaces: memberWorkspaces,
            realIds: realIds,
            // Every id this plate covers, including halves Hyprland has not
            // created yet. Activation walks these, not just the live ones.
            expectedRealIds: expectedIds,
            isActive: isActive,
            isFocused: isFocused,
            isUrgent: isUrgent,
            hasFullscreen: hasFullscreen,
            monitorName: monitorName,
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
