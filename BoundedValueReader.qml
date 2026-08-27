import QtQuick
import Quickshell.Io

// File content never enters omarchy-shell. A bundled helper validates the
// source as a regular, non-symlink file, enforces a byte ceiling, and emits
// only one small normalized status token per change.
QtObject {
    id: root

    property string mode: ""
    property string path: ""
    property int intervalMs: 1000
    property string fallbackValue: ""
    property string value: fallbackValue

    readonly property string readerPath: localPath(Qt.resolvedUrl("scripts/voxtype-prism-read"))

    function localPath(url) {
        let result = String(url || "");
        if (result.indexOf("file://") === 0) result = result.slice(7);
        try {
            return decodeURIComponent(result);
        } catch (error) {
            return result;
        }
    }

    function restart() {
        root.value = root.fallbackValue;
        restartTimer.stop();
        if (reader.running) {
            reader.running = false;
            restartTimer.restart();
        } else if (root.readerPath && root.mode && root.path) {
            reader.running = true;
        }
    }

    onModeChanged: restart()
    onPathChanged: restart()
    onIntervalMsChanged: restart()
    Component.onCompleted: restart()

    property Process reader: Process {
        id: reader
        running: false
        command: [root.readerPath, root.mode, root.path, String(root.intervalMs)]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const next = String(line || "").trim();
                if (next.length > 0) root.value = next;
            }
        }

        onRunningChanged: {
            if (!reader.running) {
                root.value = root.fallbackValue;
                restartTimer.restart();
            }
        }
    }

    property Timer restartTimer: Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!reader.running && root.readerPath && root.mode && root.path)
                reader.running = true;
        }
    }
}
