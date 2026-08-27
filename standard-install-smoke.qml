import QtQuick
import Quickshell
import "." as Prism

ShellRoot {
    Prism.Service {
        manifest: ({
            id: "io.github.jonhenshaw.voxtype-prism",
            __sourceDir: Quickshell.env("VOXTYPE_PRISM_SOURCE_DIR")
        })
    }
}
