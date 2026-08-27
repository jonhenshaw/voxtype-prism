import QtQuick
import Quickshell

// Fail closed when Voxtype's own OSD is enabled. That prevents two indicators
// during initial installation and ensures this plugin never needs to edit
// another application's configuration from inside omarchy-shell.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string configPath: configHome + "/voxtype/config.toml"

    readonly property bool available:
        configStatus.value === "stock-enabled" || configStatus.value === "stock-disabled"
    readonly property bool stockOsdEnabled: configStatus.value !== "stock-disabled"
    readonly property bool configured: available && !stockOsdEnabled

    property BoundedValueReader configStatus: BoundedValueReader {
        id: configStatus
        mode: "config"
        path: root.configPath
        intervalMs: 1500
        fallbackValue: "unavailable"
    }
}
