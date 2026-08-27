pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Layer-shell host only. State and audio live in IndicatorController, while all
// rendering lives in the reusable IndicatorVisual.
Item {
    id: root

    property string daemonState: "idle"
    property var audio: null
    property var themePalette: null
    property var targetScreen: null
    property string styleId: "signal"
    property string position: "bottom-center"
    property real scaleFactor: 1.0
    property real glowIntensity: 0.6
    property bool motionEnabled: true

    readonly property string phase: controller.phase
    readonly property bool surfaceWanted: controller.surfaceWanted
    readonly property real presence: controller.presence
    readonly property var sampleLevels: controller.sampleLevels

    IndicatorController {
        id: controller
        daemonState: root.daemonState
        audio: root.audio
        motionEnabled: root.motionEnabled
    }

    PanelWindow {
        id: surface
        screen: root.targetScreen
        visible: root.targetScreen !== null
            && (controller.surfaceWanted || controller.presence > 0.001)
        implicitWidth: Math.ceil(indicator.implicitWidth)
        implicitHeight: Math.ceil(indicator.implicitHeight)
        anchors {
            top: root.position === "top-center"
            bottom: root.position !== "top-center"
        }
        margins {
            top: root.position === "top-center" ? 20 : 0
            bottom: root.position === "top-center" ? 0 : 20
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.namespace: "voxtype-prism"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        IndicatorVisual {
            id: indicator
            anchors.centerIn: parent
            styleId: root.styleId
            phase: controller.phase
            levels: controller.sampleLevels
            themePalette: root.themePalette
            scaleFactor: root.scaleFactor
            glowIntensity: root.glowIntensity
            motionEnabled: root.motionEnabled
            opacity: controller.presence
            scale: 0.96 + controller.presence * 0.04

            Behavior on scale {
                enabled: root.motionEnabled
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }
    }
}
