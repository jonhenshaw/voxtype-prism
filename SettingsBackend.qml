import QtQuick
import Quickshell.Io

// Narrow process boundary for the settings workbench. The helper owns all
// filesystem, credential, and Voxtype lifecycle work; this object only sends
// bounded JSON over stdin and turns the helper's response into presentation
// state.
QtObject {
    id: root

    readonly property int protocolVersion: 1
    readonly property int maxResponseCharacters: 1024 * 1024
    readonly property string helperPath: localPath(Qt.resolvedUrl("scripts/voxtype-prism-settings"))

    property bool loading: false
    property bool saving: false
    property bool testing: false
    readonly property bool busy: loading || saving || testing

    property bool hasSnapshot: false
    // Revisions are opaque helper-issued compare-and-swap tokens. Never parse,
    // shorten, or regenerate them in QML.
    property string revision: ""
    property var settings: ({})
    property var catalog: ({ providers: [], indicator: {} })

    property string errorMessage: ""
    property string errorCode: ""
    property string successMessage: ""
    // A committed save can still fail its Voxtype restart/readback. Keep that
    // distinct from a rejected save: the fresh helper snapshot is authoritative
    // and the warning must remain visible until a later successful save.
    property string warningMessage: ""
    // A compare-and-swap conflict is evidence, not permission to replace the
    // user's draft. The panel explicitly chooses whether to rebase or reload.
    property var revisionConflictSnapshot: null
    readonly property bool hasRevisionConflict: revisionConflictSnapshot !== null
    property string testOutput: ""
    property string testProvider: ""
    property string testModel: ""
    property int testElapsedMs: 0

    signal snapshotLoaded()
    signal saveSucceeded()
    signal testSucceeded()
    signal operationFailed(string operation, string message)

    function localPath(url) {
        let value = String(url || "")
        if (value.indexOf("file://") === 0) value = value.slice(7)
        try {
            return decodeURIComponent(value)
        } catch (error) {
            return value
        }
    }

    function clearFeedback() {
        errorMessage = ""
        errorCode = ""
        successMessage = ""
    }

    function utf8ByteLength(value) {
        const text = String(value || "")
        let bytes = 0
        for (let i = 0; i < text.length; ++i) {
            const code = text.charCodeAt(i)
            if (code <= 0x7f) bytes += 1
            else if (code <= 0x7ff) bytes += 2
            else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                    && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
                bytes += 4
                ++i
            } else bytes += 3
        }
        return bytes
    }

    function validateRefineFields(operation, refine) {
        if (!refine || typeof refine !== "object") return true
        if (refine.model !== undefined && utf8ByteLength(refine.model) > 512) {
            setLocalError(operation, "Model override must be 512 bytes or fewer.")
            return false
        }
        if (refine.prompt !== undefined && utf8ByteLength(refine.prompt) > 32768) {
            setLocalError(operation, "Prompt must be 32,768 bytes or fewer.")
            return false
        }
        if (refine.dictionary !== undefined && utf8ByteLength(refine.dictionary) > 32768) {
            setLocalError(operation, "Dictionary must be 32,768 bytes or fewer.")
            return false
        }
        return true
    }

    function finiteNumber(value, fallback) {
        const number = Number(value)
        return isFinite(number) ? number : fallback
    }

    function buildPatch(draft) {
        if (!draft || typeof draft !== "object") return ({})
        const savedRefine = settings && settings.refine ? settings.refine : ({})
        const savedIndicator = settings && settings.indicator ? settings.indicator : ({})
        const nextRefine = draft.refine || ({})
        const nextIndicator = draft.indicator || ({})
        const savedOverride = savedRefine.modelOverride
            ? String(savedRefine.model || "") : ""
        const refine = ({})
        const indicator = ({})

        if (Boolean(nextRefine.enabled) !== Boolean(savedRefine.enabled))
            refine.enabled = Boolean(nextRefine.enabled)
        if (String(nextRefine.provider || "") !== String(savedRefine.provider || ""))
            refine.provider = String(nextRefine.provider || "")
        if (String(nextRefine.model || "") !== savedOverride)
            refine.model = String(nextRefine.model || "")
        if (String(nextRefine.prompt || "") !== String(savedRefine.prompt || ""))
            refine.prompt = String(nextRefine.prompt || "")
        if (String(nextRefine.dictionary || "") !== String(savedRefine.dictionary || ""))
            refine.dictionary = String(nextRefine.dictionary || "")
        if (Boolean(nextRefine.screenContext) !== Boolean(savedRefine.screenContext))
            refine.screenContext = Boolean(nextRefine.screenContext)


        if (String(nextIndicator.preset || "signal")
                !== String(savedIndicator.preset || "signal"))
            indicator.preset = String(nextIndicator.preset || "signal")
        if (String(nextIndicator.position || "bottom-center")
                !== String(savedIndicator.position || "bottom-center"))
            indicator.position = String(nextIndicator.position || "bottom-center")
        if (Math.abs(finiteNumber(nextIndicator.scale, 1.0)
                - finiteNumber(savedIndicator.scale, 1.0)) > 0.0001)
            indicator.scale = finiteNumber(nextIndicator.scale, 1.0)
        if (Boolean(nextIndicator.motion) !== (savedIndicator.motion === undefined
                ? true : Boolean(savedIndicator.motion)))
            indicator.motion = Boolean(nextIndicator.motion)
        if (Math.abs(finiteNumber(nextIndicator.glow, 0.6)
                - finiteNumber(savedIndicator.glow, 0.6)) > 0.0001)
            indicator.glow = finiteNumber(nextIndicator.glow, 0.6)

        const patch = ({})
        if (Object.keys(refine).length > 0) patch.refine = refine
        if (Object.keys(indicator).length > 0) patch.indicator = indicator
        return patch
    }

    function rebaseConflictDraft(draft) {
        if (!hasRevisionConflict) return null
        const patch = buildPatch(draft)
        if (!adoptRevisionConflictSnapshot()) return null
        return patch
    }

    function setLocalError(operation, message) {
        clearFeedback()
        errorCode = "invalid-input"
        errorMessage = String(message || "The request is invalid.")
        operationFailed(operation, errorMessage)
    }

    function normalizeError(response, stderrText, fallback) {
        let message = ""
        let code = ""
        if (response && response.error !== undefined) {
            if (typeof response.error === "string") {
                message = response.error
            } else if (response.error && typeof response.error === "object") {
                message = String(response.error.message || response.error.detail || "")
                code = String(response.error.code || "")
            }
        }
        if (!message && response && response.message !== undefined)
            message = String(response.message)
        if (!message && stderrText) message = String(stderrText).trim()
        if (!message) message = fallback
        return { code: code, message: message }
    }

    function parseResponse(operation, output, stderrText, exitCode) {
        const raw = String(output || "").trim()
        if (!raw) {
            const missing = normalizeError(null, stderrText,
                operation + " did not return a response (exit " + exitCode + ").")
            errorCode = missing.code
            errorMessage = missing.message
            operationFailed(operation, missing.message)
            return null
        }
        if (raw.length > maxResponseCharacters) {
            errorCode = "response-too-large"
            errorMessage = operation + " returned more data than the workbench accepts."
            operationFailed(operation, errorMessage)
            return null
        }

        let response = null
        try {
            response = JSON.parse(raw)
        } catch (error) {
            errorCode = "invalid-response"
            errorMessage = operation + " returned malformed JSON."
            operationFailed(operation, errorMessage)
            return null
        }
        if (!response || typeof response !== "object" || Array.isArray(response)) {
            errorCode = "invalid-response"
            errorMessage = operation + " returned an invalid response object."
            operationFailed(operation, errorMessage)
            return null
        }
        if (response.ok !== true || exitCode !== 0) {
            const failure = normalizeError(response, stderrText,
                operation + " failed (exit " + exitCode + ").")
            errorCode = failure.code
            errorMessage = failure.message

            const errorDetails = response.error && typeof response.error === "object"
                && response.error.details && typeof response.error.details === "object"
                ? response.error.details : ({})
            const suppliedSnapshot = response.snapshot && typeof response.snapshot === "object"
                ? response.snapshot : null

            if (failure.code === "revision_conflict" && suppliedSnapshot)
                revisionConflictSnapshot = suppliedSnapshot

            if (operation === "Save" && errorDetails.committed === true && suppliedSnapshot
                    && applySnapshot(suppliedSnapshot)) {
                revisionConflictSnapshot = null
                warningMessage = failure.message
                errorMessage = ""
                // Resync the panel to the settings that really committed while
                // retaining the restart failure as a persistent warning.
                snapshotLoaded()
            }
            operationFailed(operation, failure.message)
            return null
        }
        return response
    }

    function applySnapshot(nextSnapshot) {
        if (!nextSnapshot || typeof nextSnapshot !== "object") return false
        const nextSettings = nextSnapshot.settings
        if (!nextSettings || typeof nextSettings !== "object") return false
        const nextRevision = String(nextSnapshot.revision || "")
        if (!nextRevision) return false

        revision = nextRevision
        settings = nextSettings
        if (nextSnapshot.catalog && typeof nextSnapshot.catalog === "object")
            catalog = nextSnapshot.catalog
        hasSnapshot = true
        return true
    }

    function load() {
        if (busy) return
        clearFeedback()
        loading = true
        snapshotProcess.outputText = ""
        snapshotProcess.errorText = ""
        snapshotProcess.outputOverflow = false
        snapshotProcess.command = [helperPath, "snapshot"]
        snapshotProcess.running = true
    }

    function save(patch) {
        if (busy || !hasSnapshot) return
        if (!patch || typeof patch !== "object" || Array.isArray(patch)) {
            setLocalError("Save", "There are no valid settings to save.")
            return
        }
        if (!validateRefineFields("Save", patch.refine)) return
        clearFeedback()
        saving = true
        applyProcess.pendingInput = JSON.stringify({
            protocol: protocolVersion,
            expectedRevision: revision,
            patch: patch
        }) + "\n"
        applyProcess.outputText = ""
        applyProcess.errorText = ""
        applyProcess.outputOverflow = false
        applyProcess.stdinEnabled = true
        applyProcess.command = [helperPath, "apply"]
        applyProcess.running = true
    }

    function testRefinement(sample, candidate) {
        if (busy || !hasSnapshot) return
        const originalText = String(sample || "")
        const text = originalText.trim()
        if (!text) {
            setLocalError("Test refinement", "Enter some raw dictated text first.")
            return
        }
        if (utf8ByteLength(originalText) > 4096) {
            setLocalError("Test refinement", "Test sample must be 4,096 bytes or fewer.")
            return
        }
        if (!validateRefineFields("Test refinement", candidate || {})) return
        clearFeedback()
        testOutput = ""
        testProvider = ""
        testModel = ""
        testElapsedMs = 0
        testing = true
        testProcess.pendingInput = JSON.stringify({
            protocol: protocolVersion,
            expectedRevision: revision,
            sample: text,
            candidate: candidate || {}
        }) + "\n"
        testProcess.outputText = ""
        testProcess.errorText = ""
        testProcess.outputOverflow = false
        testProcess.stdinEnabled = true
        testProcess.command = [helperPath, "test-refine"]
        testProcess.running = true
    }

    function adoptRevisionConflictSnapshot() {
        if (!hasRevisionConflict) return false
        const next = revisionConflictSnapshot
        if (!applySnapshot(next)) {
            setLocalError("Reload", "The external settings snapshot is incomplete.")
            return false
        }
        revisionConflictSnapshot = null
        errorMessage = ""
        errorCode = ""
        successMessage = ""
        return true
    }

    function appendBounded(process, field, chunk) {
        if (process.outputOverflow) return
        const current = String(process[field] || "")
        const addition = String(chunk || "")
        if (current.length + addition.length + 1 > maxResponseCharacters) {
            process.outputOverflow = true
            return
        }
        process[field] = current + addition + "\n"
    }

    property Process snapshotProcess: Process {
        id: snapshotProcess
        property string outputText: ""
        property string errorText: ""
        property bool outputOverflow: false

        stdout: SplitParser {
            onRead: function(data) { root.appendBounded(snapshotProcess, "outputText", data) }
        }
        stderr: SplitParser {
            onRead: function(data) { root.appendBounded(snapshotProcess, "errorText", data) }
        }
        onExited: function(exitCode) {
            root.loading = false
            root.clearFeedback()
            if (snapshotProcess.outputOverflow) {
                root.errorCode = "response-too-large"
                root.errorMessage = "Snapshot returned more data than the workbench accepts."
                root.operationFailed("Snapshot", root.errorMessage)
                return
            }
            const response = root.parseResponse(
                "Snapshot", snapshotProcess.outputText, snapshotProcess.errorText, exitCode)
            if (!response) return
            const candidate = response.snapshot && typeof response.snapshot === "object"
                ? response.snapshot : response
            if (!root.applySnapshot(candidate)) {
                root.errorCode = "invalid-snapshot"
                root.errorMessage = "The settings helper returned an incomplete snapshot."
                root.operationFailed("Snapshot", root.errorMessage)
                return
            }
            root.revisionConflictSnapshot = null
            root.snapshotLoaded()
        }
    }

    property Process applyProcess: Process {
        id: applyProcess
        property string pendingInput: ""
        property string outputText: ""
        property string errorText: ""
        property bool outputOverflow: false

        stdinEnabled: false
        stdout: SplitParser {
            onRead: function(data) { root.appendBounded(applyProcess, "outputText", data) }
        }
        stderr: SplitParser {
            onRead: function(data) { root.appendBounded(applyProcess, "errorText", data) }
        }
        onStarted: {
            applyProcess.write(applyProcess.pendingInput)
            applyProcess.pendingInput = ""
            applyProcess.stdinEnabled = false
        }
        onExited: function(exitCode) {
            root.saving = false
            root.clearFeedback()
            if (applyProcess.outputOverflow) {
                root.errorCode = "response-too-large"
                root.errorMessage = "Save returned more data than the workbench accepts."
                root.operationFailed("Save", root.errorMessage)
                return
            }
            const response = root.parseResponse(
                "Save", applyProcess.outputText, applyProcess.errorText, exitCode)
            if (!response) return
            const nextSnapshot = response.snapshot && typeof response.snapshot === "object"
                ? response.snapshot : response
            if (!root.applySnapshot(nextSnapshot)) {
                root.errorCode = "invalid-snapshot"
                root.errorMessage = "Settings were saved, but the refreshed snapshot was incomplete."
                root.operationFailed("Save", root.errorMessage)
                return
            }

            const restart = response.restart || {}
            if (restart.required && restart.verified)
                root.successMessage = "Saved and Voxtype restarted"
            else if (restart.required)
                root.successMessage = "Saved; restart still required"
            else
                root.successMessage = "Changes saved"
            root.warningMessage = ""
            root.revisionConflictSnapshot = null
            root.saveSucceeded()
        }
    }

    property Process testProcess: Process {
        id: testProcess
        property string pendingInput: ""
        property string outputText: ""
        property string errorText: ""
        property bool outputOverflow: false

        stdinEnabled: false
        stdout: SplitParser {
            onRead: function(data) { root.appendBounded(testProcess, "outputText", data) }
        }
        stderr: SplitParser {
            onRead: function(data) { root.appendBounded(testProcess, "errorText", data) }
        }
        onStarted: {
            testProcess.write(testProcess.pendingInput)
            testProcess.pendingInput = ""
            testProcess.stdinEnabled = false
        }
        onExited: function(exitCode) {
            root.testing = false
            root.clearFeedback()
            if (testProcess.outputOverflow) {
                root.errorCode = "response-too-large"
                root.errorMessage = "Test refinement returned more data than the workbench accepts."
                root.operationFailed("Test refinement", root.errorMessage)
                return
            }
            const response = root.parseResponse(
                "Test refinement", testProcess.outputText, testProcess.errorText, exitCode)
            if (!response) return
            const result = response.result && typeof response.result === "object"
                ? response.result : response
            root.testOutput = String(result.output || "")
            root.testProvider = String(result.provider || "")
            root.testModel = String(result.model || "")
            const elapsed = Number(result.elapsedMs)
            root.testElapsedMs = isFinite(elapsed) && elapsed >= 0 ? Math.round(elapsed) : 0
            if (!root.testOutput) {
                root.errorCode = "empty-output"
                root.errorMessage = "The provider returned an empty refinement."
                root.operationFailed("Test refinement", root.errorMessage)
                return
            }
            root.successMessage = "Refinement completed"
            root.testSucceeded()
        }
    }
}
