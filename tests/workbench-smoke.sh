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
  SettingsSlider.qml PrismTextArea.qml PrismPageHeader.qml \
  PrismFormField.qml PrismSection.qml PrismOpticalIconButton.qml \
  IndicatorVisual.qml; do
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
        property int step: 0
        property int attempts: 0
        property string savedPrompt: ""

        interval: 100
        running: true
        repeat: true

        function fail(message) {
            running = false
            console.error("VOXTYPE_PRISM_WORKBENCH_SMOKE_FAILED:", message)
            Qt.quit()
        }

        onTriggered: {
            attempts += 1
            if (attempts > 70) {
                fail("timed out at step " + step)
                return
            }

            if (step === 0) {
                if (!workbench.windowVisible || workbench.refineProvider === "")
                    return
                savedPrompt = workbench.refinePrompt
                workbench.refineProvider = "anthropic"
                workbench.refinePrompt = savedPrompt + "\nKeep product names exact."
                workbench.refineDictionary = "Voxtype Prism\nHyprland"
                workbench.indicatorPreset = "signal"
                workbench.indicatorPreset = "halo"
                workbench.indicatorPreset = "bar-pulse"
                workbench.indicatorPosition = "top-center"
                workbench.rawSample = "um ship the vox type indicator"
                if (!workbench.dirty) {
                    fail("draft changes were not detected")
                    return
                }
                workbench.open('{"tab":"Indicator"}')
                if (workbench.selectedTab !== 3
                        || workbench.refinePrompt.indexOf("Keep product names exact.") < 0) {
                    fail("dirty re-summon did not preserve the draft and select Indicator")
                    return
                }
                workbench.saveChanges()
                step = 1
                return
            }

            if (step === 1) {
                if (workbench.dirty) return
                if (workbench.refineProvider !== "anthropic"
                        || workbench.indicatorPreset !== "bar-pulse"
                        || workbench.indicatorPosition !== "top-center") {
                    fail("saved draft did not round-trip")
                    return
                }
                workbench.refinePrompt += "\nUnsaved close check."
                workbench.close()
                if (!workbench.windowVisible || !workbench.discardDialogVisible) {
                    fail("dirty close was not intercepted")
                    return
                }
                workbench.closeDiscardDialog()
                workbench.syncDraft()
                if (workbench.dirty) {
                    fail("revert did not restore the saved snapshot")
                    return
                }
                workbench.rawSample = "😀".repeat(1025)
                if (workbench.sampleBytes !== 4100 || workbench.testWithinLimits) {
                    fail("UTF-8 test limit was not enforced")
                    return
                }
                workbench.selectTab(1)
                if (workbench.selectedTab !== 1) {
                    fail("tab navigation failed")
                    return
                }
                workbench.close()
                if (workbench.windowVisible) {
                    fail("clean close did not hide the window")
                    return
                }
                console.log("VOXTYPE_PRISM_WORKBENCH_SMOKE_OK")
                Qt.quit()
            }
        }
    }
}
QML

output=$(timeout 9s env \
  HOME="$smoke_root/home" \
  XDG_CONFIG_HOME="$smoke_root/config" \
  XDG_STATE_HOME="$smoke_root/state" \
  VOXTYPE_PRISM_DISABLE_LAUNCHER=1 \
  VOXTYPE_PRISM_NO_RESTART=1 \
  QT_QPA_PLATFORM=offscreen \
  quickshell --no-color -p "$smoke_root/shell.qml" 2>&1)

printf '%s\n' "$output"
grep -Fq "VOXTYPE_PRISM_WORKBENCH_SMOKE_OK" <<<"$output"
