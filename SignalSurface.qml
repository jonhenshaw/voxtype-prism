import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

Item {
    id: root

    property string daemonState: "idle"
    property var audio: null
    property var palette: null
    property var targetScreen: null
    property bool motionEnabled: true

    property string phase: "idle"
    property bool surfaceWanted: false
    property bool hasSeenActivity: false
    property real presence: 0
    property var sampleLevels: [0, 0, 0, 0, 0, 0, 0]
    property int thinkingFrame: 0

    readonly property bool levelVisible: phase === "recording" || phase === "streaming"
    readonly property color stateColor: {
        if (!palette) return "#7aa2f7";
        if (phase === "recording") return palette.recording;
        if (phase === "transcribing") return palette.transcribing;
        if (phase === "ready") return palette.ready;
        return palette.accent;
    }
    readonly property string icon: {
        if (phase === "recording" || phase === "streaming") return "\uf130";
        if (phase === "transcribing") return "\uf110";
        return "\uf00c";
    }
    readonly property string label: {
        if (phase === "recording") return "LISTENING";
        if (phase === "streaming") return "STREAMING";
        if (phase === "transcribing") return "WORKING";
        return "READY";
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function clearLevels() {
        root.sampleLevels = [0, 0, 0, 0, 0, 0, 0];
    }

    function normalizedState(value) {
        const state = String(value || "idle").trim();
        if (state === "recording" || state === "streaming" || state === "transcribing") return state;
        return "idle";
    }

    function syncState() {
        const next = root.normalizedState(root.daemonState);
        if (next !== "idle") {
            completionTimer.stop();
            if (next === "recording" && root.phase !== "recording") root.clearLevels();
            root.phase = next;
            root.hasSeenActivity = true;
            root.surfaceWanted = true;
            root.presence = 1;
            return;
        }

        if (root.hasSeenActivity && root.surfaceWanted && root.phase !== "ready") {
            root.phase = "ready";
            root.clearLevels();
            root.surfaceWanted = true;
            root.presence = 1;
            completionTimer.restart();
            return;
        }

        if (!root.hasSeenActivity) {
            root.surfaceWanted = false;
            root.presence = 0;
        }
    }

    onDaemonStateChanged: syncState()
    Component.onCompleted: syncState()

    Behavior on presence {
        enabled: root.motionEnabled
        NumberAnimation { duration: root.surfaceWanted ? 150 : 220; easing.type: Easing.OutCubic }
    }

    Connections {
        target: root.audio
        enabled: root.audio !== null
        ignoreUnknownSignals: true

        function onFrameReceived(peak, rms, vad, tsMs) {
            if (!root.levelVisible) return;
            const value = Math.min(1, Math.sqrt(Math.max(0, peak)) * 2.15);
            const next = root.sampleLevels.slice(1);
            next.push(value);
            root.sampleLevels = next;
        }

        function onDisconnected() {
            root.clearLevels();
        }
    }

    Timer {
        id: completionTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.surfaceWanted = false;
            root.presence = 0;
        }
    }

    Timer {
        interval: 170
        repeat: true
        running: root.phase === "transcribing" && root.surfaceWanted && root.motionEnabled
        onTriggered: root.thinkingFrame = (root.thinkingFrame + 1) % 3
    }

    PanelWindow {
        id: surface
        screen: root.targetScreen
        visible: root.targetScreen !== null && (root.surfaceWanted || root.presence > 0.001)
        implicitWidth: 168
        implicitHeight: 48
        anchors { bottom: true }
        margins { bottom: 20 }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.namespace: "voxtype-signal"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: haloSource
            visible: false
            width: 156
            height: 40
            anchors.centerIn: parent
            radius: 14
            color: root.stateColor
        }

        MultiEffect {
            anchors.fill: haloSource
            source: haloSource
            autoPaddingEnabled: true
            blurEnabled: true
            blur: 0.7
            blurMax: 6
            blurMultiplier: 0.55
            opacity: 0.08 * root.presence
            scale: 1.01
        }

        Rectangle {
            id: card
            width: 156
            height: 40
            anchors.centerIn: parent
            radius: 14
            color: root.withAlpha(root.palette ? root.palette.panel : "#13141c", 0.96)
            border.width: 1
            border.color: root.withAlpha(root.stateColor, 0.62)
            opacity: root.presence
            scale: 0.96 + root.presence * 0.04

            Behavior on border.color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                spacing: 8

                Item {
                    width: 18
                    height: parent.height

                    Text {
                        id: stateIcon
                        anchors.centerIn: parent
                        text: root.icon
                        color: root.stateColor
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        renderType: Text.NativeRendering
                    }

                    RotationAnimator {
                        target: stateIcon
                        from: 0
                        to: 360
                        duration: 920
                        loops: Animation.Infinite
                        running: root.phase === "transcribing" && root.surfaceWanted && root.motionEnabled
                        onRunningChanged: if (!running) stateIcon.rotation = 0
                    }
                }

                Item {
                    width: 46
                    height: parent.height

                    Row {
                        id: levelBars
                        visible: root.levelVisible
                        anchors.centerIn: parent
                        spacing: 3

                        Repeater {
                            model: 7
                            Rectangle {
                                required property int index
                                width: 2
                                height: 3 + Math.round(15 * (root.sampleLevels[index] || 0))
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
                                opacity: index === root.thinkingFrame ? 1 : 0.32

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
                    color: root.palette ? root.palette.foreground : "#c0caf5"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 0.8
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
