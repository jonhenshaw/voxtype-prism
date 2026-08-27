import QtQuick
import Quickshell

QtObject {
    id: root

    readonly property string statePath: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        if (xdg && xdg.length > 0) return xdg + "/voxtype/state";
        const uid = Quickshell.env("UID");
        if (uid && uid.length > 0) return "/run/user/" + uid + "/voxtype/state";
        return "/run/user/1000/voxtype/state";
    }

    readonly property string daemonState: stateStatus.value

    property BoundedValueReader stateStatus: BoundedValueReader {
        id: stateStatus
        mode: "state"
        path: root.statePath
        intervalMs: 80
        fallbackValue: "idle"
    }
}
