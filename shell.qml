import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

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
    StateReader { id: stateReader }
    AudioBridge { id: audioBridge }

    IpcHandler {
        target: "voxtype-signal"

        function status(): string {
            return JSON.stringify({
                daemonState: stateReader.daemonState,
                phase: signal.phase,
                surfaceWanted: signal.surfaceWanted,
                presence: signal.presence,
                audioRunning: audioBridge.running,
                sampleLevels: signal.sampleLevels
            });
        }
    }

    SignalSurface {
        id: signal
        daemonState: stateReader.daemonState
        audio: audioBridge
        palette: palette
        targetScreen: root.activeScreen
    }
}
