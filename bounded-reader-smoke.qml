import QtQuick
import Quickshell
import "." as Prism

ShellRoot {
    id: root

    property bool sawInitialValue: false
    property bool forcedRestart: false

    Prism.StateReader { id: stateReader }
    Prism.OmarchyPalette { id: palette }

    Prism.BoundedValueReader {
        id: reader
        mode: "config"
        path: Quickshell.env("VOXTYPE_PRISM_SMOKE_CONFIG")
        intervalMs: 50
        fallbackValue: "idle"

        onValueChanged: {
            if (!root.forcedRestart && value === "stock-disabled") {
                root.sawInitialValue = true;
                root.forcedRestart = true;
                reader.reader.running = false;
            } else if (root.forcedRestart && value === "stock-disabled") {
                if (!stateReader.stateStatus.reader.running || !palette.paletteStatus.reader.running)
                    return;
                console.log("VOXTYPE_PRISM_BOUNDED_READER_SMOKE_OK");
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: false
        onTriggered: {
            console.error("VOXTYPE_PRISM_BOUNDED_READER_SMOKE_TIMEOUT",
                          root.sawInitialValue, reader.value, reader.reader.running,
                          stateReader.stateStatus.reader.running,
                          palette.paletteStatus.reader.running);
            Qt.quit();
        }
    }
}
