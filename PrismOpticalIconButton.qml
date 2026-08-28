import QtQuick
import qs.Commons
import qs.Ui as Ui

// Native panel action button with the glyph's painted bounds centered inside
// the hit target. Nerd Font advance boxes are not always optically symmetric,
// so centering the raw Text line box can leave close/check icons visibly off.
Ui.PanelActionButton {
    id: root

    property string opticalIconText: ""

    iconText: ""
    size: Style.spacing.controlHeight

    readonly property rect tightBounds: glyphMetrics.tightBoundingRect

    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Accessible.focusable: focusable

    TextMetrics {
        id: glyphMetrics
        text: root.opticalIconText
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Math.round(root.fontSize))
    }

    Text {
        id: glyph
        x: Math.round((root.width - root.tightBounds.width) / 2 - root.tightBounds.x)
        y: Math.round((root.height - root.tightBounds.height) / 2
            - (glyph.baselineOffset + root.tightBounds.y))
        text: root.opticalIconText
        color: root.enabled
            ? (root._hot ? root.hoverColor : root.foreground)
            : Qt.darker(root.foreground, 2.0)
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Math.round(root.fontSize))
        renderType: Text.NativeRendering
    }
}
