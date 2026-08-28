#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output_path=${1:-"$repo_root/docs/images/refinement-workbench-implementation.png"}
tab_name=${2:-Refinement}
capture_state=${3:-success}
capture_width=${4:-1120}
capture_height=${5:-760}
font_base=${6:-0}
preview_phase=${7:-}
capture_root=$(mktemp -d /tmp/voxtype-prism-workbench-capture.XXXXXX)
cleanup() { rm -rf -- "$capture_root"; }
trap cleanup EXIT

mkdir -p "$capture_root/config"
ln -s /usr/share/omarchy/shell/Ui "$capture_root/Ui"
ln -s /usr/share/omarchy/shell/Commons "$capture_root/Commons"
ln -s "$repo_root/scripts" "$capture_root/scripts"

for file in \
  SettingsPanel.qml SettingsBackend.qml SettingsNavItem.qml \
  SettingsSlider.qml PrismTextArea.qml PrismPageHeader.qml \
  PrismFormField.qml PrismSection.qml PrismOpticalIconButton.qml \
  IndicatorVisual.qml; do
  ln -s "$repo_root/$file" "$capture_root/$file"
done

cat >"$capture_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
    id: shellRoot

    property QtObject shellMock: QtObject {
        function hide(pluginId) {}
    }

    SettingsPanel {
        id: workbench
        shell: shellRoot.shellMock
        manifest: ({ id: "io.github.jonhenshaw.voxtype-prism" })
        motionEnabled: false
        preferredWindowWidth: Number(Quickshell.env("VOXTYPE_PRISM_CAPTURE_WIDTH"))
        preferredWindowHeight: Number(Quickshell.env("VOXTYPE_PRISM_CAPTURE_HEIGHT"))
    }

    Component.onCompleted: Qt.callLater(function() {
        workbench.open(JSON.stringify({ tab: Quickshell.env("VOXTYPE_PRISM_CAPTURE_TAB") }))
    })

    Timer {
        interval: 400
        running: true
        repeat: false
        onTriggered: {
            var requestedFont = Number(Quickshell.env("VOXTYPE_PRISM_CAPTURE_FONT_BASE"))
            if (isFinite(requestedFont) && requestedFont > 0)
                Style.fontBaseSize = requestedFont
        }
    }

    Timer {
        interval: 2400
        running: true
        repeat: false
        onTriggered: {
            var output = Quickshell.env("VOXTYPE_PRISM_CAPTURE_PATH")
            var state = Quickshell.env("VOXTYPE_PRISM_CAPTURE_STATE")
            var captureWidth = Number(Quickshell.env("VOXTYPE_PRISM_CAPTURE_WIDTH"))
            var captureHeight = Number(Quickshell.env("VOXTYPE_PRISM_CAPTURE_HEIGHT"))
            if (!workbench.windowVisible || workbench.renderTarget.width !== captureWidth
                    || workbench.renderTarget.height !== captureHeight) {
                console.error("VOXTYPE_PRISM_CAPTURE_FAILED=invalid geometry "
                    + workbench.renderTarget.width + "x" + workbench.renderTarget.height)
                Qt.quit()
                return
            }
            if (state === "success" && workbench.selectedTab === 0) {
                var injected = false
                for (var i = 0; i < workbench.data.length; ++i) {
                    var candidate = workbench.data[i]
                    if (!candidate || candidate.testOutput === undefined
                            || candidate.testElapsedMs === undefined)
                        continue
                    candidate.testOutput = "I think we should ship the new Voxtype indicator."
                    candidate.testProvider = workbench.refineProvider
                    candidate.testModel = workbench.effectiveModel
                    candidate.testElapsedMs = 418
                    // Mark the captured draft dirty so Revert/Save match the
                    // selected mock's post-test, ready-to-save state.
                    workbench.refinePrompt += "\n"
                    workbench.testedFingerprint = workbench.currentTestFingerprint
                    injected = true
                    break
                }
                if (!injected) {
                    console.error("VOXTYPE_PRISM_CAPTURE_FAILED=backend state")
                    Qt.quit()
                    return
                }
            }
            if (workbench.selectedTab === 3
                    && ["signal", "halo", "bar-pulse"].indexOf(state) >= 0)
                workbench.indicatorPreset = state
            var requestedPhase = Quickshell.env("VOXTYPE_PRISM_CAPTURE_PHASE")
            if (workbench.selectedTab === 3 && requestedPhase !== "")
                workbench.previewPhase = requestedPhase
            workbench.renderTarget.grabToImage(function(result) {
                if (!result || !result.saveToFile(output))
                    console.error("VOXTYPE_PRISM_CAPTURE_FAILED=save")
                else
                    console.log("VOXTYPE_PRISM_CAPTURE_SAVED=" + output)
                Qt.quit()
            }, Qt.size(captureWidth, captureHeight))
        }
    }
}
QML

output=$(timeout 8s env \
  VOXTYPE_PRISM_CAPTURE_PATH="$output_path" \
  VOXTYPE_PRISM_CAPTURE_TAB="$tab_name" \
  VOXTYPE_PRISM_CAPTURE_STATE="$capture_state" \
  VOXTYPE_PRISM_CAPTURE_WIDTH="$capture_width" \
  VOXTYPE_PRISM_CAPTURE_HEIGHT="$capture_height" \
  VOXTYPE_PRISM_CAPTURE_FONT_BASE="$font_base" \
  VOXTYPE_PRISM_CAPTURE_PHASE="$preview_phase" \
  VOXTYPE_PRISM_DISABLE_LAUNCHER=1 \
  VOXTYPE_PRISM_NO_RESTART=1 \
  QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software \
  QT_SCALE_FACTOR=1 \
  quickshell --no-color -p "$capture_root/shell.qml" 2>&1)

printf '%s\n' "$output"
grep -Fq "VOXTYPE_PRISM_CAPTURE_SAVED=$output_path" <<<"$output"
