import QtQuick
import QtQuick.Layouts
import qs.Commons

// Shared heading rhythm for every destination in the Prism workbench.
ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    property color foreground: Color.foreground

    spacing: Style.spacing.sm

    Text {
        Layout.fillWidth: true
        text: root.title
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    Text {
        Layout.fillWidth: true
        text: root.description
        color: Qt.darker(root.foreground, 1.25)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }
}
