import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property bool needed: false
    property var targetScreen: null
    property var themePalette: null
    property bool busy: setupProcess.running
    property bool activationAttempted: false
    property string errorText: ""

    readonly property string helperPath: localPath(Qt.resolvedUrl("scripts/voxtype-prism-config"))

    function localPath(url) {
        let value = String(url || "");
        if (value.indexOf("file://") === 0) value = value.slice(7);
        try {
            return decodeURIComponent(value);
        } catch (error) {
            return value;
        }
    }

    function activate() {
        if (root.busy || !root.helperPath) return;
        root.errorText = "";
        root.activationAttempted = true;
        setupProcess.running = true;
    }

    function finishAttempt() {
        if (!root.activationAttempted || setupProcess.running) return;
        root.activationAttempted = false;
        const error = setupStderr.text.trim();
        const output = setupStdout.text.trim();
        if (error.length > 0 || output.indexOf("Voxtype Prism is configured") === -1)
            root.errorText = error || "Activation failed. Check the Voxtype service.";
    }

    property Process setupProcess: Process {
        id: setupProcess
        running: false
        command: [root.helperPath, "setup"]

        stdout: StdioCollector {
            id: setupStdout
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: setupStderr
            waitForEnd: true
        }

        onRunningChanged: if (!setupProcess.running) Qt.callLater(root.finishAttempt)
    }

    PanelWindow {
        screen: root.targetScreen
        visible: root.needed && root.targetScreen !== null
        implicitWidth: 336
        implicitHeight: root.errorText ? 132 : 112
        anchors { bottom: true }
        margins { bottom: 24 }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "voxtype-prism-activation"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: root.themePalette ? root.themePalette.panel : "#13141c"
            border.width: 1
            border.color: root.themePalette ? root.themePalette.accent : "#7aa2f7"

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 7

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: 20
                        text: "\uf130"
                        color: root.themePalette ? root.themePalette.accent : "#7aa2f7"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17
                        renderType: Text.NativeRendering
                    }

                    Column {
                        width: parent.width - activateButton.width - 40
                        spacing: 2

                        Text {
                            text: "ACTIVATE VOXTYPE PRISM"
                            color: root.themePalette ? root.themePalette.foreground : "#c0caf5"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: "Replace the stock indicator. Fully reversible."
                            color: root.themePalette ? root.themePalette.mutedText : "#565f89"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                    }

                    Rectangle {
                        id: activateButton
                        width: 82
                        height: 30
                        radius: 10
                        color: activateMouse.containsMouse
                            ? (root.themePalette ? root.themePalette.accent : "#7aa2f7")
                            : "transparent"
                        border.width: 1
                        border.color: root.themePalette ? root.themePalette.accent : "#7aa2f7"
                        opacity: root.busy ? 0.55 : 1

                        Text {
                            anchors.centerIn: parent
                            text: root.busy ? "WORKING" : "ACTIVATE"
                            color: activateMouse.containsMouse
                                ? (root.themePalette ? root.themePalette.panel : "#13141c")
                                : (root.themePalette ? root.themePalette.accent : "#7aa2f7")
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: activateMouse
                            anchors.fill: parent
                            enabled: !root.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activate()
                        }
                    }
                }

                Text {
                    visible: root.errorText.length > 0
                    width: parent.width
                    text: root.errorText
                    color: root.themePalette ? root.themePalette.recording : "#f7768e"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }
}
