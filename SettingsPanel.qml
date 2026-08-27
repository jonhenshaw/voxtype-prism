pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui

// On-demand desktop workbench for Voxtype Prism's enhancement layer. This is
// intentionally a normal FloatingWindow: unlike the recording indicator it is
// a full application surface and must participate in ordinary window focus,
// workspaces, resizing, and accessibility.
Item {
    id: root

    property var shell: null
    property var manifest: null

    // Qt/Quattro currently exposes no system reduced-motion preference. Keep
    // this injectable so the host (or a future shell preference) can disable
    // every decorative transition and indicator preview animation at once.
    property bool motionEnabled: true

    readonly property string pluginId: manifest && manifest.id
        ? String(manifest.id) : "io.github.jonhenshaw.voxtype-prism"
    property alias windowVisible: window.visible
    readonly property Item renderTarget: focusScope
    readonly property bool opened: window.visible

    property int selectedTab: 0
    property bool closingFromHost: false
    property bool suppressVisibilityNotification: false
    property bool discardDialogVisible: false
    property bool shortcutsVisible: false
    property string pendingCloseAction: "close"
    property var focusBeforeModal: null
    readonly property bool modalVisible: discardDialogVisible || shortcutsVisible

    property bool refineEnabled: false
    property string refineProvider: ""
    property string refineModel: ""
    property string refinePrompt: ""
    property string refineDictionary: ""

    property string indicatorPreset: "signal"
    property string indicatorPosition: "bottom-center"
    property real indicatorScale: 1.0
    property bool indicatorMotion: true
    property real indicatorGlow: 0.6
    property string previewPhase: "recording"
    property var previewLevels: [0.30, 0.54, 0.74, 0.43, 0.82, 0.61, 0.36, 0.68, 0.48]

    property string rawSample: "um i think we should ship the new vox type indicator"
    property string pendingTestFingerprint: ""
    property string testedFingerprint: ""

    readonly property var savedRefine: backend.settings && backend.settings.refine
        ? backend.settings.refine : ({})
    readonly property var savedIndicator: backend.settings && backend.settings.indicator
        ? backend.settings.indicator : ({})
    readonly property string savedModelOverride: savedRefine.modelOverride
        ? String(savedRefine.model || "") : ""

    readonly property string effectiveModel: refineModel.trim()
        || providerDefaultModel(refineProvider)
        || (refineProvider === String(savedRefine.provider || "")
            ? String(savedRefine.model || "") : "")

    readonly property int sampleBytes: backend.utf8ByteLength(rawSample)
    readonly property int modelBytes: backend.utf8ByteLength(refineModel)
    readonly property int promptBytes: backend.utf8ByteLength(refinePrompt)
    readonly property int dictionaryBytes: backend.utf8ByteLength(refineDictionary)
    readonly property bool modelTooLarge: modelBytes > 512
    readonly property bool promptTooLarge: promptBytes > 32768
    readonly property bool dictionaryTooLarge: dictionaryBytes > 32768
    readonly property bool sampleTooLarge: sampleBytes > 4096
    readonly property bool draftWithinLimits: !modelTooLarge && !promptTooLarge && !dictionaryTooLarge
    readonly property bool testWithinLimits: draftWithinLimits && !sampleTooLarge
    readonly property string validationMessage: modelTooLarge
        ? "Model override exceeds 512 bytes"
        : (promptTooLarge ? "Prompt exceeds 32,768 bytes"
        : (dictionaryTooLarge ? "Dictionary exceeds 32,768 bytes"
        : (sampleTooLarge ? "Test sample exceeds 4,096 bytes" : "")))

    readonly property string currentTestFingerprint: JSON.stringify([
        rawSample, refineProvider, refineModel, refinePrompt, refineDictionary
    ])
    readonly property bool testOutputStale: backend.testOutput !== ""
        && testedFingerprint !== currentTestFingerprint

    readonly property bool dirty: backend.hasSnapshot && (
        refineEnabled !== Boolean(savedRefine.enabled)
        || refineProvider !== String(savedRefine.provider || "")
        || refineModel !== savedModelOverride
        || refinePrompt !== String(savedRefine.prompt || "")
        || refineDictionary !== String(savedRefine.dictionary || "")
        || indicatorPreset !== String(savedIndicator.preset || "signal")
        || indicatorPosition !== String(savedIndicator.position || "bottom-center")
        || Math.abs(indicatorScale - finiteNumber(savedIndicator.scale, 1.0)) > 0.0001
        || indicatorMotion !== (savedIndicator.motion === undefined ? true : Boolean(savedIndicator.motion))
        || Math.abs(indicatorGlow - finiteNumber(savedIndicator.glow, 0.6)) > 0.0001)

    readonly property var providerOptions: catalogOptions(
        backend.catalog && backend.catalog.providers ? backend.catalog.providers : [],
        refineProvider)
    readonly property var presetOptions: catalogOptions(
        backend.catalog && backend.catalog.indicator && backend.catalog.indicator.presets
            ? backend.catalog.indicator.presets : [], indicatorPreset)
    readonly property var positionOptions: catalogOptions(
        backend.catalog && backend.catalog.indicator && backend.catalog.indicator.positions
            ? backend.catalog.indicator.positions : [], indicatorPosition)

    readonly property var scaleRange: backend.catalog && backend.catalog.indicator
        && backend.catalog.indicator.scale ? backend.catalog.indicator.scale : ({ min: 0.75, max: 1.5, step: 0.05 })
    readonly property var glowRange: backend.catalog && backend.catalog.indicator
        && backend.catalog.indicator.glow ? backend.catalog.indicator.glow : ({ min: 0, max: 1, step: 0.05 })

    readonly property var readiness: readinessFor(refineProvider)
    readonly property bool providerReady: Boolean(readiness.ready)
    readonly property string providerReadinessText: String(readiness.message || (providerReady ? "Ready" : "Needs setup"))

    readonly property QtObject indicatorPalette: QtObject {
        readonly property color background: Color.background
        readonly property color panel: Color.popups.background
        readonly property color foreground: Color.foreground
        readonly property color mutedText: Color.muted
        readonly property color accent: Color.accent
        readonly property color recording: Color.urgent
        readonly property color transcribing: Color.accent
        readonly property color ready: Color.accent
    }

    readonly property var tabs: [
        { label: "Refinement", shortcut: "Alt+1" },
        { label: "Prompt", shortcut: "Alt+2" },
        { label: "Dictionary", shortcut: "Alt+3" },
        { label: "Indicator", shortcut: "Alt+4" }
    ]

    function finiteNumber(value, fallback) {
        const number = Number(value)
        return isFinite(number) ? number : fallback
    }

    function titleCase(value) {
        return String(value || "").replace(/[-_]+/g, " ").replace(/\b\w/g,
            function(letter) { return letter.toUpperCase() })
    }

    function phaseLabel(value) {
        if (value === "recording") return "Listening"
        if (value === "transcribing") return "Transcribing"
        if (value === "ready") return "Done"
        if (value === "streaming") return "Streaming"
        return titleCase(value)
    }

    function optionValue(option) {
        if (option && typeof option === "object")
            return String(option.value !== undefined ? option.value
                : (option.id !== undefined ? option.id : option.label))
        return String(option)
    }

    function optionLabel(option) {
        if (option && typeof option === "object")
            return String(option.label !== undefined ? option.label
                : (option.name !== undefined ? option.name : optionValue(option)))
        return titleCase(option)
    }

    function catalogOptions(source, current) {
        const result = []
        const values = source && Array.isArray(source) ? source : []
        for (let i = 0; i < values.length; ++i) {
            const value = optionValue(values[i])
            if (!value) continue
            result.push({ value: value, label: optionLabel(values[i]) })
        }
        if (current) {
            let found = false
            for (let j = 0; j < result.length; ++j)
                if (result[j].value === current) { found = true; break }
            if (!found) result.unshift({ value: current, label: titleCase(current) })
        }
        return result
    }

    function providerRecord(providerId) {
        const providers = backend.catalog && backend.catalog.providers
            && Array.isArray(backend.catalog.providers) ? backend.catalog.providers : []
        for (let i = 0; i < providers.length; ++i) {
            const provider = providers[i]
            if (optionValue(provider) === providerId) return provider
        }
        return null
    }

    function providerDefaultModel(providerId) {
        const provider = providerRecord(providerId)
        return provider ? String(provider.defaultModel || provider.model || "") : ""
    }

    function readinessFor(providerId) {
        const provider = providerRecord(providerId)
        let state = provider ? provider.readiness : undefined
        if (state === undefined && providerId === String(savedRefine.provider || ""))
            state = savedRefine.readiness

        if (typeof state === "boolean")
            return { ready: state, message: state ? "Ready" : "Needs setup" }
        if (typeof state === "string") {
            const normalized = state.toLowerCase()
            const ready = normalized === "ready" || normalized === "available" || normalized === "ok"
            return { ready: ready, message: titleCase(state) }
        }
        if (state && typeof state === "object") {
            const ready = state.ready === true || state.status === "ready"
                || state.available === true
            return { ready: ready, message: String(state.message || state.label
                || (ready ? "Ready" : "Needs setup")) }
        }
        return { ready: false, message: "Readiness unknown" }
    }

    function rangeMin(range, fallback) {
        return finiteNumber(range && range.min, fallback)
    }

    function rangeMax(range, fallback) {
        return finiteNumber(range && range.max, fallback)
    }

    function rangeStep(range, fallback) {
        return finiteNumber(range && range.step, fallback)
    }

    function syncDraft() {
        const refine = savedRefine
        const indicator = savedIndicator
        refineEnabled = Boolean(refine.enabled)
        refineProvider = String(refine.provider || "")
        // modelOverride is a presence boolean; model is the effective value.
        // Only populate the editor when an override actually exists.
        refineModel = refine.modelOverride ? String(refine.model || "") : ""
        refinePrompt = String(refine.prompt || "")
        refineDictionary = String(refine.dictionary || "")
        indicatorPreset = String(indicator.preset || "signal")
        indicatorPosition = String(indicator.position || "bottom-center")
        indicatorScale = finiteNumber(indicator.scale, 1.0)
        indicatorMotion = indicator.motion === undefined ? true : Boolean(indicator.motion)
        indicatorGlow = finiteNumber(indicator.glow, 0.6)
    }

    function chooseProvider(value) {
        const oldDefault = providerDefaultModel(refineProvider)
        const shouldClearOverride = !refineModel.trim() || refineModel === oldDefault
        refineProvider = String(value)
        if (shouldClearOverride) refineModel = ""
    }

    function draftObject() {
        return {
            refine: {
                enabled: refineEnabled,
                provider: refineProvider,
                model: refineModel,
                prompt: refinePrompt,
                dictionary: refineDictionary
            },
            indicator: {
                preset: indicatorPreset,
                position: indicatorPosition,
                scale: indicatorScale,
                motion: indicatorMotion,
                glow: indicatorGlow
            }
        }
    }

    function saveChanges() {
        if (!dirty || backend.busy) return
        if (!draftWithinLimits) {
            backend.setLocalError("Save", validationMessage)
            return
        }
        backend.save(backend.buildPatch(draftObject()))
    }

    function runTest() {
        if (backend.busy) return
        if (!testWithinLimits) {
            backend.setLocalError("Test refinement", validationMessage)
            return
        }
        pendingTestFingerprint = currentTestFingerprint
        backend.testRefinement(rawSample, {
            provider: refineProvider,
            model: refineModel,
            prompt: refinePrompt,
            dictionary: refineDictionary
        })
    }

    function selectTab(index) {
        if (index < 0 || index >= tabs.length) return
        selectedTab = index
        if (shortcutsVisible) hideShortcuts()
    }

    function applyDraftPatch(patch) {
        if (!patch || typeof patch !== "object") return
        const refine = patch.refine || {}
        const indicator = patch.indicator || {}
        if (refine.enabled !== undefined) refineEnabled = Boolean(refine.enabled)
        if (refine.provider !== undefined) refineProvider = String(refine.provider)
        if (refine.model !== undefined) refineModel = String(refine.model)
        if (refine.prompt !== undefined) refinePrompt = String(refine.prompt)
        if (refine.dictionary !== undefined) refineDictionary = String(refine.dictionary)
        if (indicator.preset !== undefined) indicatorPreset = String(indicator.preset)
        if (indicator.position !== undefined) indicatorPosition = String(indicator.position)
        if (indicator.scale !== undefined) indicatorScale = finiteNumber(indicator.scale, 1.0)
        if (indicator.motion !== undefined) indicatorMotion = Boolean(indicator.motion)
        if (indicator.glow !== undefined) indicatorGlow = finiteNumber(indicator.glow, 0.6)
    }

    function keepDraftAfterConflict() {
        const draftPatch = backend.rebaseConflictDraft(draftObject())
        if (!draftPatch) return
        syncDraft()
        applyDraftPatch(draftPatch)
        backend.successMessage = "Draft kept on top of external changes"
    }

    function reloadExternalChanges() {
        if (!backend.adoptRevisionConflictSnapshot()) return
        syncDraft()
        backend.successMessage = "External changes loaded"
    }

    function rememberModalFocus() {
        const owningWindow = focusScope.QsWindow.window
        focusBeforeModal = owningWindow ? owningWindow.activeFocusItem : null
    }

    function restoreModalFocus() {
        const target = focusBeforeModal
        focusBeforeModal = null
        Qt.callLater(function() {
            if (target && target.visible && target.enabled) target.forceActiveFocus()
            else focusScope.forceActiveFocus()
        })
    }

    function showShortcuts() {
        if (discardDialogVisible) return
        rememberModalFocus()
        shortcutsVisible = true
        Qt.callLater(function() { closeShortcutsButton.forceActiveFocus() })
    }

    function hideShortcuts() {
        if (!shortcutsVisible) return
        shortcutsVisible = false
        restoreModalFocus()
    }

    function showDiscardDialog() {
        if (!discardDialogVisible) rememberModalFocus()
        discardDialogVisible = true
        Qt.callLater(function() { keepEditingButton.forceActiveFocus() })
    }

    function closeDiscardDialog() {
        if (!discardDialogVisible) return
        discardDialogVisible = false
        restoreModalFocus()
    }

    function open(payloadJson) {
        closingFromHost = false
        let requestedTab = -1
        if (payloadJson) {
            try {
                const payload = JSON.parse(String(payloadJson))
                if (payload && typeof payload.tab === "string") {
                    const wanted = payload.tab.toLowerCase()
                    for (let i = 0; i < tabs.length; ++i)
                        if (tabs[i].label.toLowerCase() === wanted) requestedTab = i
                }
            } catch (error) {
                // An invalid optional summon payload should not block settings.
            }
        }
        if (requestedTab >= 0) selectedTab = requestedTab
        if (window.visible && dirty) {
            Qt.callLater(function() { focusScope.forceActiveFocus() })
            return
        }
        window.visible = true
        if (!backend.busy) backend.load()
        Qt.callLater(function() { focusScope.forceActiveFocus() })
    }

    function close() {
        // Host toggle/hide reaches this method before it updates its own open
        // bookkeeping. Keep the loaded panel visible until the user resolves a
        // dirty draft; finishClose() first resets/saves the draft and then asks
        // the host to hide again.
        if (window.visible && dirty) {
            pendingCloseAction = "close"
            showDiscardDialog()
            return
        }
        closingFromHost = true
        suppressVisibilityNotification = true
        window.visible = false
        suppressVisibilityNotification = false
        discardDialogVisible = false
        shortcutsVisible = false
        focusBeforeModal = null
        closingFromHost = false
    }

    function requestClose(action) {
        pendingCloseAction = action || "close"
        if (dirty) {
            showDiscardDialog()
            return
        }
        finishClose(pendingCloseAction)
    }

    function finishClose(action) {
        const launchAdvanced = action === "advanced"
        discardDialogVisible = false
        shortcutsVisible = false
        focusBeforeModal = null
        suppressVisibilityNotification = true
        window.visible = false
        suppressVisibilityNotification = false
        // Start the stock TUI while this Loader is still alive. shell.hide may
        // immediately destroy the panel instance after it is notified.
        if (launchAdvanced)
            Quickshell.execDetached(["/usr/bin/voxtype-configure-launcher"])
        if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    }

    SettingsBackend { id: backend }

    Connections {
        target: backend
        function onSnapshotLoaded() { root.syncDraft() }
        function onSaveSucceeded() { root.syncDraft() }
        function onTestSucceeded() { root.testedFingerprint = root.pendingTestFingerprint }
    }

    Timer {
        interval: 4200
        running: backend.successMessage !== ""
        repeat: false
        onTriggered: backend.successMessage = ""
    }

    Shortcut { sequence: "Ctrl+S"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.saveChanges() }
    Shortcut { sequence: "Ctrl+Return"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.runTest() }
    Shortcut { sequence: "Ctrl+Enter"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.runTest() }
    Shortcut { sequence: "Alt+1"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.selectTab(0) }
    Shortcut { sequence: "Alt+2"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.selectTab(1) }
    Shortcut { sequence: "Alt+3"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.selectTab(2) }
    Shortcut { sequence: "Alt+4"; enabled: !root.modalVisible; context: Qt.WindowShortcut; onActivated: root.selectTab(3) }
    Shortcut {
        sequence: "F1"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.discardDialogVisible) return
            if (root.shortcutsVisible) root.hideShortcuts()
            else root.showShortcuts()
        }
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.discardDialogVisible) root.closeDiscardDialog()
            else if (root.shortcutsVisible) root.hideShortcuts()
            else root.requestClose("close")
        }
    }

    FloatingWindow {
        id: window
        visible: false
        title: "Voxtype Prism"
        color: Color.background
        implicitWidth: 1120
        implicitHeight: 760
        minimumSize: Qt.size(900, 620)

        onVisibleChanged: {
            if (!visible && !root.suppressVisibilityNotification && !root.closingFromHost
                    && root.shell && typeof root.shell.hide === "function")
                root.shell.hide(root.pluginId)
        }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: true

            // FloatingWindow wraps the backing QQuickWindow, so compositor
            // close requests arrive on the attached window rather than the
            // interface object itself.
            Connections {
                target: focusScope.QsWindow.window
                ignoreUnknownSignals: true
                function onClosing(closeEvent) {
                    if (!root.dirty) return
                    closeEvent.accepted = false
                    root.requestClose("close")
                }
            }

            Row {
                id: workbench
                anchors.fill: parent
                visible: backend.hasSnapshot
                enabled: !backend.loading && !root.modalVisible
                opacity: enabled ? 1 : 0.62

                Behavior on opacity {
                    enabled: root.motionEnabled
                    NumberAnimation { duration: 100 }
                }

                Rectangle {
                    id: navigationRail
                    width: Math.max(Style.space(184), Math.round(window.width * 0.18))
                    height: parent.height
                    color: Color.popups.background

                    Column {
                        anchors.fill: parent
                        anchors.topMargin: Style.space(24)
                        anchors.bottomMargin: Style.space(22)
                        spacing: Style.spacing.md

                        Text {
                            text: "Voxtype Prism"
                            color: Color.accent
                            leftPadding: Style.spacing.panelPadding
                            rightPadding: Style.spacing.panelPadding
                            bottomPadding: Style.space(20)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.heading
                            font.bold: true
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        Repeater {
                            model: root.tabs

                            SettingsNavItem {
                                required property var modelData
                                required property int index
                                width: navigationRail.width
                                text: String(modelData.label)
                                shortcutText: String(modelData.shortcut)
                                selected: root.selectedTab === index
                                onClicked: root.selectTab(index)
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.spacing.panelPadding
                        spacing: Style.spacing.lg

                        Ui.Button {
                            width: parent.width
                            leftAlign: true
                            focusable: true
                            iconText: "?"
                            text: "Shortcuts"
                            tooltipText: "Keyboard shortcuts (F1)"
                            onClicked: root.showShortcuts()
                        }

                        Text {
                            width: parent.width
                            text: backend.hasSnapshot
                                ? (root.dirty ? "Unsaved changes" : "All changes saved")
                                : "Loading settings"
                            color: root.dirty ? Color.accent : Qt.darker(Color.foreground, 1.55)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    width: Math.max(Style.spacing.hairline, 1)
                    height: parent.height
                    color: Style.normalBorderFor(Color.foreground, Color.accent)
                }

                Item {
                    id: mainArea
                    width: parent.width - navigationRail.width - 1
                    height: parent.height

                    StackLayout {
                        id: pageStack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: statusBanner.top
                        anchors.leftMargin: Style.space(42)
                        anchors.rightMargin: Style.space(42)
                        anchors.topMargin: Style.space(26)
                        anchors.bottomMargin: Style.space(18)
                        currentIndex: root.selectedTab

                        // -------------------------------------------------- Refinement
                        Item {
                            id: refinementPage

                            Column {
                                anchors.fill: parent
                                spacing: Style.space(14)

                                Row {
                                    width: parent.width
                                    height: Style.space(58)
                                    spacing: Style.spacing.controlGap

                                    Text {
                                        text: "Refinement"
                                        color: Color.foreground
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.display
                                        font.bold: true
                                        Accessible.role: Accessible.Heading
                                        Accessible.name: text
                                    }

                                    Ui.Toggle {
                                        checked: root.refineEnabled
                                        width: Style.space(170)
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: root.refineEnabled ? "Enabled" : "Disabled"
                                        titleSize: Style.font.body
                                        Accessible.name: "Enable LLM refinement"
                                        Accessible.description: checked ? "Enabled" : "Disabled"
                                        onClicked: root.refineEnabled = !root.refineEnabled
                                    }

                                    Item {
                                        width: Math.max(0, parent.width - x - listeningPill.width
                                            - parent.spacing)
                                        height: 1
                                    }

                                    Item {
                                        id: listeningPill
                                        width: Style.space(210)
                                        height: Style.space(58)
                                        anchors.verticalCenter: parent.verticalCenter
                                        Accessible.role: Accessible.StaticText
                                        Accessible.name: "Indicator preview: listening"

                                        IndicatorVisual {
                                            anchors.centerIn: parent
                                            styleId: "signal"
                                            phase: "recording"
                                            levels: root.previewLevels
                                            themePalette: root.indicatorPalette
                                            scaleFactor: 1.15
                                            glowIntensity: root.indicatorGlow
                                            motionEnabled: false
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: Math.max(Style.space(76), providerColumn.implicitHeight,
                                        modelColumn.implicitHeight, readinessGroup.implicitHeight)
                                    spacing: Style.space(18)

                                    Column {
                                        id: providerColumn
                                        width: Math.max(Style.space(250), parent.width * 0.36)
                                        spacing: Style.spacing.labelGap

                                        Text {
                                            text: "Provider"
                                            color: Qt.darker(Color.foreground, 1.4)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                            font.bold: true
                                        }

                                        Ui.Dropdown {
                                            id: providerPicker
                                            width: parent.width
                                            showLabel: false
                                            value: root.refineProvider
                                            options: root.providerOptions
                                            Accessible.name: "Refinement provider"
                                            onChanged: function(value) { root.chooseProvider(value) }
                                        }
                                    }

                                    Column {
                                        id: modelColumn
                                        width: Math.max(Style.space(190), parent.width * 0.28)
                                        spacing: Style.spacing.labelGap

                                        Row {
                                            width: parent.width
                                            Text {
                                                width: parent.width - modelByteCount.width
                                                text: "Model override"
                                                color: Qt.darker(Color.foreground, 1.4)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                            }
                                            Text {
                                                id: modelByteCount
                                                text: root.modelBytes + " / 512 bytes"
                                                color: root.modelTooLarge ? Color.urgent
                                                    : Qt.darker(Color.foreground, 1.55)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Ui.TextField {
                                            id: modelField
                                            width: parent.width
                                            text: root.refineModel
                                            placeholderText: root.providerDefaultModel(root.refineProvider)
                                                ? "Default · " + root.providerDefaultModel(root.refineProvider)
                                                : "Provider default"
                                            Accessible.name: "Refinement model"
                                            Accessible.description: "Optional. Leave blank to follow the provider default."
                                            maximumLength: 512
                                            accent: root.modelTooLarge ? Color.urgent : Color.accent
                                            onTextEdited: root.refineModel = text
                                        }

                                        Text {
                                            width: parent.width
                                            text: "Effective · " + (root.effectiveModel || "Unavailable")
                                            color: root.effectiveModel ? Color.accent : Color.urgent
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideMiddle
                                            Accessible.name: "Effective model "
                                                + (root.effectiveModel || "unavailable")
                                        }
                                    }

                                    Item { width: Math.max(0, parent.width - x - readinessGroup.width); height: 1 }

                                    Row {
                                        id: readinessGroup
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.spacing.lg

                                        Rectangle {
                                            width: Style.space(9)
                                            height: width
                                            radius: Style.cornerRadius > 0 ? width / 2 : 0
                                            color: root.providerReady ? Color.accent : Color.urgent
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Column {
                                            spacing: Style.spacing.xs
                                            Text {
                                                text: "Credentials"
                                                color: Qt.darker(Color.foreground, 1.5)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                            }
                                            Text {
                                                text: root.providerReadinessText
                                                color: root.providerReady ? Color.foreground : Color.urgent
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                                Accessible.name: "Provider credentials: " + text
                                            }
                                        }
                                    }
                                }

                                Ui.PanelSeparator { width: parent.width; foreground: Color.foreground }

                                Text {
                                    width: parent.width
                                    text: "Test how your dictated text is refined by the current draft. Testing does not save your changes."
                                    color: Qt.darker(Color.foreground, 1.4)
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                }

                                Row {
                                    id: comparisonRow
                                    width: parent.width
                                    height: Math.max(Style.space(160), parent.height - y - testButton.height
                                        - privacyRow.height - Style.space(48))
                                    spacing: Style.space(18)

                                    Column {
                                        width: (parent.width - comparisonArrow.width - parent.spacing * 2) / 2
                                        height: parent.height
                                        spacing: Style.spacing.md

                                        Text {
                                            text: "Raw dictated text"
                                            color: Color.foreground
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.subtitle
                                            font.bold: true
                                        }

                                        PrismTextArea {
                                            id: rawEditor
                                            width: parent.width
                                            height: parent.height - y
                                            text: root.rawSample
                                            accessibleName: "Raw dictated text sample"
                                            accessibleDescription: "Text sent when testing refinement"
                                            maximumLength: 8192
                                            maximumBytes: 4096
                                            hasError: root.sampleTooLarge
                                            onEdited: root.rawSample = text
                                        }
                                    }

                                    Text {
                                        id: comparisonArrow
                                        width: Style.space(28)
                                        text: "→"
                                        color: Qt.darker(Color.foreground, 1.25)
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.display
                                        Accessible.ignored: true
                                    }

                                    Column {
                                        width: (parent.width - comparisonArrow.width - parent.spacing * 2) / 2
                                        height: parent.height
                                        spacing: Style.spacing.md

                                        Text {
                                            text: "Refined output"
                                            color: Color.foreground
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.subtitle
                                            font.bold: true
                                        }

                                        PrismTextArea {
                                            width: parent.width
                                            height: parent.height - outputStatus.height - parent.spacing * 2 - y
                                            text: backend.testOutput
                                            readOnly: true
                                            hasError: backend.errorMessage !== "" && !backend.testing
                                            opacity: root.testOutputStale ? 0.62 : 1
                                            placeholderText: backend.testing
                                                ? "Refining…" : "Run a test to preview the result"
                                            accessibleName: "Refined output"
                                            accessibleDescription: "Latest LLM refinement result"
                                        }

                                        Text {
                                            id: outputStatus
                                            width: parent.width
                                            text: backend.testing ? "Testing refinement…"
                                                : (backend.errorMessage ? backend.errorMessage
                                                : (root.testOutputStale ? "Result is stale · test the current draft again"
                                                : (backend.testOutput ? "Refinement completed"
                                                + (backend.testElapsedMs > 0 ? " · " + backend.testElapsedMs + " ms" : "") : "")))
                                            visible: text !== ""
                                            color: backend.errorMessage || root.testOutputStale
                                                ? Color.urgent : Color.accent
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                            elide: Text.ElideRight
                                            Accessible.name: text
                                        }
                                    }
                                }

                                Ui.Button {
                                    id: testButton
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: backend.testing ? "Testing…"
                                        : (root.testOutputStale ? "Retest refinement" : "Test refinement")
                                    iconText: backend.testing ? "󰑮" : "󰑐"
                                    iconSpinning: backend.testing && root.motionEnabled
                                    tooltipText: "Test current draft (Ctrl+Enter)"
                                    focusable: true
                                    bordered: true
                                    active: true
                                    accent: Color.accent
                                    enabled: !backend.busy && root.rawSample.trim() !== ""
                                        && root.testWithinLimits
                                    opacity: enabled ? 1 : 0.5
                                    onClicked: root.runTest()
                                    Accessible.name: text
                                    Accessible.description: "Shortcut Ctrl+Enter"
                                }

                                Row {
                                    id: privacyRow
                                    width: parent.width
                                    spacing: Style.spacing.controlGap

                                    Text {
                                        text: "󰌾"
                                        color: Qt.darker(Color.foreground, 1.4)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.icon
                                    }

                                    Text {
                                        width: parent.width - x
                                        text: "Privacy: dictated text is sent to the selected provider for refinement. Credentials remain in OhMyPi and are never displayed here. Do not include sensitive or personal information in test content."
                                        color: Qt.darker(Color.foreground, 1.5)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Prompt
                        Item {
                            id: promptPage

                            Column {
                                anchors.fill: parent
                                spacing: Style.space(16)

                                Column {
                                    width: parent.width
                                    spacing: Style.spacing.sm

                                    Text {
                                        text: "Custom prompt"
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.display
                                        font.bold: true
                                        Accessible.role: Accessible.Heading
                                        Accessible.name: text
                                    }
                                    Text {
                                        width: parent.width
                                        text: "Tell the model how to clean your dictation. The dictionary is appended automatically when a refinement runs."
                                        color: Qt.darker(Color.foreground, 1.4)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Ui.BorderSurface {
                                    width: parent.width
                                    height: Style.space(66)
                                    color: Style.normalFillFor(Color.foreground, Color.accent)
                                    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                    radius: Style.cornerRadius

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: Style.spacing.rowPaddingX
                                        spacing: Style.spacing.controlGap

                                        Text {
                                            text: "󰭹"
                                            color: Color.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.iconLarge
                                        }

                                        Column {
                                            width: parent.width - x
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Style.spacing.xs
                                            Text {
                                                text: "Keep the instruction narrow"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                            }
                                            Text {
                                                width: parent.width
                                                text: "Ask for corrections without adding facts, commentary, Markdown, or a new tone."
                                                color: Qt.darker(Color.foreground, 1.5)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "System prompt"
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.subtitle
                                    font.bold: true
                                }

                                PrismTextArea {
                                    id: promptEditor
                                    width: parent.width
                                    height: parent.height - y - promptActions.height - parent.spacing
                                    text: root.refinePrompt
                                    placeholderText: "Describe how the model should refine speech-to-text…"
                                    accessibleName: "Custom refinement system prompt"
                                    accessibleDescription: "Saved to your Voxtype refine prompt file"
                                    maximumLength: 32768
                                    maximumBytes: 32768
                                    showCount: true
                                    hasError: root.promptTooLarge
                                    onEdited: root.refinePrompt = text
                                }

                                Row {
                                    id: promptActions
                                    width: parent.width
                                    spacing: Style.spacing.controlGap

                                    Text {
                                        width: Math.max(0, parent.width - testPromptButton.width)
                                        text: "Stored locally in ~/.config/voxtype/refine-prompt.md"
                                        color: Qt.darker(Color.foreground, 1.55)
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideMiddle
                                    }

                                    Ui.Button {
                                        id: testPromptButton
                                        text: "Test this prompt"
                                        iconText: "󰑐"
                                        focusable: true
                                        bordered: true
                                        onClicked: {
                                            root.selectTab(0)
                                            Qt.callLater(function() { rawEditor.control.forceActiveFocus() })
                                        }
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Dictionary
                        Item {
                            id: dictionaryPage

                            Column {
                                anchors.fill: parent
                                spacing: Style.space(18)

                                Column {
                                    width: parent.width
                                    spacing: Style.spacing.sm

                                    Text {
                                        text: "Custom dictionary"
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.display
                                        font.bold: true
                                        Accessible.role: Accessible.Heading
                                        Accessible.name: text
                                    }
                                    Text {
                                        width: parent.width
                                        text: "Teach refinement your names, technical terms, and preferred spellings. One entry per line."
                                        color: Qt.darker(Color.foreground, 1.4)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: parent.height - y
                                    spacing: Style.space(20)

                                    Column {
                                        width: parent.width * 0.66
                                        height: parent.height
                                        spacing: Style.spacing.md

                                        Text {
                                            text: "Preferred terms"
                                            color: Color.foreground
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.subtitle
                                            font.bold: true
                                        }

                                        PrismTextArea {
                                            id: dictionaryEditor
                                            width: parent.width
                                            height: parent.height - y - dictionaryLocation.height - parent.spacing
                                            text: root.refineDictionary
                                            placeholderText: "Hyprland\nQuickshell\nvox type → Voxtype"
                                            accessibleName: "Custom refinement dictionary"
                                            accessibleDescription: "One preferred spelling or mapping per line"
                                            maximumLength: 32768
                                            maximumBytes: 32768
                                            showCount: true
                                            hasError: root.dictionaryTooLarge
                                            onEdited: root.refineDictionary = text
                                        }

                                        Text {
                                            id: dictionaryLocation
                                            width: parent.width
                                            text: "Stored locally in ~/.config/voxtype/refine-dictionary.md"
                                            color: Qt.darker(Color.foreground, 1.55)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    Ui.BorderSurface {
                                        width: parent.width - x
                                        height: parent.height
                                        color: Style.normalFillFor(Color.foreground, Color.accent)
                                        borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                        radius: Style.cornerRadius

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: Style.spacing.panelPadding
                                            spacing: Style.space(16)

                                            Text {
                                                text: "Dictionary format"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.heading
                                                font.bold: true
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Use a preferred spelling by itself:"
                                                color: Qt.darker(Color.foreground, 1.4)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                wrapMode: Text.WordWrap
                                            }

                                            Ui.BorderSurface {
                                                width: parent.width
                                                height: Style.space(46)
                                                color: Color.background
                                                borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                                radius: Style.cornerRadius
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Style.spacing.controlPaddingX
                                                    text: "Hyprland"
                                                    color: Color.accent
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.body
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Or map the way a term sounds to the way it should be written:"
                                                color: Qt.darker(Color.foreground, 1.4)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                wrapMode: Text.WordWrap
                                            }

                                            Ui.BorderSurface {
                                                width: parent.width
                                                height: Style.space(46)
                                                color: Color.background
                                                borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                                radius: Style.cornerRadius
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Style.spacing.controlPaddingX
                                                    text: "quick shell → Quickshell"
                                                    color: Color.accent
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.body
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Blank lines and lines beginning with # are ignored. Entries are appended to your prompt only when refinement runs."
                                                color: Qt.darker(Color.foreground, 1.5)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Indicator
                        Item {
                            id: indicatorPage

                            Column {
                                anchors.fill: parent
                                spacing: Style.space(16)

                                Column {
                                    width: parent.width
                                    spacing: Style.spacing.sm

                                    Text {
                                        text: "Indicator"
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.display
                                        font.bold: true
                                        Accessible.role: Accessible.Heading
                                        Accessible.name: text
                                    }
                                    Text {
                                        width: parent.width
                                        text: "Choose how Prism communicates recording and refinement without changing Voxtype itself."
                                        color: Qt.darker(Color.foreground, 1.4)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Ui.BorderSurface {
                                    id: indicatorPreviewCard
                                    width: parent.width
                                    height: Math.max(Style.space(190), parent.height * 0.38)
                                    color: Color.popups.background
                                    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                    radius: Style.cornerRadius
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: root.titleCase(root.indicatorPreset)
                                        + " indicator preview in " + root.phaseLabel(root.previewPhase) + " state"

                                    Text {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: Style.spacing.rowPaddingX
                                        text: "LIVE PREVIEW · " + root.phaseLabel(root.previewPhase).toUpperCase()
                                        color: Qt.darker(Color.foreground, 1.45)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        font.letterSpacing: 0.8
                                    }

                                    Loader {
                                        id: indicatorVisualLoader
                                        anchors.centerIn: parent
                                        source: Qt.resolvedUrl("IndicatorVisual.qml")
                                    }

                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "styleId"
                                        value: root.indicatorPreset
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "phase"
                                        value: root.previewPhase
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "levels"
                                        value: root.previewLevels
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "themePalette"
                                        value: root.indicatorPalette
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "scaleFactor"
                                        value: root.indicatorScale
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "glowIntensity"
                                        value: root.indicatorGlow
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }
                                    Binding {
                                        target: indicatorVisualLoader.item
                                        property: "motionEnabled"
                                        value: root.motionEnabled && root.indicatorMotion
                                        when: indicatorVisualLoader.status === Loader.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: indicatorVisualLoader.status === Loader.Error
                                        text: "Indicator preview unavailable"
                                        color: Color.urgent
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.body
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: parent.height - y
                                    spacing: Style.space(28)

                                    Column {
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        spacing: Style.space(14)

                                        Ui.Dropdown {
                                            width: parent.width
                                            label: "Indicator preset"
                                            value: root.indicatorPreset
                                            options: root.presetOptions
                                            Accessible.name: "Indicator preset"
                                            onChanged: function(value) { root.indicatorPreset = value }
                                        }

                                        Ui.Dropdown {
                                            width: parent.width
                                            label: "Screen position"
                                            value: root.indicatorPosition
                                            options: root.positionOptions
                                            Accessible.name: "Indicator screen position"
                                            onChanged: function(value) { root.indicatorPosition = value }
                                        }

                                        Ui.Dropdown {
                                            width: parent.width
                                            label: "Preview state"
                                            value: root.previewPhase
                                            options: [
                                                { value: "recording", label: "Listening" },
                                                { value: "transcribing", label: "Transcribing" },
                                                { value: "ready", label: "Done" }
                                            ]
                                            Accessible.name: "Indicator preview state"
                                            onChanged: function(value) { root.previewPhase = value }
                                        }
                                    }

                                    Column {
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        spacing: Style.space(16)

                                        SettingsSlider {
                                            width: parent.width
                                            label: "Scale"
                                            accessibleName: "Indicator scale"
                                            from: root.rangeMin(root.scaleRange, 0.75)
                                            to: root.rangeMax(root.scaleRange, 1.5)
                                            stepSize: root.rangeStep(root.scaleRange, 0.05)
                                            value: root.indicatorScale
                                            valueText: Math.round(root.indicatorScale * 100) + "%"
                                            onModified: function(value) { root.indicatorScale = value }
                                        }

                                        SettingsSlider {
                                            width: parent.width
                                            label: "Glow"
                                            accessibleName: "Indicator glow intensity"
                                            from: root.rangeMin(root.glowRange, 0)
                                            to: root.rangeMax(root.glowRange, 1)
                                            stepSize: root.rangeStep(root.glowRange, 0.05)
                                            value: root.indicatorGlow
                                            valueText: Math.round(root.indicatorGlow * 100) + "%"
                                            onModified: function(value) { root.indicatorGlow = value }
                                        }

                                        Ui.Toggle {
                                            width: parent.width
                                            label: "Indicator motion"
                                            description: root.indicatorMotion
                                                ? "Waveforms and phase changes animate"
                                                : "Preview and live indicator remain still"
                                            checked: root.indicatorMotion
                                            Accessible.name: "Indicator motion"
                                            Accessible.description: description
                                            onClicked: root.indicatorMotion = !root.indicatorMotion
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Ui.BorderSurface {
                        id: statusBanner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: actionFooter.top
                        anchors.leftMargin: Style.space(42)
                        anchors.rightMargin: Style.space(42)
                        height: visible
                            ? (backend.hasRevisionConflict ? Style.space(64) : Style.space(44)) : 0
                        visible: backend.hasRevisionConflict || backend.warningMessage !== ""
                            || root.validationMessage !== "" || backend.saving || backend.loading
                            || backend.errorMessage !== "" || backend.successMessage !== ""
                        color: Style.normalFillFor(Color.foreground,
                            backend.hasRevisionConflict || backend.warningMessage !== ""
                                || root.validationMessage !== "" || backend.errorMessage !== ""
                                ? Color.urgent : Color.accent)
                        borderSpec: Border.controlSpec("normal", Color.foreground,
                            backend.hasRevisionConflict || backend.warningMessage !== ""
                                || root.validationMessage !== "" || backend.errorMessage !== ""
                                ? Color.urgent : Color.accent)
                        radius: Style.cornerRadius
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: statusBannerText.text

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.rowPaddingX
                            anchors.rightMargin: Style.spacing.rowPaddingX
                            spacing: Style.spacing.controlGap

                            Text {
                                id: statusBannerText
                                width: parent.width
                                    - (backend.hasRevisionConflict
                                        ? keepDraftButton.width + reloadExternalButton.width
                                            + parent.spacing * 2 : 0)
                                anchors.verticalCenter: parent.verticalCenter
                                text: backend.hasRevisionConflict
                                    ? "Settings changed outside Prism. Keep this draft or load the external changes."
                                    : (backend.errorMessage
                                    || root.validationMessage
                                    || backend.warningMessage
                                    || (backend.saving ? "Saving changes…" : "")
                                    || (backend.loading ? "Refreshing settings…" : "")
                                    || backend.successMessage)
                                color: backend.hasRevisionConflict || backend.warningMessage !== ""
                                    || root.validationMessage !== "" || backend.errorMessage !== ""
                                    ? Color.urgent : Color.accent
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                wrapMode: Text.WordWrap
                                elide: backend.hasRevisionConflict ? Text.ElideNone : Text.ElideRight
                            }

                            Ui.Button {
                                id: keepDraftButton
                                visible: backend.hasRevisionConflict
                                text: "Keep draft"
                                tooltipText: "Rebase this draft on the external settings"
                                focusable: true
                                bordered: true
                                onClicked: root.keepDraftAfterConflict()
                            }

                            Ui.Button {
                                id: reloadExternalButton
                                visible: backend.hasRevisionConflict
                                text: "Reload external"
                                tooltipText: "Discard this draft and load the external settings"
                                focusable: true
                                bordered: true
                                foreground: Color.urgent
                                accent: Color.urgent
                                onClicked: root.reloadExternalChanges()
                            }
                        }
                    }

                    Item {
                        id: actionFooter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Style.space(42)
                        anchors.rightMargin: Style.space(42)
                        height: Style.space(68)

                        Ui.PanelSeparator {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            foreground: Color.foreground
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.topMargin: Style.spacing.md
                            spacing: Style.spacing.controlGap

                            Ui.Button {
                                text: "Reset"
                                tooltipText: "Discard unsaved changes"
                                focusable: true
                                bordered: true
                                enabled: root.dirty && !backend.busy
                                opacity: enabled ? 1 : 0.45
                                onClicked: root.syncDraft()
                                Accessible.name: "Reset unsaved changes"
                            }

                            Item {
                                width: Math.max(0, parent.width - x - saveButton.width
                                    - advancedButton.width - parent.spacing * 2)
                                height: 1
                            }

                            Ui.Button {
                                id: saveButton
                                text: backend.saving ? "Saving…"
                                    : (mainArea.width < Style.space(760) ? "Save" : "Save changes")
                                iconText: backend.saving ? "󰑮" : "󰆓"
                                iconSpinning: backend.saving && root.motionEnabled
                                tooltipText: "Save changes (Ctrl+S)"
                                focusable: true
                                bordered: true
                                active: root.dirty
                                enabled: root.dirty && !backend.busy && root.draftWithinLimits
                                opacity: enabled ? 1 : 0.5
                                onClicked: root.saveChanges()
                                Accessible.name: text
                                Accessible.description: "Shortcut Ctrl+S"
                            }

                            Ui.Button {
                                id: advancedButton
                                text: mainArea.width < Style.space(760)
                                    ? "Advanced settings" : "Advanced Voxtype settings"
                                iconText: "󰒓"
                                tooltipText: "Close Prism and open the standard Voxtype configuration"
                                focusable: true
                                onClicked: root.requestClose("advanced")
                                Accessible.name: "Open advanced Voxtype settings"
                            }
                        }
                    }
                }
            }

            // Initial loading / fatal snapshot failure.
            Item {
                anchors.fill: parent
                visible: !backend.hasSnapshot

                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Style.space(80), Style.space(460))
                    spacing: Style.space(16)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: backend.loading ? "󰑮" : "󰅚"
                        color: backend.errorMessage ? Color.urgent : Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.displayLarge
                        rotation: 0

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: backend.loading && root.motionEnabled
                        }
                    }

                    Text {
                        width: parent.width
                        text: backend.loading ? "Loading Voxtype Prism settings"
                            : "Settings could not be loaded"
                        color: Color.foreground
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Style.font.family
                        font.pixelSize: Style.font.heading
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: backend.loading ? "Reading a safe snapshot from the local helper…"
                            : backend.errorMessage
                        color: backend.errorMessage ? Color.urgent : Qt.darker(Color.foreground, 1.45)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }

                    Ui.Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !backend.loading
                        text: "Retry"
                        iconText: "󰑐"
                        focusable: true
                        bordered: true
                        onClicked: backend.load()
                    }
                }
            }

            // Keyboard shortcuts overlay.
            FocusScope {
                anchors.fill: parent
                visible: root.shortcutsVisible
                z: 40
                focus: visible
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.hideShortcuts()
                        event.accepted = true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Color.menu.scrim
                    MouseArea { anchors.fill: parent; onClicked: root.hideShortcuts() }
                }

                Ui.BorderSurface {
                    width: Math.min(Style.space(520), parent.width - Style.space(60))
                    height: shortcutsColumn.implicitHeight + Style.spacing.panelPadding * 2
                    anchors.centerIn: parent
                    color: Color.popups.background
                    borderSpec: Border.localOrSurfaceSpec("popups", "border",
                        Color.popups.border, Color.popups.border, Style.normalBorderWidth)
                    radius: Style.cornerRadius
                    Accessible.role: Accessible.Dialog
                    Accessible.name: "Keyboard shortcuts"

                    MouseArea { anchors.fill: parent }

                    Column {
                        id: shortcutsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.spacing.panelPadding
                        spacing: Style.space(14)

                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - closeShortcutsButton.width
                                text: "Keyboard shortcuts"
                                color: Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.heading
                                font.bold: true
                            }
                            Ui.PanelActionButton {
                                id: closeShortcutsButton
                                iconText: "󰅖"
                                tooltipText: "Close shortcuts"
                                focusable: true
                                onClicked: root.hideShortcuts()
                            }
                        }

                        Repeater {
                            model: [
                                { keys: "Alt+1 … Alt+4", action: "Switch workbench tabs" },
                                { keys: "Ctrl+Enter", action: "Test current refinement draft" },
                                { keys: "Ctrl+S", action: "Save all changes" },
                                { keys: "F1", action: "Show or hide this guide" },
                                { keys: "Esc", action: "Close dialogs or the workbench" }
                            ]

                            Row {
                                required property var modelData
                                width: shortcutsColumn.width
                                spacing: Style.spacing.controlGap
                                Text {
                                    width: Style.space(150)
                                    text: String(parent.modelData.keys)
                                    color: Color.accent
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }
                                Text {
                                    width: parent.width - x
                                    text: String(parent.modelData.action)
                                    color: Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                }
                            }
                        }
                    }
                }
            }

            // Dirty-close guard shared by window dismissal and Advanced.
            FocusScope {
                anchors.fill: parent
                visible: root.discardDialogVisible
                z: 50
                focus: visible
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.closeDiscardDialog()
                        event.accepted = true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Color.menu.scrim
                    MouseArea { anchors.fill: parent }
                }

                Ui.BorderSurface {
                    width: Math.min(Style.space(500), parent.width - Style.space(60))
                    height: discardColumn.implicitHeight + Style.spacing.panelPadding * 2
                    anchors.centerIn: parent
                    color: Color.popups.background
                    borderSpec: Border.localOrSurfaceSpec("popups", "border",
                        Color.popups.border, Color.popups.border, Style.normalBorderWidth)
                    radius: Style.cornerRadius
                    Accessible.role: Accessible.Dialog
                    Accessible.name: "Unsaved changes"

                    Column {
                        id: discardColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.spacing.panelPadding
                        spacing: Style.space(14)

                        Text {
                            text: "Discard unsaved changes?"
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.heading
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            text: root.pendingCloseAction === "advanced"
                                ? "Advanced Voxtype settings opens in a separate app. Your Prism edits must be saved first or discarded."
                                : "Your prompt, dictionary, provider, and indicator edits have not been saved."
                            color: Qt.darker(Color.foreground, 1.4)
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: Style.spacing.controlGap

                            Ui.Button {
                                id: keepEditingButton
                                text: "Keep editing"
                                focusable: true
                                bordered: true
                                onClicked: root.closeDiscardDialog()
                            }
                            Ui.Button {
                                text: root.pendingCloseAction === "advanced"
                                    ? "Discard and open" : "Discard and close"
                                foreground: Color.urgent
                                accent: Color.urgent
                                focusable: true
                                bordered: true
                                onClicked: {
                                    root.syncDraft()
                                    root.finishClose(root.pendingCloseAction)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
