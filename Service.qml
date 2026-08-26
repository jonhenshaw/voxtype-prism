import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Omarchy service entry point. This runs inside the existing omarchy-shell
// process; it never starts a second Quickshell instance.
Item {
    id: root

    // Injected by Omarchy's service loader.
    property var shell: null
    property var manifest: null
    property string omarchyPath: ""
    property var pluginRegistry: null
    property var barWidgetRegistry: null

    readonly property string focusedScreenName:
        Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    readonly property var activeScreen: {
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (String(screens[i].name || "") === root.focusedScreenName) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    VoxtypeConfig { id: voxtypeConfig }
    OmarchyPalette { id: palette }
    StateReader { id: stateReader }
    AudioBridge {
        id: audioBridge
        enabled: voxtypeConfig.configured
    }

    IpcHandler {
        target: "voxtype-prism"

        function status(): string {
            return JSON.stringify({
                configured: voxtypeConfig.configured,
                configAvailable: voxtypeConfig.available,
                stockOsdEnabled: voxtypeConfig.stockOsdEnabled,
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
        daemonState: voxtypeConfig.configured ? stateReader.daemonState : "idle"
        audio: audioBridge
        themePalette: palette
        targetScreen: root.activeScreen
    }

    Component.onCompleted: {
        if (!voxtypeConfig.configured) {
            console.warn("voxtype-prism: setup required; run scripts/voxtype-prism-config setup");
        }
    }
}
