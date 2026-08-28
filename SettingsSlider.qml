import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui as Ui

Column {
    id: root

    property string label: ""
    property string valueText: Number(value).toFixed(0)
    property string accessibleName: label
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property color foreground: Color.foreground
    property color accent: Color.accent

    signal modified(real value)

    spacing: Style.spacing.md

    Row {
        width: parent.width

        Text {
            width: parent.width - valueLabel.width
            text: root.label
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            id: valueLabel
            text: root.valueText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
    }

    QQC.Slider {
        id: slider
        width: parent.width
        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value
        snapMode: QQC.Slider.SnapAlways
        live: true
        activeFocusOnTab: true
        Accessible.name: root.accessibleName
        Accessible.description: "Value " + root.valueText
        onMoved: root.modified(value)

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: Math.max(Style.spacing.xs, Style.space(3))
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Style.normalFillFor(root.foreground, root.accent)

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
            }
        }

        handle: Ui.BorderSurface {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: Style.space(18)
            implicitHeight: implicitWidth
            radius: Style.cornerRadius > 0 ? width / 2 : 0
            color: slider.pressed || slider.hovered || slider.activeFocus
                ? Style.hoverStateColor(root.foreground, root.accent)
                : root.accent
            borderSpec: Border.controlSpec(slider.activeFocus ? "focus" : "normal",
                root.foreground, root.accent)
        }
    }
}
