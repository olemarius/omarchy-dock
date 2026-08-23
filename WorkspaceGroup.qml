import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One workspace plate on the grouped dock rail: a clickable background that
// switches to the workspace, a workspace label, and the running applications
// of that workspace rendered with the same DockItem tiles the flat rail uses.
//
// The plate deliberately sits *behind* the tiles: clicking an icon focuses
// that window, clicking anywhere else on the plate — padding, label, the gap
// between icons — switches to the workspace.
Item {
    id: root

    property var groupData: null
    property string barPosition: "bottom"
    property var shell: null
    property real slotSize: 42
    property real iconBaseSize: 24
    property int iconRevision: 0
    property bool iconsReady: true
    property int systemBorderSize: Style.normalBorderWidth > 0 ? Style.normalBorderWidth : 2
    property int systemRounding: Style.cornerRadius > 0 ? Style.cornerRadius : 12
    property bool showBadges: true
    property bool showLabel: true

    signal workspaceActivated(var groupData)
    signal itemLaunched(string appId)

    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property var items: (groupData && groupData.items) ? groupData.items : []
    readonly property int itemCount: items.length
    readonly property bool isEmpty: itemCount === 0
    readonly property bool isActive: groupData ? groupData.isActive === true : false
    readonly property bool isFocused: groupData ? groupData.isFocused === true : false
    readonly property bool isUrgent: groupData ? groupData.isUrgent === true : false
    readonly property string label: groupData ? String(groupData.name || "") : ""

    // Plate padding: a little more on the label side so the number never
    // crowds the plate edge, tighter on the tile side where the icons already
    // carry their own optical margin.
    readonly property real padLead: 6
    readonly property real padTrail: root.isEmpty ? 6 : 4
    readonly property real labelGap: 4
    readonly property real labelExtent: root.showLabel ? Math.max(12, Math.ceil(labelMetrics.advanceWidth)) : 0
    readonly property real labelSlot: root.showLabel ? labelExtent + labelGap : 0

    // Rail extent of the plate along the dock axis.
    readonly property real plateExtent: root.padLead + root.labelSlot + (root.itemCount * root.slotSize) + root.padTrail

    implicitWidth: root.isVertical ? root.slotSize : root.plateExtent
    implicitHeight: root.isVertical ? root.plateExtent : root.slotSize
    width: implicitWidth
    height: implicitHeight

    TextMetrics {
        id: labelMetrics
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        text: root.label
    }

    // Clickable workspace background.
    Rectangle {
        id: plate
        anchors.fill: parent
        radius: Math.max(4, root.systemRounding - 2)
        antialiasing: true

        // Active workspaces (visible on some monitor) lift out of the rail;
        // the focused one additionally takes the accent border, so "where am
        // I" stays readable at a glance on a multi-monitor setup.
        color: {
            if (root.isUrgent) return Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.22)
            if (root.isFocused) return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
            if (root.isActive) return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.11)
            if (plateMouse.containsMouse) return Util.alpha(Color.foreground, 0.10)
            return Util.alpha(Color.foreground, root.isEmpty ? 0.03 : 0.06)
        }
        border.width: root.isFocused ? root.systemBorderSize : 0
        border.color: root.isUrgent ? Color.urgent : Color.accent

        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        MouseArea {
            id: plateMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.workspaceActivated(root.groupData)
        }

        Text {
            id: labelText
            visible: root.showLabel
            text: root.label
            font: labelMetrics.font
            color: root.isFocused || root.isActive ? Color.accent : Color.bar.text
            opacity: root.isFocused ? 1.0 : (root.isActive ? 0.85 : (root.isEmpty ? 0.45 : 0.7))
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            x: root.isVertical ? (root.width - width) / 2 : root.padLead
            y: root.isVertical ? root.padLead : (root.height - height) / 2

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    // Application tiles for this workspace. Each tile keeps DockItem's own
    // behaviour: left click focuses, wheel cycles between that app's windows,
    // middle click spawns another instance.
    Repeater {
        model: root.items

        DockItem {
            required property var modelData
            required property int index

            itemData: modelData
            itemIndex: index
            totalCount: root.itemCount
            barPosition: root.barPosition
            shell: root.shell
            slotSize: root.slotSize
            iconBaseSize: root.iconBaseSize
            iconRevision: root.iconRevision
            iconsReady: root.iconsReady
            systemBorderSize: root.systemBorderSize
            systemRounding: root.systemRounding
            showBadges: root.showBadges

            // Grouped tiles are a live view of what the compositor reports,
            // not a user-arranged rail — reordering or pinning them would have
            // nothing to persist, so dragging and edit mode stay off here.
            draggable: false
            isEditMode: false

            x: root.isVertical ? 0 : (root.padLead + root.labelSlot + index * root.slotSize)
            y: root.isVertical ? (root.padLead + root.labelSlot + index * root.slotSize) : 0
            z: 2

            onOriginalAppLaunched: function(appId) { root.itemLaunched(appId) }
        }
    }
}
