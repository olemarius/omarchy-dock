import QtQuick
import qs.Commons

// Unread indicator: a dot in the icon's top-right corner, nothing more.
//
// It used to carry the exact count and animate on every change. Neither
// survived contact with the rail: tiles are rebuilt whenever the model
// changes, so a fresh badge read the count it was born with as an arrival and
// pulsed - which set every badged icon bouncing merely from moving the pointer
// between screens, while a genuinely new notification landing alongside a
// rebuild passed silently. A dot states the one thing that is reliably true,
// and states it without moving.
Item {
    id: root

    property int count: 0
    property bool hasUrgent: false
    property bool isSuppressed: false
    property real dotSize: 8

    readonly property bool isBadgeActive: count > 0 && !isSuppressed

    implicitWidth: dotSize
    implicitHeight: dotSize
    z: 250
    visible: isBadgeActive

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Color.urgent
        antialiasing: true
        smooth: true

        // A hairline of the dock's own ground keeps the dot legible where it
        // lands on a light app icon.
        border.width: 1
        border.color: Util.alpha(Color.background, 0.55)
    }
}
