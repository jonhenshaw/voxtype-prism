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

    readonly property string pluginId: manifest && manifest.id
        ? String(manifest.id) : "io.github.jonhenshaw.voxtype-prism"

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
    IndicatorRuntimeConfig { id: indicatorConfig }
    LauncherManager {
        id: launcher
        enabled: Quickshell.env("VOXTYPE_PRISM_DISABLE_LAUNCHER") !== "1"
    }
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
                phase: indicatorSurface.phase,
                surfaceWanted: indicatorSurface.surfaceWanted,
                presence: indicatorSurface.presence,
                audioRunning: audioBridge.running,
                sampleLevels: indicatorSurface.sampleLevels,
                indicatorStyle: indicatorConfig.styleId,
                indicatorPosition: indicatorConfig.position,
                indicatorScale: indicatorConfig.scaleFactor,
                indicatorMotion: indicatorConfig.motionEnabled,
                indicatorGlow: indicatorConfig.glowIntensity,
                launcherInstalled: launcher.installed,
                launcherError: launcher.errorText,
                activationNeeded: activation.needed,
                activationBusy: activation.busy,
                activationError: activation.errorText
            });
        }

        function settings(): string {
            if (!root.shell || typeof root.shell.summon !== "function")
                return "unavailable";
            return root.shell.summon(root.pluginId, "{}") ? "ok" : "unavailable";
        }
    }

    SignalSurface {
        id: indicatorSurface
        daemonState: voxtypeConfig.configured ? stateReader.daemonState : "idle"
        audio: audioBridge
        themePalette: palette
        targetScreen: root.activeScreen
        styleId: indicatorConfig.styleId
        position: indicatorConfig.position
        scaleFactor: indicatorConfig.scaleFactor
        motionEnabled: indicatorConfig.motionEnabled
        glowIntensity: indicatorConfig.glowIntensity
    }

    PrismActivation {
        id: activation
        needed: voxtypeConfig.available && voxtypeConfig.stockOsdEnabled
        targetScreen: root.activeScreen
        themePalette: palette
    }

}
