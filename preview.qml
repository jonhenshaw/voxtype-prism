import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

    property string previewState: Quickshell.env("VOXTYPE_SIGNAL_PREVIEW_STATE") || "recording"
    property int audioFrame: 0
    readonly property var audioLevels: [0.03, 0.14, 0.42, 0.21, 0.67, 0.34, 0.09, 0.52, 0.26]
    readonly property string focusedScreenName:
        Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    readonly property var activeScreen: {
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (String(screens[i].name || "") === root.focusedScreenName) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    OmarchyPalette { id: palette }

    IpcHandler {
        target: "voxtype-signal-preview"

        function state(next: string): string {
            const normalized = String(next || "").trim();
            if (normalized !== "recording" && normalized !== "streaming"
                    && normalized !== "transcribing" && normalized !== "idle") {
                return "expected recording, streaming, transcribing, or idle";
            }
            root.previewState = normalized;
            return root.previewState;
        }
    }

    QtObject {
        id: mockAudio
        property bool running: true
        signal frameReceived(real peak, real rms, bool vad, var tsMs)
        signal disconnected()
    }

    Timer {
        interval: 85
        repeat: true
        running: root.previewState === "recording" || root.previewState === "streaming"
        onTriggered: {
            root.audioFrame = (root.audioFrame + 1) % root.audioLevels.length;
            const level = root.audioLevels[root.audioFrame];
            mockAudio.frameReceived(level, level * 0.56, level > 0.12, Date.now());
        }
    }

    SignalSurface {
        daemonState: root.previewState
        audio: mockAudio
        palette: palette
        targetScreen: root.activeScreen
    }
}
