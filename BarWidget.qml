import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "rosakodu.dock"

  property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/dock-settings.json"
  property bool dockEnabled: true
  property var disabledMonitors: []
  // The dock owns dock-settings.json. This widget must never write a value it
  // has not read back first, or its defaults land on top of the real file -
  // which is how workspaceStride silently reverted to 0.
  property bool settingsLoaded: false

  // The screen this copy of the widget is drawn on. The bar is built per
  // monitor, so "this monitor" is unambiguous: it is the one you clicked on.
  readonly property string thisMonitor: root.anchorWindow && root.anchorWindow.screen
    ? String(root.anchorWindow.screen.name || "") : ""
  readonly property bool thisMonitorEnabled: root.thisMonitor === ""
    || root.disabledMonitors.indexOf(root.thisMonitor) === -1
  property bool autohide: false
  property bool showFolderTitles: true
  property bool showBadges: true
  property bool groupByWorkspace: false
  // 0 = one plate per workspace, >0 = plates span paired workspaces across
  // monitors (the offset between a screen's workspaces, conventionally 10).
  property int workspaceStride: 0
  property string workspaceScope: "all"
  property bool groupAppInstances: true
  readonly property int spanningStride: 10
  property bool widgetsEnabled: true
  property bool settingsOpen: false

  // The window this widget is drawn in, and therefore the monitor its popup
  // belongs on. Without this the popup is placed on whichever screen
  // Quickshell picks by default, which on a multi-head setup is regularly not
  // the one holding the button. Same resolution the shell's own PopupCard uses.
  readonly property var anchorWindow: root.QsWindow ? root.QsWindow.window : null

  // Centre of this button in its bar window, sampled rather than bound:
  // mapToItem() is not reactive, and neighbours in the same bar section change
  // width as they update (the clock relaying out every minute is enough to
  // shift this button), which would leave a bound value stale. Sampling when
  // the popup opens is what the alignment actually depends on.
  property real anchorCenterX: 0
  property real anchorCenterY: 0

  function refreshAnchorCenter() {
    var point = root.mapToItem(null, root.width / 2, root.height / 2)
    if (!point) return
    root.anchorCenterX = point.x
    root.anchorCenterY = point.y
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.readSettings()
    onFileChanged: { reload(); root.readSettings() }
  }

  property var dockWidgets: ["omarchy.apps"]
  property string appMenuPosition: "left"
  property string widgetPosition: "right"
  property var widgetSavedPositions: ({})

  function readSettings() {
    try {
      var txt = settingsFile.text()
      if (txt && txt.trim().length > 0) {
        var s = JSON.parse(txt)
        if (s && s.dockEnabled !== undefined) {
          root.dockEnabled = (s.dockEnabled === true)
        }
        if (s && s.disabledMonitors !== undefined && Array.isArray(s.disabledMonitors)) {
          root.disabledMonitors = s.disabledMonitors
        }
        if (s && s.autohide !== undefined) {
          root.autohide = (s.autohide === true)
        }
        if (s && s.showFolderTitles !== undefined) {
          root.showFolderTitles = (s.showFolderTitles === true)
        }
        if (s && s.showBadges !== undefined) {
          root.showBadges = (s.showBadges === true)
        }
        if (s && s.groupByWorkspace !== undefined) {
          root.groupByWorkspace = (s.groupByWorkspace === true)
        }
        if (s && s.groupAppInstances !== undefined) {
          root.groupAppInstances = (s.groupAppInstances === true)
        }
        if (s && s.workspaceScope !== undefined) {
          root.workspaceScope = (s.workspaceScope === "monitor") ? "monitor" : "all"
        }
        if (s && s.workspaceStride !== undefined) {
          var stride = parseInt(s.workspaceStride, 10)
          if (!isNaN(stride) && stride >= 0) root.workspaceStride = stride
        }
        if (s && s.widgetsEnabled !== undefined) {
          root.widgetsEnabled = (s.widgetsEnabled === true)
        }
        if (s && s.appMenuPosition !== undefined) {
          root.appMenuPosition = s.appMenuPosition
        }
        if (s && s.widgetPosition !== undefined) {
          root.widgetPosition = s.widgetPosition
        }
        if (s && s.dockWidgets !== undefined && Array.isArray(s.dockWidgets)) {
          root.dockWidgets = s.dockWidgets
        }
        if (s && s.widgetSavedPositions !== undefined && typeof s.widgetSavedPositions === "object") {
          root.widgetSavedPositions = s.widgetSavedPositions
        }
      }
    } catch(e) {}
    root.settingsLoaded = true
  }

  function saveSettings() {
    if (!root.settingsLoaded) return
    var s = {}
    try {
      var txt = settingsFile.text()
      if (txt && txt.trim().length > 0) {
        s = JSON.parse(txt) || {}
      }
    } catch(e) {}

    s.dockEnabled = root.dockEnabled
    s.autohide = root.autohide
    s.showFolderTitles = root.showFolderTitles
    s.showBadges = root.showBadges
    s.groupByWorkspace = root.groupByWorkspace
    s.widgetsEnabled = root.widgetsEnabled
    s.appMenuPosition = root.appMenuPosition || s.appMenuPosition || "left"
    s.widgetPosition = root.widgetPosition || s.widgetPosition || "right"
    s.widgetSavedPositions = root.widgetSavedPositions || s.widgetSavedPositions || {}
    if (!root.widgetsEnabled) {
      s.dockWidgets = []
    } else if (Array.isArray(s.dockWidgets) && s.dockWidgets.length > 0) {
      s.dockWidgets = s.dockWidgets.slice(0, 2)
    } else if (Array.isArray(root.dockWidgets) && root.dockWidgets.length > 0) {
      s.dockWidgets = root.dockWidgets.slice(0, 2)
    } else {
      s.dockWidgets = ["omarchy.apps"]
    }

    settingsFile.setText(JSON.stringify(s, null, 2) + "\n")
  }

  function setDockEnabled(val) {
    root.dockEnabled = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setDockEnabled " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setThisMonitorEnabled(val) {
    if (!root.thisMonitor) return
    var next = []
    for (var i = 0; i < root.disabledMonitors.length; i++) {
      if (String(root.disabledMonitors[i]) !== root.thisMonitor) next.push(root.disabledMonitors[i])
    }
    if (!val) next.push(root.thisMonitor)
    root.disabledMonitors = next
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setMonitorEnabled "
        + root.thisMonitor + ":" + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setAutohide(val) {
    root.autohide = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setAutohide " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setGroupByWorkspace(val) {
    root.groupByWorkspace = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setGroupByWorkspace " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setGroupAppInstances(val) {
    root.groupAppInstances = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setGroupAppInstances " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  // Mode picks which workspaces a dock lists. That is the scope, not the block
  // offset: the offset describes how the compositor numbers each screen's
  // workspaces and applies either way. Setting it alongside keeps the plates
  // numbered 1..n on both screens rather than 11..15 on the second.
  function setWorkspaceScope(scope) {
    root.workspaceScope = scope
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setWorkspaceScope " + scope)
      if (root.workspaceStride <= 0) {
        root.workspaceStride = root.spanningStride
        root.bar.run("omarchy-shell rosakodu.dock setWorkspaceStride " + root.spanningStride)
      }
    } else {
      saveSettings()
    }
  }

  function setWorkspaceStride(val) {
    root.workspaceStride = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setWorkspaceStride " + val)
    } else {
      saveSettings()
    }
  }

  function setShowFolderTitles(val) {
    root.showFolderTitles = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setShowFolderTitles " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setShowBadges(val) {
    root.showBadges = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setShowBadges " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  function setWidgetsEnabled(val) {
    root.widgetsEnabled = val
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell rosakodu.dock setWidgetsEnabled " + (val ? "true" : "false"))
    } else {
      saveSettings()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "···"
    tooltipText: "Dock Settings"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.settingsOpen = !root.settingsOpen
      }
    }
  }

  onSettingsOpenChanged: {
    if (settingsOpen) {
      root.refreshAnchorCenter()
      settingsCard.forceActiveFocus()
    }
  }

  // Outside-click dismissal for Settings popup
  HyprlandFocusGrab {
    id: settingsGrab
    active: root.settingsOpen
    windows: [settingsWindow]
    onCleared: {
      root.settingsOpen = false
    }
  }

  // Settings Popup Overlay Window, aligned under the widget rather than
  // centred on the screen: the button can sit in any bar section, and a card
  // that ignores it reads as belonging to something else.
  PanelWindow {
    id: settingsWindow
    visible: root.settingsOpen

    WlrLayershell.namespace: "omarchy-dock-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    screen: root.anchorWindow ? root.anchorWindow.screen : null

    readonly property bool isBarBottom: root.bar && root.bar.position === "bottom"
    readonly property bool isBarLeft: root.bar && root.bar.position === "left"
    readonly property bool isBarRight: root.bar && root.bar.position === "right"

    // Measure against the widget's own screen. Reading a width off the bar
    // handed back the other monitor on a multi-head setup, which centred the
    // card using the wrong width and pushed it off the narrow screen.
    readonly property var popupScreen: root.anchorWindow ? root.anchorWindow.screen : null
    readonly property real screenWidth: popupScreen ? popupScreen.width : (Screen.width || 1920)
    readonly property real screenHeight: popupScreen ? popupScreen.height : (Screen.height || 1080)

    readonly property real cardWidth: 280
    readonly property real edgeGap: (Style.gapsOut || 5) + 4

    // The bar spans the monitor, so the button's position in its bar window
    // doubles as its position on screen.
    readonly property real widgetCenterX: root.anchorCenterX > 0 ? root.anchorCenterX : screenWidth / 2
    readonly property real widgetCenterY: root.anchorCenterY > 0 ? root.anchorCenterY : screenHeight / 2

    // Centred under the button, then clamped so a button near either end
    // still gets a fully visible card.
    readonly property real calculatedLeft: Math.round(Math.max(edgeGap,
      Math.min(screenWidth - cardWidth - edgeGap, widgetCenterX - cardWidth / 2)))
    readonly property real calculatedTop: Math.round(Math.max(edgeGap,
      Math.min(screenHeight - (settingsCard.height || 120) - edgeGap, widgetCenterY - (settingsCard.height || 120) / 2)))

    anchors {
      top: (isBarRight || isBarLeft) ? true : !isBarBottom
      bottom: isBarBottom
      left: isBarRight ? false : true
      right: isBarRight
    }

    margins {
      top: (isBarLeft || isBarRight) ? calculatedTop : (isBarBottom ? 0 : ((Style.gapsOut || 5) + 38))
      bottom: isBarBottom ? ((Style.gapsOut || 5) + 38) : 0
      left: isBarRight ? 0 : (isBarLeft ? ((Style.gapsOut || 5) + 38) : calculatedLeft)
      right: isBarRight ? ((Style.gapsOut || 5) + 38) : 0
    }

    implicitWidth: 280
    implicitHeight: settingsCard.height

    Rectangle {
      id: settingsCard
      focus: true
      Keys.onEscapePressed: function(event) {
        root.settingsOpen = false
        event.accepted = true
      }
      Keys.onBackPressed: function(event) {
        root.settingsOpen = false
        event.accepted = true
      }
      width: 280
      height: cardColumn.height + 24
      color: Color.composed("popups.background", "popups.background-alpha", Color.background, 0.96)
      border.width: Style.borderWidth || 2
      border.color: Color.accent
      radius: Style.cornerRadius >= 0 ? Style.cornerRadius : 12
      antialiasing: true
      smooth: true

      ColumnLayout {
        id: cardColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 10

        // Header Row
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          DockGlyph {
            width: 16
            height: 16
            text: "⚙"
            fontFamily: Style.font.family
            fontSize: 14
            color: Color.accent
          }

          Text {
            text: "Dock Settings"
            font.family: Style.font.family
            font.pixelSize: 13
            font.bold: true
            color: Color.popups.text
            Layout.fillWidth: true
          }
        }

        // Divider
        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Color.composed("popups.border", "popups.border-alpha", Color.border, 0.35)
        }

        // Toggle Enable Dock Row (at the very top)
        Rectangle {
          id: enableDockRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          color: toggleEnableMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Enable dock"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Show or hide dock bar"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            // Custom Smooth Toggle Switch
            Rectangle {
              id: switchEnableTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.dockEnabled ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchEnableThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.dockEnabled ? (switchEnableTrack.width - width - 3) : 3
                color: root.dockEnabled ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: toggleEnableMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setDockEnabled(!root.dockEnabled)
            }
          }
        }

        // Toggle Autohide Row
        Rectangle {
          id: autohideRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: toggleMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Autohide dock"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Hide dock when not hovered"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            // Custom Smooth Toggle Switch
            Rectangle {
              id: switchTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.autohide ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.autohide ? (switchTrack.width - width - 3) : 3
                color: root.autohide ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: toggleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setAutohide(!root.autohide)
            }
          }
        }

        // Per-monitor Row. "Enable dock" above is the master switch; this
        // subtracts the screen you are looking at from it, so a second display
        // can stay clear without turning the dock off everywhere.
        Rectangle {
          id: thisMonitorRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          visible: root.thisMonitor !== ""
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: monitorMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Dock on " + root.thisMonitor
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Show the dock on this monitor"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: switchMonitorTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.thisMonitorEnabled ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchMonitorThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.thisMonitorEnabled ? (switchMonitorTrack.width - width - 3) : 3
                color: root.thisMonitorEnabled ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: monitorMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setThisMonitorEnabled(!root.thisMonitorEnabled)
            }
          }
        }

        // Toggle Workspace Grouping Row
        Rectangle {
          id: groupByWorkspaceRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: groupMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Group by workspace"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "One plate per workspace"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: switchGroupTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.groupByWorkspace ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchGroupThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.groupByWorkspace ? (switchGroupTrack.width - width - 3) : 3
                color: root.groupByWorkspace ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: groupMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setGroupByWorkspace(!root.groupByWorkspace)
            }
          }
        }

        // Instance Grouping Row
        Rectangle {
          id: instanceRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: (root.dockEnabled && root.groupByWorkspace) ? 1.0 : 0.4
          enabled: root.dockEnabled && root.groupByWorkspace
          color: instanceMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Group windows"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "One icon per app, not per window"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: switchInstanceTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.groupAppInstances ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchInstanceThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.groupAppInstances ? (switchInstanceTrack.width - width - 3) : 3
                color: root.groupAppInstances ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: instanceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setGroupAppInstances(!root.groupAppInstances)
            }
          }
        }

        // Workspace Mode Row. Only meaningful while grouping is on, so it
        // dims with the rest of the disabled controls rather than vanishing
        // and making the card jump height as the toggle flips.
        Rectangle {
          id: workspaceModeRow
          Layout.fillWidth: true
          height: 74
          radius: 8
          opacity: (root.dockEnabled && root.groupByWorkspace) ? 1.0 : 0.4
          enabled: root.dockEnabled && root.groupByWorkspace
          color: "transparent"
          Behavior on opacity { NumberAnimation { duration: 150 } }

          ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 6

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                text: "Mode"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Which workspaces this dock lists"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Repeater {
                model: [
                  { label: "This screen", scope: "monitor" },
                  { label: "All screens", scope: "all" }
                ]

                Rectangle {
                  required property var modelData

                  readonly property bool selected: root.workspaceScope === modelData.scope

                  Layout.fillWidth: true
                  Layout.preferredHeight: 26
                  radius: 6
                  color: selected
                    ? Color.accent
                    : (modeMouse.containsMouse
                        ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.14)
                        : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.07))
                  Behavior on color { ColorAnimation { duration: 140 } }

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: Style.font.family
                    font.pixelSize: 10
                    font.bold: parent.selected
                    color: parent.selected ? Color.background : Color.popups.text
                  }

                  MouseArea {
                    id: modeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setWorkspaceScope(modelData.scope)
                  }
                }
              }
            }
          }
        }

        // Toggle Folder Names Row
        Rectangle {
          id: folderTitlesRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: toggleTitlesMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Folder names"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Show titles in folder popups"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            // Custom Smooth Toggle Switch
            Rectangle {
              id: switchTitlesTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.showFolderTitles ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchTitlesThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.showFolderTitles ? (switchTitlesTrack.width - width - 3) : 3
                color: root.showFolderTitles ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: toggleTitlesMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setShowFolderTitles(!root.showFolderTitles)
            }
          }
        }

        // Toggle Notification Badges Row
        Rectangle {
          id: badgesRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: toggleBadgesMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Notification badges"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Show unread badges on app icons"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            // Custom Smooth Toggle Switch
            Rectangle {
              id: switchBadgesTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.showBadges ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchBadgesThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.showBadges ? (switchBadgesTrack.width - width - 3) : 3
                color: root.showBadges ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: toggleBadgesMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setShowBadges(!root.showBadges)
            }
          }
        }

        // Toggle Widgets in Dock Row
        Rectangle {
          id: widgetsRow
          Layout.fillWidth: true
          height: 48
          radius: 8
          opacity: root.dockEnabled ? 1.0 : 0.4
          enabled: root.dockEnabled
          color: toggleWidgetsMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150 } }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: "Dock widgets"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
                color: Color.popups.text
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Display bar widgets on dock"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            // Custom Smooth Toggle Switch
            Rectangle {
              id: switchWidgetsTrack
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              Layout.preferredWidth: 36
              Layout.preferredHeight: 20
              width: 36
              height: 20
              radius: 10
              color: root.widgetsEnabled ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.25)
              Behavior on color { ColorAnimation { duration: 180 } }

              Rectangle {
                id: switchWidgetsThumb
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: root.widgetsEnabled ? (switchWidgetsTrack.width - width - 3) : 3
                color: root.widgetsEnabled ? Color.background : Color.popups.text
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: toggleWidgetsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.setWidgetsEnabled(!root.widgetsEnabled)
            }
          }
        }

        // Configure Widgets Action Button
        Rectangle {
          id: configureWidgetsRow
          Layout.fillWidth: true
          Layout.preferredHeight: 40
          radius: 8
          opacity: (root.dockEnabled && root.widgetsEnabled) ? 1.0 : 0.4
          enabled: root.dockEnabled && root.widgetsEnabled
          color: configureWidgetsMouse.containsMouse ? Color.composed("accent", "accent-alpha", Color.accent, 0.2) : Color.composed("popups.text", "popups.text-alpha", Color.text, 0.08)
          border.width: 1
          border.color: configureWidgetsMouse.containsMouse ? Color.accent : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

          Text {
            anchors.centerIn: parent
            text: "Configure dock widgets"
            font.family: Style.font.family
            font.pixelSize: 11
            font.bold: true
            color: configureWidgetsMouse.containsMouse ? Color.accent : Color.popups.text
            renderType: Text.CurveRendering
            font.hintingPreference: Font.PreferNoHinting
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          MouseArea {
            id: configureWidgetsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.settingsOpen = false
              var sh = root.shell || (root.bar ? root.bar.shell : null)
              var dockSvc = (sh && typeof sh.serviceFor === "function") ? sh.serviceFor("rosakodu.dock") : null
              if (dockSvc && typeof dockSvc.openWidgetPicker === "function") {
                dockSvc.openWidgetPicker()
              } else if (root.bar && typeof root.bar.run === "function") {
                root.bar.run("omarchy-shell rosakodu.dock openWidgetPicker")
              } else {
                Util.execDetached("omarchy-shell rosakodu.dock openWidgetPicker")
              }
            }
          }
        }
      }
    }
  }
}
