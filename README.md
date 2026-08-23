# Omarchy Dock

![Omarchy Dock](./preview.png)

A modern, highly polished, and fully native application dock plugin for **Omarchy Quattro** (Hyprland + Quickshell), featuring app stacks (folders), iOS-style edit wiggle animations, multi-window management, dynamic orientation, and seamless theme integration.

---

## ✨ Features

- 🗂️ **Workspace Grouping** *(opt-in)* — Lay the dock out per Hyprland workspace instead of as one flat rail. Each workspace gets its own plate holding the windows running on it, with multiple windows of the same application collapsed into a single icon and window-count capsule (two browser windows on workspace 1 = one browser icon). **Clicking a plate's background switches to that workspace**; clicking an icon focuses that specific window. The focused workspace takes the accent border, active workspaces on other monitors stay highlighted, and empty workspaces remain clickable so the rail keeps a stable width. **Dragging a tile onto another workspace's plate moves those windows there**, without switching you to that workspace. The `···` bar widget carries a **Mode** control for whether a plate covers one screen or spans them all. Toggle it from the `···` bar widget or with `"groupByWorkspace": true`.
- 🧩 **Integrated Dock Widgets** — Move native system widgets (Weather, Volume & Audio, Bluetooth, Network, Power/Battery, Display, Clock/Calendar, Tailscale VPN) directly into the dock. Choose widget placement (Left or Right) via the dedicated widget configuration popup. When clicked, all widget panels appear centered on screen with clean system spacing.
- 📁 **App Stacks (Folders)** — Organize apps into folders with multi-column grids. Create folders by simply dragging one icon onto another. Customize folder icons with built-in Nerd Font glyphs, edit titles inline, and enjoy marquee text scrolling for long names. Folders seamlessly remain open when launching or switching applications.
- ✨ **iOS-Style Edit Mode (Wiggle)** — Long-press (450ms) any icon to enter edit mode with smooth physical wobbling ($\pm 3.8^\circ$, 105ms). Quickly toggle favorite pins (`•`), dissolve folders (`-`), remove dock widgets (`-`), or reorder apps.
- 🔀 **Fluid 1D & 2D Drag & Drop** — Smooth rail displacement physics when dragging apps across the dock or within folder grids. Effortlessly extract apps from folders back to the main dock.
- 🔄 **Multi-Instance Sliding Viewport (Infinite Wheel Scrolling)** — Hover over any running app with duplicate windows and scroll the mouse wheel to cycle through instances. The status capsule uses a smooth 3-slot sliding viewport: the original app is always a distinct wide dash (`━`), while duplicates are round dots (`•`). As you scroll deeper into duplicates, the original dash smoothly scrolls out of view and reappears when looping back.
- 🎯 **Real-Time Hyprland IPC Focus Sync** — Moving the mouse cursor over any window tile on the desktop (`follow_mouse = 1`) or switching focus instantly syncs and highlights the corresponding slot on the dock in real time without lag.
- ⚡ **Dedicated Controls (LMB & Middle-Click)** — Left-click opens closed apps or focuses/activates running windows. Middle-click (pressing the mouse wheel) instantly spawns a new duplicate instance anytime.
- 👁️ **Smart Cursor Hiding** — The mouse cursor is automatically hidden (`Qt.BlankCursor`) during mouse wheel scrolling and folder title hover to ensure an unobstructed view of the status capsule and animations.
- 🌐 **Full Web Apps (PWA) Support** — Automatic domain matching for Chrome/Chromium web apps (Google Maps, Google Contacts, WhatsApp, YouTube, Discord, etc.) with native GTK theme icons.
- ⚡ **Zero-Flicker Boot & Tile Lift** — Two-phase initialization instantly reserves Hyprland exclusive space to lift tiled windows smoothly, followed by a monolithic fade-in once all vector theme icons are loaded.
- 🖥️ **One Dock Per Monitor** — Every connected screen gets its own dock surface, bound to that output rather than to whichever monitor Quickshell happened to pick. Each dock keeps its own hover, drag, edit mode and open folder, so using one never disturbs the other. Switch the dock off for a screen from the `···` widget's per-monitor row, or with `"disabledMonitors": ["eDP-1"]`; new monitors get a dock by default.
- 🧭 **Dynamic Auto-Positioning** — Automatically adapts its position opposite to the Omarchy status bar (top $\leftrightarrow$ bottom, left $\leftrightarrow$ right).
- ⏱️ **Smart Auto-Hide** — Optional auto-hide with a 1.5-second dismissal delay and instant hover reveal.
- 🎛️ **Status Bar Settings Widget (`BarWidget`)** — Native top bar menu with smooth toggle switches for Dock Enable, Auto-hide, Folder Titles, and Dock Widgets configuration.
- 🎨 **100% Native Theme Sync** — Clean borderless status capsules that automatically react to Omarchy colors (`Color.accent`, `Color.bar.background`), system fonts, and window corner radius tokens.
- 🔤 **Subpixel Vector Glyphs (`DockGlyph`)** — GPU-accelerated vector curve rendering without font hinting distortion or pixel jitter during animations.

---

## 🎮 Controls & Shortcuts

| Action | Control | Description |
| :--- | :--- | :--- |
| **Open / Focus Window** | `Left-Click` / `Enter` | Opens the application if closed, or activates and focuses the chosen window tile/duplicate. |
| **Launch Duplicate** | `Middle-Click` / `Tab` | Instantly spawns a new duplicate instance of the application with immediate focus. |
| **Cycle Duplicates** | `Mouse Wheel` / `←` `→` Arrow Keys | Cycles through duplicate windows via 3-slot sliding viewport (original dash `━` and duplicate dots `•`). |
| **Open Widget Panel** | `Left-Click` *(on Widget)* | Opens the hosted system widget panel (Audio, Wi-Fi, BT, Power, Monitor, etc.) centered on screen. |
| **Switch Workspace** | `Left-Click` *(on plate background)* | In workspace grouping mode, clicking a workspace plate anywhere outside an icon switches to that workspace. |
| **Move Window to Workspace** | `Drag` *(tile onto another plate)* | In workspace grouping mode, drag an application tile onto another workspace's plate. Every window that tile represents moves there; you stay on your current workspace. Empty workspaces appear as drop targets for the duration of the drag — the gaps between occupied ones and one past the last — so a window can be sent somewhere new. Dropping on the tile's own plate, or outside the rail, does nothing. |
| **Enter Edit Mode** | `Long-Press` *(450ms)* | Activates iOS-style physical wobble mode to reorder apps, toggle pins, remove widgets, or dissolve folders. |
| **Reorder & Folders** | `Drag & Drop` | Drag along the rail to reorder. Drag one icon onto another to create a folder (App Stack). |
| **Folder Icon Picker** | `Right-Click` *(on Folder)* | Opens the Nerd Font glyph picker to customize the folder's icon. |
| **Exit Edit Mode / Close Menus** | `Right-Click` / `Escape` | Instantly exits edit mode and dismisses open menus. |
| **Toggle Pin State** | `Click • Badge` *(in Edit Mode)* | Pins or unpins the application to/from favorites. |
| **Dissolve Folder / Remove Widget**| `Click - Badge` *(in Edit Mode)* | Dissolves folder back to dock, or returns widget back to system status bar tray. |

---

## 📦 Installation

Install and enable the dock with a single command:

```bash
omarchy plugin add https://github.com/rosakodu/omarchy-dock.git --enable
```

---

## ⚙️ Configuration

The dock works out of the box with zero configuration required.

You can customize options directly via the `···` status bar widget or in `~/.config/omarchy/dock-settings.json`:

```json
{
  "dockEnabled": true,
  "autohide": false,
  "showFolderTitles": true,
  "widgetsEnabled": true,
  "widgetPosition": "left",
  "dockWidgets": [
    "omarchy.apps"
  ],
  "disabledMonitors": [],
  "excludeUndockedMonitors": true,
  "groupByWorkspace": false,
  "showEmptyWorkspaces": true,
  "paddedWorkspaceCount": 5,
  "workspaceScope": "all",
  "excludeMonitors": [],
  "maxEmptyWorkspaces": 1,
  "groupAppInstances": true,
  "workspaceStride": 0
}
```

`disabledMonitors` lists monitors — by the names Hyprland reports, e.g. `eDP-1` — that should not show a dock. `dockEnabled` remains the master switch across every screen; this subtracts individual ones from it. Unknown names are inert, so unplugging a display never leaves a dock switched off with no way to reach the setting.

`excludeUndockedMonitors` (default `true`) keeps the rails in agreement with that: a screen with no dock contributes no windows to the docks that remain. Turning the dock off for a monitor and still seeing its windows listed on another screen's dock reads as a bug — and unlike naming the monitor in `excludeMonitors`, this corrects itself the moment that dock is switched back on. Set it to `false` if you want one dock to stay a view of everything running, including screens you gave no dock to.

```bash
omarchy-shell rosakodu.dock setMonitorEnabled eDP-1:false   # off for one screen
omarchy-shell rosakodu.dock toggleMonitor                   # flip the focused screen
omarchy-shell rosakodu.dock setExcludeUndockedMonitors false
```

### Workspace grouping

| Key | Default | Meaning |
| :--- | :--- | :--- |
| `groupByWorkspace` | `false` | Group running windows onto one clickable plate per workspace instead of the flat pinned rail. |
| `showEmptyWorkspaces` | `true` | Keep plates for workspaces with no windows, so the rail does not reflow as workspaces empty out. Set `false` for a rail of only what is running. |
| `maxEmptyWorkspaces` | `1` | How many empty plates to keep at rest — while a tile is being dragged the rail reveals its empty workspaces regardless, both the gaps between occupied ones and one past the last, so a window can be dropped onto a workspace nothing lives on yet. A trailing run of untouched workspaces says nothing beyond "there is somewhere free to go", so one is shown and the rest dropped; `-1` shows them all. The workspace you are currently viewing always keeps its plate, however empty. |
| `paddedWorkspaceCount` | `5` | How many numbered workspaces are always shown when `showEmptyWorkspaces` is on. |
| `workspaceScope` | `"all"` | `"all"` shows every workspace; `"monitor"` restricts the rail to workspaces on the dock's own monitor. |
| `groupAppInstances` | `true` | One tile per application. Turn it off to give every window its own icon, so two windows of the same editor are two separate targets rather than one icon carrying a count. |
| `workspaceStride` | `0` | Spanning workspaces. Hyprland cannot put one workspace on two monitors, so multi-monitor setups often pair them by offset — workspace 2 on the main screen and 12 on the second being two halves of one idea. Set this to that offset (usually `10`) and each plate represents the pair: it shows the windows of both halves, clicking it switches every screen at once, and dragging a tile onto it keeps each window on the screen it is already on. `0` gives one plate per workspace. |
| `excludeMonitors` | `[]` | Monitor names whose workspaces are left off the rail entirely, e.g. `["eDP-1"]` to ignore the laptop screen while docked. Excluded workspaces are not padded back as empty plates. Workspaces the compositor has never opened have no monitor yet, so they still appear — set `showEmptyWorkspaces` to `false` for a rail of only what exists. |

Pinning, folders, reordering and edit mode apply to the flat rail. The grouped rail is a live view of what the compositor reports, so its tiles are not reorderable: left click focuses, the mouse wheel cycles that application's windows on that workspace, middle click spawns another instance, and dragging moves windows between workspaces rather than rearranging the rail.

The same options are reachable over IPC:

```bash
omarchy-shell rosakodu.dock setGroupByWorkspace true
omarchy-shell rosakodu.dock setShowEmptyWorkspaces false
omarchy-shell rosakodu.dock setWorkspaceScope monitor
omarchy-shell rosakodu.dock listMonitors                  # names to exclude
omarchy-shell rosakodu.dock setExcludeMonitors eDP-1      # comma-separated; "" clears
omarchy-shell rosakodu.dock setMaxEmptyWorkspaces 0      # -1 for all
omarchy-shell rosakodu.dock setWorkspaceStride 10        # 0 disables spanning
```

Pinned items and folder layouts are automatically saved to `~/.config/omarchy/dock-pinned.json`.

---

## 🗑️ Uninstallation

```bash
omarchy plugin remove rosakodu.dock
```

---

## 📄 License

[MIT](./LICENSE) © 2026 rosakodu

