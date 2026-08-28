import QtQuick
import QtQuick.Layouts
import qs.Commons

// A predictable label/control/helper stack. Controls supplied by callers are
// placed in the inner ColumnLayout so sibling fields share label baselines.
ColumnLayout {
    id: root

    property string label: ""
    property string meta: ""
    property string helper: ""
    property bool hasError: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color errorColor: Color.urgent
    default property alias fieldContent: fieldSlot.data

    spacing: Style.spacing.labelGap

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.controlGap

        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            visible: root.meta !== ""
            text: root.meta
            color: root.hasError ? root.errorColor : Qt.darker(root.foreground, 1.25)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }

    ColumnLayout {
        id: fieldSlot
        Layout.fillWidth: true
        spacing: Style.spacing.labelGap
    }

    Text {
        Layout.fillWidth: true
        visible: root.helper !== ""
        text: root.helper
        color: root.hasError ? root.errorColor : Qt.darker(root.foreground, 1.25)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
    }
}
