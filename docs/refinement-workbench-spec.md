# Refinement Workbench v1.2

## Product position

Voxtype Prism is the Omarchy-native refinement and presentation studio for
Voxtype. It does not duplicate Voxtype's engine, model, language, audio, hotkey,
or output configuration surfaces. Those remain in Voxtype's packaged TUI and
future upstream graphical settings panel.

The selected visual truth is
`docs/images/refinement-workbench-reference.png`.
Production uses live Omarchy theme tokens rather than copying the mock's
specific colors.

## Required experience

1. **Refinement-first native window**
   - Normal keyboard-focusable Omarchy `FloatingWindow`, approximately
     1120 × 760, with an 18% left navigation rail.
   - Refinement, Prompt, Dictionary, and Indicator destinations.
   - Provider, effective model, credential readiness, enable state, raw input,
     refined output, explicit test action, privacy disclosure, reset, save, and
     advanced-settings handoff.
   - Loading, dirty, success, conflict, provider failure, and discard states.

2. **Working refinement controls**
   - Grok, Anthropic, OpenAI Codex, and loopback local providers.
   - Prompt and dictionary edits apply on the next dictation.
   - `test-refine` is the only settings action that may contact a provider and
     can exercise unsaved form values without persisting them.
   - Remote tests disclose that dictated text is sent to the selected provider.
   - The UI never receives tokens, account IDs, or authorization headers.

3. **Curated indicator controls**
   - Signal, Halo, and Bar Pulse are real runtime renderers, not placeholder
     names or mock-only thumbnails.
   - The panel preview and runtime surface reuse the same pure visual module.
   - Top/bottom placement, scale, motion, and glow are persisted through a
     versioned, allowlisted Prism-owned settings document.
   - Runtime surfaces remain click-through, reserve no screen space, and never
     request keyboard focus.

4. **Quick Shell replacement with escape hatch**
   - The user-scoped `voxtype-configure.desktop` entry shadows the packaged
     desktop ID and opens Prism from Quick Shell.
   - A foreign user override is never overwritten.
   - If Prism cannot open, the launcher falls back to
     `/usr/bin/voxtype-configure-launcher`.
   - **Advanced Voxtype settings** closes Prism before launching the packaged
     TUI.

5. **Safe lifecycle**
   - Existing standard-install activation remains explicit and reversible.
   - QML stays presentation-only. Raw config, filesystem mutation, service
     restart, credential access, and network calls stay behind Python helpers.
   - Reads are bounded regular-file reads that do not follow symlinks.
   - Writes are private and atomic, require an opaque composite revision, and
     never overwrite a concurrent replacement.
   - Multi-file local failures reverse completed writes when readback still
     proves ownership; incomplete recovery is reported explicitly.
   - Unknown post-process commands are refused rather than overwritten.
   - Hook ownership changes restart, verify, and read back `voxtype.service`.

## Non-goals

- Rebuilding Voxtype's general configuration UI.
- Managing model downloads, transcription engines, languages, GPU modes,
  meetings, hotkeys, or analytics.
- Loading arbitrary third-party indicator QML or downloading styles.
- Automatically testing providers during load or save.
- Relying on QML destruction callbacks for uninstall restoration.

## Acceptance gates

- Repository unit tests, plugin validation, QML load smoke, Python compilation,
  desktop-entry validation, and `git diff --check` pass.
- The installed panel opens through both direct shell summon and the Quick Shell
  desktop entry, while fallback still opens the stock TUI when Prism is absent.
- Provider selection, raw/refined test, prompt/dictionary editing, all three
  indicator previews, save/reset, keyboard navigation, and close/discard flows
  are exercised.
- Live Signal remains click-through and Voxtype dictation still completes.
- A same-state screenshot is compared with the selected mock; all P0/P1/P2
  design differences are fixed before handoff.
