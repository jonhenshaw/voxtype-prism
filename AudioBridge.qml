import QtQuick
import Quickshell.Io

Item {
    id: root

    property string bridgeBinary: "/usr/bin/voxtype-audio-bridge"
    property int restartDelayMs: 1000
    property bool running: false
    property real peak: 0
    property real rms: 0
    property bool vad: false
    property var tsMs: 0

    signal frameReceived(real peak, real rms, bool vad, var tsMs)
    signal connected()
    signal disconnected()

    onEnabledChanged: {
        restartTimer.stop();
        process.running = root.enabled;
        if (!root.enabled && root.running) {
            root.running = false;
            root.disconnected();
        }
    }

    Component.onCompleted: process.running = root.enabled

    function handleLine(line) {
        const trimmed = String(line || "").trim();
        if (trimmed.length === 0) return;

        let payload;
        try {
            payload = JSON.parse(trimmed);
        } catch (error) {
            console.warn("voxtype-prism: ignored non-JSON audio bridge output");
            return;
        }

        if (payload.status === "connected") {
            root.connected();
            return;
        }
        if (payload.status === "disconnected") {
            root.running = false;
            root.disconnected();
            return;
        }
        if (typeof payload.peak !== "number" || typeof payload.rms !== "number") return;

        root.peak = payload.peak;
        root.rms = payload.rms;
        root.vad = !!payload.vad;
        root.tsMs = payload.ts_ms !== undefined ? payload.ts_ms : 0;
        root.running = true;
        root.frameReceived(root.peak, root.rms, root.vad, root.tsMs);
    }

    Process {
        id: process
        command: [root.bridgeBinary]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleLine(data)
        }

        onRunningChanged: {
            if (process.running) return;
            if (root.running) {
                root.running = false;
                root.disconnected();
            }
            if (root.enabled) restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: root.restartDelayMs
        repeat: false
        onTriggered: if (root.enabled && !process.running) process.running = true
    }
}
