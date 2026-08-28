import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

// Opaque, theme-native grouping surface. Translucent control fills can safely
// compose inside this card without revealing unrelated windows underneath.
Ui.BorderSurface {
    id: root

    property int contentPadding: Style.spacing.panelPadding
    property color foreground: Color.foreground
    property color accent: Color.accent
    default property alias sectionContent: content.data

    implicitHeight: content.implicitHeight + contentPadding * 2
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g,
        Color.popups.background.b, 1)
    borderSpec: Border.controlSpec("normal", foreground, accent)
    radius: Style.cornerRadius

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: Style.space(14)
    }
}
