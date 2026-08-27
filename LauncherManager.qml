import QtQuick
import Quickshell.Io

// Installs the user-scoped desktop entry that makes Quick Shell open Prism.
// The helper owns all file validation and mutation; QML receives only status.
Item {
    id: root

    property bool enabled: true
    property bool installing: installer.running
    property bool installed: false
    property string errorText: ""
    readonly property string helperPath: localPath(Qt.resolvedUrl("scripts/voxtype-prism-launcher"))

    function localPath(url) {
        let value = String(url || "");
        if (value.indexOf("file://") === 0) value = value.slice(7);
        try {
            return decodeURIComponent(value);
        } catch (error) {
            return value;
        }
    }

    function install() {
        if (!root.enabled || !root.helperPath || installer.running) return;
        root.errorText = "";
        installer.command = [root.helperPath, "install"];
        installer.running = true;
    }

    Process {
        id: installer
        running: false

        stdout: StdioCollector {
            id: installStdout
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: installStderr
            waitForEnd: true
        }

        onRunningChanged: {
            if (installer.running) return;
            const error = installStderr.text.trim();
            try {
                const result = JSON.parse(installStdout.text.trim() || "{}");
                root.installed = result.ok === true && result.state === "prism";
                if (!root.installed) root.errorText = String(result.error || error || "Launcher installation failed.");
            } catch (parseError) {
                root.installed = false;
                root.errorText = error || "Launcher installation returned invalid status.";
            }
        }
    }

    Component.onCompleted: if (root.enabled) install()
}
