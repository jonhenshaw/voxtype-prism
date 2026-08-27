pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// A pure visual: callers provide normalized style, state, levels, and palette.
// It has no daemon, file, process, screen, or layer-shell dependencies.
Item {
    id: root

    property string styleId: "signal"
    property string phase: "ready"
    property var levels: [0, 0, 0, 0, 0, 0, 0]
    property var themePalette: null
    property real scaleFactor: 1.0
    property real glowIntensity: 0.6
    property bool motionEnabled: true

    property int thinkingFrame: 0

    readonly property real normalizedScale: Math.max(0.75, Math.min(1.5, scaleFactor))
    readonly property real normalizedGlow: Math.max(0, Math.min(1, glowIntensity))
    readonly property real baseWidth: styleId === "halo" ? 68 : (styleId === "bar-pulse" ? 136 : 168)
    readonly property real baseHeight: styleId === "halo" ? 68 : (styleId === "bar-pulse" ? 34 : 48)
    readonly property bool levelVisible: phase === "recording" || phase === "streaming"
    readonly property color panelColor: themePalette ? themePalette.panel : "#13141c"
    readonly property color foregroundColor: themePalette ? themePalette.foreground : "#c0caf5"
    readonly property color stateColor: {
        if (!themePalette) {
            if (phase === "recording") return "#f7768e";
            if (phase === "transcribing") return "#e0af68";
            if (phase === "ready") return "#9ece6a";
            return "#7aa2f7";
        }
        if (phase === "recording") return themePalette.recording;
        if (phase === "transcribing") return themePalette.transcribing;
        if (phase === "ready") return themePalette.ready;
        return themePalette.accent;
    }
    readonly property string icon: {
        if (phase === "recording" || phase === "streaming") return "\uf130";
        if (phase === "transcribing") return "\uf110";
        return "\uf00c";
    }
    readonly property string haloIcon: phase === "streaming" ? "\uf1eb" : icon
    readonly property string label: {
        if (phase === "recording") return "LISTENING";
        if (phase === "streaming") return "STREAMING";
        if (phase === "transcribing") return "WORKING";
        return "READY";
    }
    readonly property real liveLevel: Math.max(
        root.levelAt(6),
        root.levelAt(5) * 0.82,
        root.levelAt(4) * 0.64
    )

    implicitWidth: baseWidth * normalizedScale
    implicitHeight: baseHeight * normalizedScale

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, Math.max(0, Math.min(1, alpha)));
    }

    function levelAt(index) {
        if (!root.levels || index < 0 || index >= root.levels.length) return 0;
        const value = root.levels[index];
        if (typeof value !== "number") return 0;
        return Math.max(0, Math.min(1, value));
    }

    function meterHeight(index) {
        if (root.levelVisible) return 3 + Math.round(15 * root.levelAt(6 - index));
        if (root.phase === "transcribing") {
            const frame = root.thinkingFrame % 5;
            return index === frame ? 16 : (index === frame - 1 ? 9 : 4);
        }
        return 2;
    }

    Timer {
        interval: 170
        repeat: true
        running: root.phase === "transcribing" && root.visible && root.motionEnabled
        onTriggered: root.thinkingFrame = (root.thinkingFrame + 1) % 15
    }

    Item {
        id: scaledContent
        width: root.baseWidth
        height: root.baseHeight
        anchors.centerIn: parent
        scale: root.normalizedScale

        // Signal preserves the existing 156 x 40 pill at scale 1.
        Item {
            id: signalVisual
            visible: root.styleId === "signal"
            width: 168
            height: 48
            anchors.centerIn: parent

            Rectangle {
                id: signalGlowSource
                visible: false
                width: 156
                height: 40
                anchors.centerIn: parent
                radius: 14
                color: root.stateColor
            }

            MultiEffect {
                anchors.fill: signalGlowSource
                source: signalGlowSource
                autoPaddingEnabled: true
                blurEnabled: true
                blur: 0.7
                blurMax: 6
                blurMultiplier: 0.55
                opacity: 0.08 * root.normalizedGlow / 0.6
                scale: 1.01
            }

            Rectangle {
                id: signalCard
                width: 156
                height: 40
                anchors.centerIn: parent
                radius: 14
                color: root.withAlpha(root.panelColor, 0.96)
                border.width: 1
                border.color: root.withAlpha(root.stateColor, 0.62)

                Behavior on border.color {
                    enabled: root.motionEnabled
                    ColorAnimation { duration: 160 }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    spacing: 8

                    Item {
                        width: 18
                        height: parent.height

                        Text {
                            id: signalIcon
                            anchors.centerIn: parent
                            text: root.icon
                            color: root.stateColor
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            renderType: Text.NativeRendering
                        }

                        RotationAnimator {
                            target: signalIcon
                            from: 0
                            to: 360
                            duration: 920
                            loops: Animation.Infinite
                            running: root.styleId === "signal"
                                && root.phase === "transcribing"
                                && root.motionEnabled
                            onRunningChanged: if (!running) signalIcon.rotation = 0
                        }
                    }

                    Item {
                        width: 46
                        height: parent.height

                        Row {
                            visible: root.levelVisible
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: 7

                                Rectangle {
                                    required property int index
                                    width: 2
                                    height: 3 + Math.round(15 * root.levelAt(index))
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 1
                                    color: root.stateColor

                                    Behavior on height {
                                        enabled: root.motionEnabled
                                        NumberAnimation { duration: 72; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }

                        Row {
                            visible: root.phase === "transcribing"
                            anchors.centerIn: parent
                            spacing: 5

                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: root.stateColor
                                    opacity: index === root.thinkingFrame % 3 ? 1 : 0.32

                                    Behavior on opacity {
                                        enabled: root.motionEnabled
                                        NumberAnimation { duration: 120 }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.phase === "ready"
                            width: 32
                            height: 2
                            anchors.centerIn: parent
                            radius: 1
                            color: root.withAlpha(root.stateColor, 0.62)
                        }
                    }

                    Text {
                        width: 54
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.label
                        color: root.foregroundColor
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 0.8
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        // Halo is deliberately wordless. Its ring and glow react to real audio.
        Item {
            id: haloVisual
            visible: root.styleId === "halo"
            width: 68
            height: 68
            anchors.centerIn: parent

            Rectangle {
                id: haloGlowSource
                visible: false
                width: 48
                height: 48
                anchors.centerIn: parent
                radius: 24
                color: root.stateColor
                scale: root.levelVisible ? 0.9 + root.liveLevel * 0.24 : 1
            }

            MultiEffect {
                anchors.fill: haloGlowSource
                source: haloGlowSource
                autoPaddingEnabled: true
                blurEnabled: true
                blur: 0.9
                blurMax: 16
                blurMultiplier: 0.9
                opacity: root.normalizedGlow * (root.levelVisible ? 0.16 + root.liveLevel * 0.4 : 0.24)
                scale: 1.02
            }

            Rectangle {
                id: responsiveRing
                width: 48
                height: 48
                anchors.centerIn: parent
                radius: 24
                scale: root.levelVisible ? 0.9 + root.liveLevel * 0.2 : 1
                color: root.withAlpha(
                    root.stateColor,
                    root.levelVisible ? 0.08 + root.liveLevel * 0.18 : 0.1
                )
                border.width: root.phase === "ready" ? 2 : 1
                border.color: root.withAlpha(root.stateColor, root.phase === "ready" ? 0.8 : 0.58)
                opacity: root.phase === "transcribing"
                    ? (root.thinkingFrame % 2 === 0 ? 0.62 : 1) : 1

                Behavior on scale {
                    enabled: root.motionEnabled
                    NumberAnimation { duration: 76; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    enabled: root.motionEnabled
                    ColorAnimation { duration: 160 }
                }
                Behavior on opacity {
                    enabled: root.motionEnabled
                    NumberAnimation { duration: 170 }
                }
            }

            Rectangle {
                width: 38
                height: 38
                anchors.centerIn: parent
                radius: 19
                color: root.withAlpha(root.panelColor, 0.96)
                border.width: 1
                border.color: root.withAlpha(root.stateColor, 0.72)

                Text {
                    id: haloStateIcon
                    anchors.centerIn: parent
                    text: root.haloIcon
                    color: root.stateColor
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    renderType: Text.NativeRendering
                }

                RotationAnimator {
                    target: haloStateIcon
                    from: 0
                    to: 360
                    duration: 920
                    loops: Animation.Infinite
                    running: root.styleId === "halo"
                        && root.phase === "transcribing"
                        && root.motionEnabled
                    onRunningChanged: if (!running) haloStateIcon.rotation = 0
                }
            }
        }

        // Bar Pulse mirrors the newest five samples around a compact state icon.
        Item {
            id: barPulseVisual
            visible: root.styleId === "bar-pulse"
            width: 136
            height: 34
            anchors.centerIn: parent

            component BarBank: Row {
                property bool reversed: false
                layoutDirection: reversed ? Qt.RightToLeft : Qt.LeftToRight
                spacing: 3

                Repeater {
                    model: 5

                    Rectangle {
                        required property int index
                        width: 3
                        height: root.meterHeight(index)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1.5
                        color: root.stateColor
                        opacity: root.phase === "ready" ? 0.5 : 0.92

                        Behavior on height {
                            enabled: root.motionEnabled
                            NumberAnimation { duration: 76; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Rectangle {
                id: stripGlowSource
                visible: false
                width: 124
                height: 3
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                radius: 1.5
                color: root.stateColor
            }

            MultiEffect {
                anchors.fill: stripGlowSource
                source: stripGlowSource
                autoPaddingEnabled: true
                blurEnabled: true
                blur: 0.8
                blurMax: 8
                blurMultiplier: 0.7
                opacity: root.normalizedGlow * 0.38
            }

            Rectangle {
                id: stripCard
                width: 124
                height: 28
                anchors.centerIn: parent
                radius: 8
                color: root.withAlpha(root.panelColor, 0.9)
                border.width: 1
                border.color: root.withAlpha(root.stateColor, 0.42)

                Rectangle {
                    height: 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    radius: 1
                    color: root.withAlpha(root.stateColor, 0.82)
                }

                Item {
                    id: stripCenter
                    width: 22
                    height: parent.height
                    anchors.centerIn: parent

                    Text {
                        id: stripStateIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        text: root.haloIcon
                        color: root.stateColor
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }

                    RotationAnimator {
                        target: stripStateIcon
                        from: 0
                        to: 360
                        duration: 920
                        loops: Animation.Infinite
                        running: root.styleId === "bar-pulse"
                            && root.phase === "transcribing"
                            && root.motionEnabled
                        onRunningChanged: if (!running) stripStateIcon.rotation = 0
                    }
                }

                BarBank {
                    anchors.right: stripCenter.left
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    reversed: true
                }

                BarBank {
                    anchors.left: stripCenter.right
                    anchors.leftMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                }
            }
        }
    }
}
