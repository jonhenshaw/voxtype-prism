import QtQuick
import qs.Commons
import qs.Ui as Ui

Item {
    id: root

    property string text: ""
    property bool selected: false
    property string shortcutText: ""
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal clicked()

    implicitHeight: Math.max(Style.spacing.controlHeight + Style.spacing.xl,
        labelButton.implicitHeight)
    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.description: shortcutText ? "Shortcut " + shortcutText : ""
    Accessible.selected: selected
    Accessible.onPressAction: root.clicked()

    Ui.Button {
        id: labelButton
        anchors.fill: parent
        text: root.text
        selected: root.selected
        focusable: true
        leftAlign: true
        foreground: root.foreground
        accent: root.accent
        horizontalPadding: Style.spacing.rowPaddingX + Style.spacing.md
        onClicked: root.clicked()
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.spacing.xs, Style.space(3))
        height: parent.height - Style.spacing.lg
        radius: Style.cornerRadius > 0 ? width / 2 : 0
        color: root.accent
        visible: root.selected
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        text: root.shortcutText
        visible: text !== "" && !root.selected
        color: Qt.darker(root.foreground, 1.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }
}
