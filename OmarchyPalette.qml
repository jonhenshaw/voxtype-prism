import QtQuick
import Quickshell

// Minimal Omarchy palette reader. The bundled reader polls across atomic theme
// swaps and emits only a small allowlisted JSON color map into omarchy-shell.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    readonly property string themeDir: stateHome + "/omarchy/current/theme"
    readonly property string colorsPath: themeDir + "/colors.toml"

    property color background: "#1a1b26"
    property color panel: "#13141c"
    property color foreground: "#c0caf5"
    property color mutedText: "#565f89"
    property color accent: "#7aa2f7"
    property color recording: "#f7768e"
    property color transcribing: "#e0af68"
    property color ready: "#9ece6a"

    function load(raw) {
        let values = {};
        try {
            const parsed = JSON.parse(String(raw || "{}"));
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) values = parsed;
        } catch (error) {
            return;
        }

        root.background = values.background || values.color0 || root.background;
        root.panel = values.dark_background || values.darker_background || root.background;
        root.foreground = values.foreground || values.bright_foreground || values.color7 || root.foreground;
        root.mutedText = values.dark_foreground || values.muted || values.color8 || root.mutedText;
        root.accent = values.accent || values.blue || values.color4 || root.accent;
        root.recording = values.red || values.color1 || root.recording;
        root.transcribing = values.yellow || values.color3 || root.transcribing;
        root.ready = values.green || values.color2 || root.ready;
    }

    property BoundedValueReader paletteStatus: BoundedValueReader {
        id: paletteStatus
        mode: "palette"
        path: root.colorsPath
        intervalMs: 300
        fallbackValue: "{}"
        onValueChanged: root.load(value)
    }
}
