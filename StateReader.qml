import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string statePath: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        if (xdg && xdg.length > 0) return xdg + "/voxtype/state";
        const uid = Quickshell.env("UID");
        if (uid && uid.length > 0) return "/run/user/" + uid + "/voxtype/state";
        return "/run/user/1000/voxtype/state";
    }

    property string daemonState: "idle"

    property FileView stateFile: FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false

        onLoaded: {
            const next = (text() || "idle").trim();
            root.daemonState = next.length > 0 ? next : "idle";
        }
        onLoadFailed: root.daemonState = "idle"
        onFileChanged: reload()
    }
}
