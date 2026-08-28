pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
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
    property int preferredWindowWidth: 1120
    property int preferredWindowHeight: 760

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

    function opaqueColor(value) {
        return Qt.rgba(value.r, value.g, value.b, 1)
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

    FloatingWindow {
        id: window
        visible: false
        title: "Voxtype Prism"
        color: root.opaqueColor(Color.background)
        implicitWidth: root.preferredWindowWidth
        implicitHeight: root.preferredWindowHeight
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

            Rectangle {
                anchors.fill: parent
                color: root.opaqueColor(Color.background)
                z: -10
            }

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
                opacity: 1

                Rectangle {
                    id: navigationRail
                    width: Math.max(Style.space(184), Math.round(window.width * 0.18))
                    height: parent.height
                    color: root.opaqueColor(Color.popups.background)

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

                    Rectangle {
                        anchors.fill: parent
                        color: root.opaqueColor(Color.background)
                        z: -10
                    }

                    StackLayout {
                        id: pageStack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: statusBanner.top
                        anchors.leftMargin: Style.space(40)
                        anchors.rightMargin: Style.space(40)
                        anchors.topMargin: Style.space(26)
                        anchors.bottomMargin: Style.space(18)
                        currentIndex: root.selectedTab

                        // -------------------------------------------------- Refinement
                        Flickable {
                            id: refinementPage
                            clip: true
                            contentWidth: width
                            contentHeight: refinementContent.height
                            boundsBehavior: Flickable.StopAtBounds
                            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: refinementContent
                                width: refinementPage.width
                                height: Math.max(refinementPage.height, implicitHeight)
                                spacing: Style.space(14)

                                PrismPageHeader {
                                    Layout.fillWidth: true
                                    title: "Refinement"
                                    description: "Choose how Prism cleans dictation, then test the current draft before saving it."
                                }

                                PrismSection {
                                    Layout.fillWidth: true
                                    contentPadding: Style.space(14)

                                    Ui.Toggle {
                                        Layout.fillWidth: true
                                        checked: root.refineEnabled
                                        label: "Refine after dictation"
                                        description: root.refineEnabled
                                            ? "Prism cleans every completed transcript with the provider below."
                                            : "Dictation is left unchanged until this setting is turned on."
                                        Accessible.name: "Refine after dictation"
                                        Accessible.description: description
                                        onClicked: root.refineEnabled = !root.refineEnabled
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: Style.space(18)
                                        rowSpacing: Style.spacing.labelGap

                                        PrismFormField {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            label: "Provider"
                                            meta: root.providerReadinessText
                                            hasError: !root.providerReady
                                            helper: "Credentials stay in OhMyPi"

                                            Ui.Dropdown {
                                                id: providerPicker
                                                Layout.fillWidth: true
                                                showLabel: false
                                                value: root.refineProvider
                                                options: root.providerOptions
                                                Accessible.name: "Refinement provider"
                                                onChanged: function(value) { root.chooseProvider(value) }
                                            }
                                        }

                                        PrismFormField {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            label: "Model override"
                                            meta: root.modelBytes >= 448
                                                ? root.modelBytes + " / 512 bytes" : ""
                                            hasError: root.modelTooLarge
                                            helper: "Effective model · "
                                                + (root.effectiveModel || "Unavailable")

                                            Ui.TextField {
                                                id: modelField
                                                Layout.fillWidth: true
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
                                        }
                                    }
                                }

                                PrismSection {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: Style.space(240)
                                    contentPadding: Style.space(14)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.spacing.controlGap

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.spacing.xs

                                            Text {
                                                text: "Test current draft"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.subtitle
                                                font.bold: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: "Uses the unsaved provider, model, prompt, and dictionary. Testing does not save them."
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        Ui.Button {
                                            id: testButton
                                            text: backend.testing ? "Testing…"
                                                : (root.testOutputStale ? "Retest draft" : "Test draft")
                                            iconText: backend.testing ? "󰑮" : "󰑐"
                                            iconSpinning: backend.testing && root.motionEnabled
                                            tooltipText: "Test current draft (Ctrl+Enter)"
                                            focusable: true
                                            bordered: true
                                            selected: true
                                            foreground: Color.accent
                                            accent: Color.accent
                                            enabled: !backend.busy && root.rawSample.trim() !== ""
                                                && root.testWithinLimits
                                            opacity: enabled ? 1 : 0.5
                                            onClicked: root.runTest()
                                            Accessible.name: text
                                            Accessible.description: "Shortcut Ctrl+Enter"
                                        }
                                    }

                                    RowLayout {
                                        id: comparisonRow
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: Style.space(18)

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: 1
                                            spacing: Style.spacing.md

                                            Text {
                                                text: "Raw dictated text"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                            }

                                            PrismTextArea {
                                                id: rawEditor
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                Layout.minimumHeight: Style.space(100)
                                                text: root.rawSample
                                                accessibleName: "Raw dictated text sample"
                                                accessibleDescription: "Text sent when testing refinement"
                                                maximumLength: 8192
                                                maximumBytes: 4096
                                                hasError: root.sampleTooLarge
                                                onEdited: root.rawSample = text
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: 1
                                            spacing: Style.spacing.md

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    text: "Refined output"
                                                    color: Color.foreground
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.bodySmall
                                                    font.bold: true
                                                }
                                                Item { Layout.fillWidth: true }
                                                Text {
                                                    id: outputStatus
                                                    Layout.maximumWidth: Style.space(260)
                                                    text: backend.testing ? "Testing refinement…"
                                                        : (backend.errorMessage ? backend.errorMessage
                                                        : (root.testOutputStale ? "Result is stale · retest"
                                                        : (backend.testOutput ? "Completed"
                                                        + (backend.testElapsedMs > 0 ? " · " + backend.testElapsedMs + " ms" : "") : "")))
                                                    visible: text !== ""
                                                    color: backend.errorMessage || root.testOutputStale
                                                        ? Color.urgent : Color.accent
                                                    font.family: Style.font.family
                                                    font.pixelSize: Style.font.caption
                                                    elide: Text.ElideRight
                                                    Accessible.name: text
                                                }
                                            }

                                            PrismTextArea {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                Layout.minimumHeight: Style.space(100)
                                                text: backend.testOutput
                                                readOnly: true
                                                hasError: backend.errorMessage !== "" && !backend.testing
                                                opacity: root.testOutputStale ? 0.72 : 1
                                                placeholderText: backend.testing
                                                    ? "Refining…" : "Run a test to preview the result"
                                                accessibleName: "Refined output"
                                                accessibleDescription: "Latest LLM refinement result"
                                            }
                                        }
                                    }

                                    RowLayout {
                                        id: privacyRow
                                        Layout.fillWidth: true
                                        spacing: Style.spacing.controlGap

                                        Text {
                                            text: "󰌾"
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.icon
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Test text is sent to the selected provider. Credentials remain in OhMyPi and are never shown here."
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Prompt
                        Flickable {
                            id: promptPage
                            clip: true
                            contentWidth: width
                            contentHeight: promptContent.height
                            boundsBehavior: Flickable.StopAtBounds
                            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: promptContent
                                width: promptPage.width
                                height: Math.max(promptPage.height, implicitHeight)
                                spacing: Style.space(14)

                                PrismPageHeader {
                                    Layout.fillWidth: true
                                    title: "Custom prompt"
                                    description: "Tell the model how to clean your dictation. Dictionary entries are appended automatically."
                                }

                                PrismSection {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    contentPadding: Style.space(14)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.spacing.controlGap

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.spacing.xs

                                            Text {
                                                text: "System prompt"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.subtitle
                                                font.bold: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: "Keep corrections narrow: preserve meaning and tone without adding facts, commentary, or Markdown."
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                    Ui.Button {
                                        id: testPromptButton
                                        text: "Try in Refinement"
                                        focusable: true
                                        bordered: true
                                        onClicked: {
                                            root.selectTab(0)
                                            Qt.callLater(function() { rawEditor.control.forceActiveFocus() })
                                        }
                                    }
                                }

                                    PrismTextArea {
                                        id: promptEditor
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumHeight: Style.space(260)
                                        text: root.refinePrompt
                                        placeholderText: "Describe how the model should refine speech-to-text…"
                                        accessibleName: "Custom refinement system prompt"
                                        accessibleDescription: "Saved to your Voxtype refine prompt file"
                                        maximumLength: 32768
                                        maximumBytes: 32768
                                        showCount: root.promptBytes >= 28672
                                        hasError: root.promptTooLarge
                                        onEdited: root.refinePrompt = text
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Local file · ~/.config/voxtype/refine-prompt.md"
                                        color: Qt.darker(Color.foreground, 1.25)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Dictionary
                        Flickable {
                            id: dictionaryPage
                            clip: true
                            contentWidth: width
                            contentHeight: dictionaryContent.height
                            boundsBehavior: Flickable.StopAtBounds
                            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: dictionaryContent
                                width: dictionaryPage.width
                                height: Math.max(dictionaryPage.height, implicitHeight)
                                spacing: Style.space(14)

                                PrismPageHeader {
                                    Layout.fillWidth: true
                                    title: "Custom dictionary"
                                    description: "Teach refinement names, technical terms, and preferred spellings."
                                }

                                RowLayout {
                                    id: dictionaryLayout
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: Style.space(20)

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumWidth: Style.space(320)
                                        spacing: Style.spacing.md

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "Dictionary entries"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.subtitle
                                                font.bold: true
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                visible: dictionaryFormatGuide.visible
                                                text: "One entry per line"
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: !dictionaryFormatGuide.visible
                                            text: "One entry per line · Hyprland · quick shell → Quickshell · # comments are ignored"
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            wrapMode: Text.WordWrap
                                        }

                                        PrismTextArea {
                                            id: dictionaryEditor
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: Style.space(280)
                                            text: root.refineDictionary
                                            placeholderText: "Hyprland\nQuickshell\nvox type → Voxtype"
                                            accessibleName: "Custom refinement dictionary"
                                            accessibleDescription: "One preferred spelling or mapping per line"
                                            maximumLength: 32768
                                            maximumBytes: 32768
                                            showCount: root.dictionaryBytes >= 28672
                                            hasError: root.dictionaryTooLarge
                                            onEdited: root.refineDictionary = text
                                        }

                                        Text {
                                            id: dictionaryLocation
                                            Layout.fillWidth: true
                                            text: "Local file · ~/.config/voxtype/refine-dictionary.md"
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    PrismSection {
                                        id: dictionaryFormatGuide
                                        visible: dictionaryPage.width >= Style.space(720)
                                        Layout.alignment: Qt.AlignTop
                                        Layout.preferredWidth: Style.space(270)
                                        Layout.minimumWidth: Style.space(230)
                                        Layout.maximumWidth: Style.space(300)
                                        contentPadding: Style.space(16)

                                        Text {
                                            text: "Format guide"
                                            color: Color.foreground
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.subtitle
                                            font.bold: true
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Use a preferred spelling by itself, or map what Prism hears to what it should write."
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                            wrapMode: Text.WordWrap
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.spacing.sm

                                            Text {
                                                text: "PREFERRED SPELLING"
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }

                                            Text {
                                                text: "Hyprland"
                                                color: Color.accent
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.body
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.spacing.sm

                                            Text {
                                                text: "SPOKEN  →  WRITTEN"
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }

                                            Text {
                                                text: "quick shell  →  Quickshell"
                                                color: Color.accent
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.body
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Blank lines and # comments are ignored."
                                            color: Qt.darker(Color.foreground, 1.25)
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        // -------------------------------------------------- Indicator
                        Flickable {
                            id: indicatorPage
                            clip: true
                            contentWidth: width
                            contentHeight: indicatorContent.height
                            boundsBehavior: Flickable.StopAtBounds
                            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: indicatorContent
                                width: indicatorPage.width
                                height: Math.max(indicatorPage.height, implicitHeight)
                                spacing: Style.space(14)

                                PrismPageHeader {
                                    Layout.fillWidth: true
                                    title: "Indicator"
                                    description: "Choose how Prism communicates listening, streaming, processing, and completion."
                                }

                                PrismSection {
                                    id: indicatorPreviewCard
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(Style.space(145),
                                        Math.min(Style.space(180), Math.round(indicatorPage.height * 0.32)))
                                    Layout.minimumHeight: Style.space(145)
                                    contentPadding: Style.space(14)
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: root.titleCase(root.indicatorPreset)
                                        + " indicator preview in " + root.phaseLabel(root.previewPhase) + " state"

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.spacing.controlGap

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.spacing.xs

                                            Text {
                                                text: "Live preview"
                                                color: Color.foreground
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.subtitle
                                                font.bold: true
                                            }

                                            Text {
                                                text: root.titleCase(root.indicatorPreset) + " · "
                                                    + root.titleCase(root.indicatorPosition)
                                                color: Qt.darker(Color.foreground, 1.25)
                                                font.family: Style.font.family
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Text {
                                            text: "Preview state"
                                            color: Color.foreground
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                            font.bold: true
                                        }

                                        Ui.Dropdown {
                                            Layout.preferredWidth: Style.space(190)
                                            showLabel: false
                                            value: root.previewPhase
                                            options: [
                                                { value: "recording", label: "Listening" },
                                                { value: "streaming", label: "Streaming" },
                                                { value: "transcribing", label: "Processing" },
                                                { value: "ready", label: "Done" }
                                            ]
                                            Accessible.name: "Indicator preview state"
                                            onChanged: function(value) { root.previewPhase = value }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

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
                                }

                                PrismSection {
                                    Layout.fillWidth: true
                                    contentPadding: Style.space(14)

                                    Text {
                                        text: "Indicator settings"
                                        color: Color.foreground
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.subtitle
                                        font.bold: true
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: Style.space(24)
                                        rowSpacing: Style.space(14)

                                        PrismFormField {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            label: "Style"
                                            helper: "Changes the indicator shape"

                                            Ui.Dropdown {
                                                Layout.fillWidth: true
                                                showLabel: false
                                                value: root.indicatorPreset
                                                options: root.presetOptions
                                                Accessible.name: "Indicator preset"
                                                onChanged: function(value) { root.indicatorPreset = value }
                                            }
                                        }

                                        PrismFormField {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            label: "Screen position"
                                            helper: "Placement on the focused monitor"

                                            Ui.Dropdown {
                                                Layout.fillWidth: true
                                                showLabel: false
                                                value: root.indicatorPosition
                                                options: root.positionOptions
                                                Accessible.name: "Indicator screen position"
                                                onChanged: function(value) { root.indicatorPosition = value }
                                            }
                                        }

                                        SettingsSlider {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
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
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
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
                                            Layout.fillWidth: true
                                            Layout.columnSpan: 2
                                            label: "Animate indicator"
                                            description: root.indicatorMotion
                                                ? "Waveforms and state changes move in the preview and live indicator."
                                                : "Preview and live indicator remain still."
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
                        anchors.leftMargin: Style.space(40)
                        anchors.rightMargin: Style.space(40)
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
                        anchors.leftMargin: Style.space(40)
                        anchors.rightMargin: Style.space(40)
                        height: Style.space(68)

                        Ui.PanelSeparator {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            foreground: Color.foreground
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.topMargin: Style.spacing.md
                            spacing: Style.spacing.controlGap

                            Text {
                                Layout.fillWidth: true
                                visible: mainArea.width >= Style.space(640)
                                text: root.dirty ? "Unsaved changes" : "All changes saved"
                                color: root.dirty ? Color.accent : Qt.darker(Color.foreground, 1.25)
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }

                            Ui.Button {
                                id: advancedButton
                                text: mainArea.width < Style.space(600) ? ""
                                    : (mainArea.width < Style.space(760)
                                    ? "Advanced settings" : "Advanced Voxtype settings")
                                iconText: "󰒓"
                                tooltipText: "Close Prism and open the standard Voxtype configuration"
                                focusable: true
                                onClicked: root.requestClose("advanced")
                                Accessible.name: "Open advanced Voxtype settings"
                            }

                            Ui.Button {
                                text: mainArea.width < Style.space(720)
                                    ? "Revert" : "Revert changes"
                                tooltipText: "Revert to the last saved settings"
                                focusable: true
                                bordered: true
                                enabled: root.dirty && !backend.busy
                                opacity: enabled ? 1 : 0.45
                                onClicked: root.syncDraft()
                                Accessible.name: "Revert unsaved changes"
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
                                selected: root.dirty
                                foreground: root.dirty ? Color.accent : Color.foreground
                                accent: Color.accent
                                enabled: root.dirty && !backend.busy && root.draftWithinLimits
                                opacity: enabled ? 1 : 0.5
                                onClicked: root.saveChanges()
                                Accessible.name: text
                                Accessible.description: "Shortcut Ctrl+S"
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
                        color: backend.errorMessage ? Color.urgent : Qt.darker(Color.foreground, 1.25)
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
                            PrismOpticalIconButton {
                                id: closeShortcutsButton
                                opticalIconText: "󰅖"
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
                            color: Qt.darker(Color.foreground, 1.25)
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
