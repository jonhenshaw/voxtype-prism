#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
smoke_root=$(mktemp -d /tmp/voxtype-prism-workbench-smoke.XXXXXX)
cleanup() { rm -rf -- "$smoke_root"; }
trap cleanup EXIT

mkdir -p "$smoke_root/home" "$smoke_root/config" "$smoke_root/state"
ln -s /usr/share/omarchy/shell/Ui "$smoke_root/Ui"
ln -s /usr/share/omarchy/shell/Commons "$smoke_root/Commons"
ln -s "$repo_root/scripts" "$smoke_root/scripts"

for file in \
  SettingsPanel.qml SettingsBackend.qml SettingsNavItem.qml \
  SettingsSlider.qml PrismTextArea.qml IndicatorVisual.qml; do
  ln -s "$repo_root/$file" "$smoke_root/$file"
done

cat >"$smoke_root/shell.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: shellRoot

    property QtObject shellMock: QtObject {
        function hide(pluginId) {}
    }

    SettingsPanel {
        id: workbench
        shell: shellRoot.shellMock
        manifest: ({ id: "io.github.jonhenshaw.voxtype-prism" })
    }

    Component.onCompleted: Qt.callLater(function() { workbench.open("{}") })

    Timer {
        interval: 2200
        running: true
        repeat: false
        onTriggered: {
            if (!workbench.windowVisible) {
                console.error("VOXTYPE_PRISM_WORKBENCH_SMOKE_NOT_VISIBLE")
                Qt.quit()
                return
            }
            console.log("VOXTYPE_PRISM_WORKBENCH_SMOKE_OK")
            Qt.quit()
        }
    }
}
QML

output=$(timeout 6s env \
  HOME="$smoke_root/home" \
  XDG_CONFIG_HOME="$smoke_root/config" \
  XDG_STATE_HOME="$smoke_root/state" \
  VOXTYPE_PRISM_DISABLE_LAUNCHER=1 \
  VOXTYPE_PRISM_NO_RESTART=1 \
  QT_QPA_PLATFORM=offscreen \
  quickshell --no-color -p "$smoke_root/shell.qml" 2>&1)

printf '%s\n' "$output"
grep -Fq "VOXTYPE_PRISM_WORKBENCH_SMOKE_OK" <<<"$output"
