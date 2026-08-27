import QtQuick
import Quickshell

// QML receives only the bounded reader's normalized, allowlisted projection.
// The raw plugin settings document never enters omarchy-shell.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string settingsPath: configHome + "/voxtype-prism/indicator.json"
    readonly property string defaultsJson: "{\"glowIntensity\":0.6,\"motionEnabled\":true,\"position\":\"bottom-center\",\"scaleFactor\":1.0,\"styleId\":\"signal\"}"

    property string styleId: "signal"
    property string position: "bottom-center"
    property real scaleFactor: 1.0
    property bool motionEnabled: true
    property real glowIntensity: 0.6

    function reset() {
        root.styleId = "signal";
        root.position = "bottom-center";
        root.scaleFactor = 1.0;
        root.motionEnabled = true;
        root.glowIntensity = 0.6;
    }

    function load(raw) {
        let values;
        try {
            values = JSON.parse(String(raw || ""));
        } catch (error) {
            root.reset();
            return;
        }
        if (!values || typeof values !== "object" || Array.isArray(values)) {
            root.reset();
            return;
        }

        const knownStyle = values.styleId === "signal"
            || values.styleId === "halo"
            || values.styleId === "bar-pulse";
        const knownPosition = values.position === "bottom-center"
            || values.position === "top-center";
        root.styleId = knownStyle ? values.styleId : "signal";
        root.position = knownPosition ? values.position : "bottom-center";
        root.scaleFactor = typeof values.scaleFactor === "number"
            ? Math.max(0.75, Math.min(1.5, values.scaleFactor)) : 1.0;
        root.motionEnabled = typeof values.motionEnabled === "boolean"
            ? values.motionEnabled : true;
        root.glowIntensity = typeof values.glowIntensity === "number"
            ? Math.max(0, Math.min(1, values.glowIntensity)) : 0.6;
    }

    Component.onCompleted: root.load(settingsStatus.value)

    property BoundedValueReader settingsStatus: BoundedValueReader {
        id: settingsStatus
        mode: "prism-settings"
        path: root.settingsPath
        intervalMs: 300
        fallbackValue: root.defaultsJson
        onValueChanged: root.load(value)
    }
}
