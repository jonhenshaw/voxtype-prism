import QtQuick

// Owns the daemon-to-visual state machine and a short, bounded audio history.
// It has no window or rendering responsibilities.
QtObject {
    id: root

    property string daemonState: "idle"
    property var audio: null
    property bool motionEnabled: true

    property string phase: "idle"
    property bool surfaceWanted: false
    property bool hasSeenActivity: false
    property real presence: 0
    property var sampleLevels: [0, 0, 0, 0, 0, 0, 0]

    readonly property bool levelVisible: phase === "recording" || phase === "streaming"

    function clearLevels() {
        root.sampleLevels = [0, 0, 0, 0, 0, 0, 0];
    }

    function normalizedState(value) {
        const state = String(value || "idle").trim();
        if (state === "recording" || state === "streaming" || state === "transcribing")
            return state;
        return "idle";
    }

    function setPresence(value) {
        presenceAnimation.stop();
        if (!root.motionEnabled) {
            root.presence = value;
            return;
        }
        presenceAnimation.from = root.presence;
        presenceAnimation.to = value;
        presenceAnimation.duration = value > root.presence ? 150 : 220;
        presenceAnimation.restart();
    }

    function syncState() {
        const next = root.normalizedState(root.daemonState);
        if (next !== "idle") {
            completionTimer.stop();
            if (next === "recording" && root.phase !== "recording") root.clearLevels();
            root.phase = next;
            root.hasSeenActivity = true;
            root.surfaceWanted = true;
            root.setPresence(1);
            return;
        }

        if (root.hasSeenActivity && root.surfaceWanted && root.phase !== "ready") {
            root.phase = "ready";
            root.clearLevels();
            root.surfaceWanted = true;
            root.setPresence(1);
            completionTimer.restart();
            return;
        }

        if (!root.hasSeenActivity) {
            root.surfaceWanted = false;
            root.setPresence(0);
        }
    }

    onDaemonStateChanged: root.syncState()
    onMotionEnabledChanged: {
        if (!root.motionEnabled) {
            presenceAnimation.stop();
            root.presence = root.surfaceWanted ? 1 : 0;
            root.clearLevels();
        }
    }
    Component.onCompleted: root.syncState()

    property Connections audioConnection: Connections {
        target: root.audio
        enabled: root.audio !== null
        ignoreUnknownSignals: true

        function onFrameReceived(peak) {
            if (!root.motionEnabled || !root.levelVisible) return;
            const value = Math.min(1, Math.sqrt(Math.max(0, peak)) * 2.15);
            const next = root.sampleLevels.slice(1);
            next.push(value);
            root.sampleLevels = next;
        }

        function onDisconnected() {
            root.clearLevels();
        }
    }

    property Timer completionTimer: Timer {
        id: completionTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.surfaceWanted = false;
            root.setPresence(0);
        }
    }

    property NumberAnimation presenceAnimation: NumberAnimation {
        id: presenceAnimation
        target: root
        property: "presence"
        easing.type: Easing.OutCubic
    }
}
