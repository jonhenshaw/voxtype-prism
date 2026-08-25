import QtQuick
import Quickshell
import Quickshell.Io

// Fail closed when Voxtype's own OSD is enabled. That prevents two indicators
// during initial installation and ensures this plugin never needs to edit
// another application's configuration from inside omarchy-shell.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string configPath: configHome + "/voxtype/config.toml"

    property bool available: false
    property bool stockOsdEnabled: true
    readonly property bool configured: available && !stockOsdEnabled

    function parseEnabled(raw) {
        const lines = String(raw || "").split("\n");
        let inOsd = false;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const section = line.match(/^\s*\[([^\]]+)\]\s*(?:#.*)?$/);
            if (section) {
                inOsd = section[1].trim() === "osd";
                continue;
            }
            if (!inOsd || /^\s*#/.test(line)) continue;
            const enabled = line.match(/^\s*enabled\s*=\s*(true|false)\s*(?:#.*)?$/);
            if (enabled) return enabled[1] === "true";
        }
        return true;
    }

    property FileView configFile: FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.available = true;
            root.stockOsdEnabled = root.parseEnabled(text());
        }
        onFileChanged: reload()
        onLoadFailed: {
            root.available = false;
            root.stockOsdEnabled = true;
        }
    }

    // Voxtype and its TUI replace config.toml atomically. Some FileView
    // backends keep watching the old inode, so this low-cost reload bridges
    // that replacement and also notices a config created after shell startup.
    property Timer refreshTimer: Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: root.configFile.reload()
    }
}
