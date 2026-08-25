import QtQuick
import Quickshell
import Quickshell.Io

// Minimal Omarchy palette reader for this standalone Quickshell config.
// Theme swaps replace the theme directory, so theme.name is the stable beacon
// that tells us to reload colors.toml from its new target.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    readonly property string themeDir: stateHome + "/omarchy/current/theme"
    readonly property string colorsPath: themeDir + "/colors.toml"
    readonly property string themeNamePath: stateHome + "/omarchy/current/theme.name"

    property color background: "#1a1b26"
    property color panel: "#13141c"
    property color foreground: "#c0caf5"
    property color mutedText: "#565f89"
    property color accent: "#7aa2f7"
    property color recording: "#f7768e"
    property color transcribing: "#e0af68"
    property color ready: "#9ece6a"

    function load(raw) {
        const values = {};
        const lines = String(raw || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (match) values[match[1]] = match[2];
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

    property FileView colorsFile: FileView {
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
    }

    property FileView themeMarker: FileView {
        path: root.themeNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            root.colorsFile.reload();
        }
    }
}
