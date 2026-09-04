# On-screen context plan review

Date: 2026-08-29

Plan reviewed: [docs/on-screen-context-plan.md](on-screen-context-plan.md)

This is a primary-source review of the proposed `on_screen_spellings` module. It does not implement the feature and does not edit the plan.

Evidence kinds:

- **Published source** — product or protocol source inspected at a named revision.
- **Official documentation** — first-party docs/specs.
- **Local runtime** — this machine (Hyprland 0.56.2, grim 1.5.0-2, tesseract 5.5.3, voxtype 0.7.5).
- **Repo constraint** — named files in this repository.

## Product survey

### VoiceInk (open source, macOS)

VoiceInk is the closest published analogue. At recording start it snapshots clipboard, selected text, and focused-window pixels in parallel, then later injects them into LLM enhancement as *separate tagged fields* from custom vocabulary.

- Capture starts after the recorder enters `.recording`, not at cleanup time. Source: [`VoiceInkEngine.swift`](https://github.com/Beingpax/VoiceInk/blob/68b871e79e2b1ec4c3b4914cccd2e0907d94237a/VoiceInk/Transcription/Engine/VoiceInkEngine.swift#L281-L294).
- Snapshot construction: clipboard, `SelectedTextService.fetchSelectedText()`, `ScreenCaptureService.captureAndExtractText()`. Source: [`RecordingContextSnapshot.swift`](https://github.com/Beingpax/VoiceInk/blob/68b871e79e2b1ec4c3b4914cccd2e0907d94237a/VoiceInk/Services/RecordingContextSnapshot.swift#L34-L53).
- Window capture uses ScreenCaptureKit (`SCScreenshotManager.captureImage`) plus Vision OCR (`VNRecognizeTextRequest`). Longest side is capped at 2800 px; capture times out at 3 s. Accessibility is used only as a focused-window *hint* (title/frame), not as the text tree. Source: [`ScreenCaptureService.swift`](https://github.com/Beingpax/VoiceInk/blob/68b871e79e2b1ec4c3b4914cccd2e0907d94237a/VoiceInk/Services/ScreenCaptureService.swift).
- Enhancement keeps `CUSTOM_VOCABULARY` as spelling authority and `CURRENT_WINDOW_CONTEXT` / clipboard / selection as context-only. Pixels never leave the box; the LLM sees OCR text. Sources: [`AIEnhancementService.swift`](https://github.com/Beingpax/VoiceInk/blob/68b871e79e2b1ec4c3b4914cccd2e0907d94237a/VoiceInk/Services/AIEnhancement/AIEnhancementService.swift#L123-L181), [`AIPrompts.swift`](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Models/AIPrompts.swift).
- Per-mode `useScreenCapture` defaults **false**. Source: [`ModeConfig.swift`](https://github.com/Beingpax/VoiceInk/blob/68b871e79e2b1ec4c3b4914cccd2e0907d94237a/VoiceInk/Modes/ModeConfig.swift#L105-L123).

VoiceInk’s Whisper prompt is a language-greeting string, not screen text. Source: [`WhisperPrompt.swift`](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Transcription/Whisper/WhisperPrompt.swift). Screen context is an enhancement-layer lexicon, which matches Prism’s intended depth.

**Keep from VoiceInk:** separate vocabulary vs window fields; pixels stay local; screen capture default-off. **Do not copy:** dumping full OCR prose into the prompt; recording-start capture that needs a cache file.

### Superwhisper (first-party docs)

Superwhisper’s Super Mode gathers application, selected-text, and clipboard context through **accessibility**, not a documented screenshot/OCR path. Official docs:

- Application context is “text from current input fields or text editor.” Source: [Super Mode](https://superwhisper.com/docs/modes/super.md).
- Capture timing is *not* one snapshot: selected text at recording start; clipboard within 3 s before or during dictation; **application context after transcription, between ASR and AI processing**. Source: [Context Awareness](https://superwhisper.com/docs/common-issues/context.md).
- Switching windows between dictation and processing captures the wrong application context. Same page.
- Custom vocabulary is local and “not sent to cloud providers.” Source: [Sensitive Data](https://superwhisper.com/docs/security/sensitive-data.md).

Prism’s refine-time capture matches Superwhisper’s application-context timing, not VoiceInk’s recording-start snapshot.

### Wispr Flow (first-party docs)

Flow’s Context Awareness is broader and cloud-facing. The help article states Flow reads limited text near the cursor, includes on-screen text **and a screenshot**, sends that payload with each dictation unless Privacy Mode is on, and is **on by default**. Password fields are excluded, with a documented caveat for custom/web fields. Source: [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness). Dictionary remains a separate product surface. Source: [Teach Flow your words](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary).

Prism must not claim Wispr-equivalence. Sending pixels off-box is a rejected design in this repo (`ARCHITECTURE.md`, plan “never send image bytes”).

### Handy (open source)

Handy has **no** screen/window/OCR/selection context on the public transcription or cleanup path. Clipboard code restores pasteboard after output paste. Source: [`clipboard.rs`](https://github.com/cjpais/Handy/blob/c6fa60da2f13a5af660fba17f37af548855119c5/src-tauri/src/clipboard.rs#L54-L74). Custom words become Whisper `initial_prompt` at ASR time, not LLM cleanup input. Source: [`transcription.rs`](https://github.com/cjpais/Handy/blob/c6fa60da2f13a5af660fba17f37af548855119c5/src-tauri/src/managers/transcription.rs) (custom-words / `initial_prompt` path). Post-process is default-off and sends only the transcript. Sources: [`settings.rs`](https://github.com/cjpais/Handy/blob/c6fa60da2f13a5af660fba17f37af548855119c5/src-tauri/src/settings.rs#L610-L612), [`CustomWords.tsx`](https://github.com/cjpais/Handy/blob/main/src/components/settings/CustomWords.tsx).

Handy is a baseline for “cleanup with no environmental context.” Prism’s dictionary already occupies that ASR-adjacent role via `preferred_spellings` at refine time, not Whisper.

### FluidVoice (open source)

FluidVoice snapshots **app name / bundle ID / window title** at recording start via `CGWindowListCopyWindowInfo`, not OCR. Selected text is an explicit Rewrite-mode accessibility capture. Custom dictionary is local post-ASR. Parakeet vocabulary boosting is a persistent JSON store (max 256 terms), not per-utterance screen injection. Sources: [`ActiveAppMonitor.swift`](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ActiveAppMonitor.swift), [`TextSelectionService.swift`](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/TextSelectionService.swift), [`ParakeetVocabularyStore.swift`](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ParakeetVocabularyStore.swift). Fluid Intelligence internals are unpublished.

**Product implication for Prism:** the published Linux-relevant lesson is VoiceInk’s *field split* plus Superwhisper’s *refine-time application context*, not Wispr’s screenshot upload and not Handy’s ASR `initial_prompt`.

## Wayland / Hyprland capture

Local runtime: Hyprland **0.56.2** (`efb5099`), grim **1.5.0-2**, `xdg-desktop-portal-hyprland` **1.4.1**. Dual 4K outputs at scale **1.6**. `hyprctl activewindow -j` currently reports `at`, `size`, `class`, `title`, and `stableId`.

### What grim actually does

grim 1.5 documents `-g` as a region in **layout coordinates** and `-T` as “identifier of a foreign toplevel handle.” Source: local `grim(1)` (2025-08-05), also grim 1.5 help.

- `-g` is an **output crop**. grim captures intersecting outputs (via `ext_output_image_capture_source_manager_v1` + `ext_image_copy_capture_manager_v1`, else `zwlr_screencopy_manager_v1`) and crops locally. Overlap, popups, and translucent CSD leak into the rectangle. Source: [grim `main.c` 1.5.0](https://gitlab.freedesktop.org/emersion/grim/-/blob/0a2c5c9/main.c).
- `-T` resolves `ext_foreign_toplevel_list_v1` then captures that toplevel through `ext_foreign_toplevel_image_capture_source_manager_v1`. The spec says images “show the same content as the toplevel.” Source: [ext-image-capture-source-v1](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/ext-image-capture-source/ext-image-capture-source-v1.xml).
- Hyprland 0.56.2 emits the foreign-toplevel identifier as lowercase hex `m_stableID`, and `activewindow -j` prints that as `stableId`. Hyprland maintainers documented `grim -T $(hyprctl -j activewindow | jq -r .stableId)` when standardized toplevel capture landed. Sources: [Hyprland `ForeignToplevel.cpp` v0.56.2](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/protocols/ForeignToplevel.cpp), [discussion #13332](https://github.com/hyprwm/Hyprland/discussions/13332).

`at`/`size` are `GEOMETRIC_GOAL` logical coordinates. They are valid grim `-g` numbers (do not multiply by 1.6; do not subtract reserved areas). They are **not** isolation. During animation they can disagree with the current frame. Source: [Hyprland `HyprCtl.cpp` v0.56.2](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/debug/HyprCtl.cpp).

### Portals

xdg-desktop-portal **ScreenCast** is a consented PipeWire session (`CreateSession` → `SelectSources` → `Start`), typically with a picker. Source: [ScreenCast spec](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html). XDPH 1.4.1 Screenshot shells out to `grim` or `grim -g "$(slurp)"` and does not implement an active-window target. Source: [XDPH `Screenshot.cpp` v1.4.1](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.4.1/src/portals/Screenshot.cpp). Portal ScreenCast is the wrong one-shot adapter for silent focused-window OCR.

### Permissions and lock

Hyprland’s permission system, when `ecosystem.enforce_permissions` is true, treats grim `screencopy` as **ASK** by default. Config example: `hl.permission({ binary = "/usr/bin/grim", type = "screencopy", mode = "allow" })`. Enforcement is **disabled by default**. Source: [Permissions wiki](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/), [Hyprland `ConfigValues.cpp` v0.56.2](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/values/ConfigValues.cpp). This machine does not override it, so grim currently proceeds without a picker.

`ext-session-lock-v1` is privileged to the lock client; it is not an observer query. Hyprland tracks `isSessionLocked()` internally but v0.56.2 does not publish a `hyprctl` lock field. Checking for class `hyprlock` is only a fail-closed heuristic. Sources: [ext-session-lock-v1](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/ext-session-lock/ext-session-lock-v1.xml), [Hyprland `SessionLockManager.cpp`](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/SessionLockManager.cpp).

**Capture adapter to ship:** `hyprctl activewindow -j` → skip empty/unmapped/lock-class → `grim -T "$stableId"` to a 0600 memfd/temp → OCR. Keep `grim -g` only as a fallback if `-T` is missing, and treat fallback as leaky.

## OCR

This machine already has `tesseract 5.5.3` + `tesseract-data-eng 2:4.1.0-5` (AVX512). Official guidance:

- Tesseract “works best on images which have a DPI of at least 300 dpi, so it may be beneficial to resize.” It does **not** prescribe a 1280 px long edge. Source: [ImproveQuality](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.md).
- Screen-text FAQ: ~20 px x-height at 10pt×300dpi; below 10 px accuracy collapses; LSTM also has an apparent **maximum** x-height around 30 px. Source: [FAQ-Old, “It won't read screen text”](https://tesseract-ocr.github.io/tessdoc/tess3/FAQ-Old.md).
- PSM 6 is “a single uniform block of text.” PSM 11 is “sparse text… no particular order.” Default PSM 3 expects a page. Same ImproveQuality page.
- For codes/receipts, disable `load_system_dawg` / `load_freq_dawg`. Same page.

A local smoke on this repo’s `preview.png` (2142×734): LSTM PSM 11 ~0.82 s native, ~0.59 s after 1280-wide downscale, with **worse** small-UI text after downscale. 1.5 s is realistic for a modest window on this CPU, not a p95 for a dense 4K editor.

| Adapter | Why not v1 |
|---|---|
| RapidOCR / PaddleOCR | Better scene-text lineage; pip/AUR, not `extra`; extra ONNX/model depth before Tesseract is measured failing. Sources: [RapidOCR](https://github.com/RapidAI/RapidOCR), Arch `extra` has tesseract and not rapidocr. |
| Surya | 650M VLM; auto-spawns vLLM or llama-server; 5 pages/s on RTX 5090 is throughput, not cold single-shot. Source: [Surya README](https://github.com/VikParuchuri/surya). |
| llama.cpp VLM | Supports local pixels (Qwen-VL, InternVL via mtmd) but variable latency and no fail-closed 1.5 s contract. Source: [llama.cpp](https://github.com/ggml-org/llama.cpp). |
| Apple Vision / Windows OCR | Not Linux. VoiceInk’s Vision path is the macOS analogue, not a Linux adapter. |

**v1 OCR adapter:** Tesseract LSTM (`--oem 1`), fail-closed. Prefer **native resolution** unless measured x-height is outside ~10–30 px. `--psm 6` is a reasonable start for an editor/terminal block; evaluate PSM 11 on mixed UI later. Do not make 1280 a hard rule.

## AT-SPI2 vs OCR

Linux accessibility text lives in **AT-SPI2**, not in Hyprland. It is D-Bus: `org.a11y.Bus` on the session bus returns the address of a separate accessibility bus. Clients (`libatspi`, `pyatspi`, or raw D-Bus) call `GetText` without being the compositor. Sources: [at-spi2-core bus README](https://gitlab.gnome.org/GNOME/at-spi2-core/-/blob/main/bus/README.md), [Text.xml `GetText`](https://gitlab.gnome.org/GNOME/at-spi2-core/-/blob/main/xml/Text.xml), [architecture](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/architecture.html).

Hyprland 0.56 has no AT-SPI or compositor text tree. GNOME’s next-protocol proposal even says global focus should come from the compositor — which Hyprland does not currently publish. Sources: [Hyprland v0.56.0 notes](https://github.com/hyprwm/Hyprland/releases/tag/v0.56.0), [new-protocol proposal](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/new-protocol.html).

When AT-SPI beats OCR: exact Unicode, caret/selection, and `ATSPI_ROLE_PASSWORD_TEXT` (text “not shown visibly to the user”). Source: [atspi-constants.h](https://gitlab.gnome.org/GNOME/at-spi2-core/-/blob/main/atspi/atspi-constants.h). GTK standard controls implement `GtkAccessible` by default. Source: [GTK 4 accessibility](https://docs.gtk.org/gtk4/section-accessibility.html). VTE exposes terminal text (`GTK_ACCESSIBLE_ROLE_TERMINAL`). Source: [vtegtk.cc](https://gitlab.gnome.org/GNOME/vte/-/blob/main/src/vtegtk.cc). Firefox/Chromium expose document text via ATK, not only chrome. Sources: [Firefox `nsMaiInterfaceText.cpp`](https://hg.mozilla.org/mozilla-central/raw-file/tip/accessible/atk/nsMaiInterfaceText.cpp), [Chromium accessibility overview](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md).

When it fails on this desktop: Ghostty 1.3 Linux `GhosttySurface` implements `gtk.Scrollable` and has **no** Linux AT-SPI text path; macOS `accessibilityValue` is a separate AppKit implementation. Source: [ghostty `surface.zig` v1.3.0](https://github.com/ghostty-org/ghostty/blob/v1.3.0/src/apprt/gtk/class/surface.zig). Kitty/Alacritty have no source-confirmed Linux AT-SPI terminal text. This machine’s focused window is often Ghostty (`org.omarchy.agent` / `initialClass: Ghostty`).

Security: the accessibility bus default policy allows any connected same-user client to talk to any destination (`send_destination="*"`, `own="*"`). Source: [accessibility.conf.in](https://gitlab.gnome.org/GNOME/at-spi2-core/-/blob/main/bus/accessibility.conf.in). Raw AT-SPI can inspect **more** trees than a focused-window screenshot. A focused `GetText` that skips password roles can leak **less** than OCR of the same window. Password role is metadata, not enforcement.

**Keep `AtspiSource` as v1.5** behind the same `collect_on_screen_spellings` interface. Do not make v1 AT-SPI-first: it will return `[]` for Ghostty (this machine’s usual dictation target) while OCR still sees identifiers. v1.5 may try AT-SPI first only for a verified focused Text subtree (VTE, Firefox/Chromium document), skip `PASSWORD_TEXT`, then fall back to OCR. Superwhisper’s analogue is accessibility text; Prism cannot copy that as v1 on Hyprland + Ghostty.

## ASR injection (Voxtype 0.7.5)

This machine runs `engine = "parakeet"` with a Prism `[output.post_process]` hook, `timeout_ms = 30000`.

Facts from Voxtype source (tag inspected at `8d49248`):

- `VOXTYPE_CONTEXT` is the **previous take’s final text** if younger than 60 s, never screen text. The child stdin is only the current transcript. Sources: [`post_process.rs`](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/src/output/post_process.rs), [CONFIGURATION.md “Context from Previous Dictation”](https://github.com/peteonrails/voxtype/blob/main/docs/CONFIGURATION.md).
- Non-zero exit / timeout / empty output falls back to the raw transcript. Same docs. This is why OCR must return `[]` and never fail the hook. Repo constraint: `scripts/voxtype-refine` docstring and `ARCHITECTURE.md`.
- `pre_recording_command` is the Hyprland submap hook. Source: [`config/default.toml`](https://github.com/peteonrails/voxtype/blob/main/config/default.toml). Plan is right not to take that seam.
- `[whisper].initial_prompt` is daemon config / `--initial-prompt` at daemon start. The transcriber copies it once. Parakeet and Cohere configs have no prompt/hotword/vocabulary fields. Sources: [CONFIGURATION.md `initial_prompt`](https://github.com/peteonrails/voxtype/blob/main/docs/CONFIGURATION.md), [`src/config.rs`](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/src/config.rs).
- `[text].replacements` run after ASR, before post-process, from a `TextProcessor` built in `Daemon::new`. Not hot-reloaded per take. Sources: [`src/text/mod.rs`](https://github.com/peteonrails/voxtype/blob/main/src/text/mod.rs), [`src/daemon.rs`](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/src/daemon.rs).
- whisper.cpp itself can set `initial_prompt` per `whisper_full` call. Source: [whisper-cli `--prompt`](https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md). Voxtype does not expose that per utterance.
- NVIDIA Speech NIM documents request-time word boosting for some Parakeet models. Source: [NVIDIA ASR customization](https://docs.nvidia.com/nim/speech/latest/asr/customization/customization.html). Voxtype’s local ONNX adapter does not.
- Cohere Transcribe v2 request fields are model/language/temperature/file. Source: [Cohere Create a transcription](https://docs.cohere.com/reference/create-audio-transcription).

**ASR injection is correctly a non-goal.** The v1 ceiling the plan already names — refine can only respell a near-miss already in the transcript — is a Voxtype 0.7.5 fact, not a Prism bug.

## Prompt injection and secrets

Untrusted OCR tokens in a remote refine request are **indirect prompt injection** plus **secret disclosure**. OWASP 2026 LLM01: models do not architecturally separate instructions from data. Source: [OWASP LLM01](https://raw.githubusercontent.com/GenAI-Security-Project/GenAI-LLM-Top10/main/2026/final/LLM01_PromptInjection.md).

Anthropic’s current jailbreak guidance names OCR output as an injection delivery surface, says to JSON-encode untrusted strings, and to state in the system prompt that such data cannot override the task. Source: [Mitigate jailbreaks](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks). OpenAI’s Model Spec says quoted JSON/XML/YAML has no authority by default. Source: [Ignore untrusted data](https://model-spec.openai.com/2025-12-18.html#ignore_untrusted_data).

That **justifies** a separate `on_screen_spellings` JSON field and the planned DEFAULT_SYSTEM sentences. It does **not** make the field a security guarantee. The user owns `refine-prompt.md` in full (`AGENTS.md`, `compose_system_prompt`); a customized prompt can drop the inert-data rule.

Provider retention (not training) still applies:

- OpenAI platform: not trained on API data by default; abuse logs may keep prompts up to 30 days. Sources: [Enterprise privacy](https://openai.com/enterprise-privacy/), [Your data](https://developers.openai.com/api/docs/guides/your-data).
- Anthropic commercial/API: inputs/outputs not used for training by default; deleted within 30 days except policy/legal/ZDR exceptions. Sources: [Commercial training](https://privacy.claude.com/en/articles/7996885-how-do-you-use-personal-data-in-model-training), [Retention](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data).
- xAI: “never trains on your API inputs or outputs without your explicit permission”; default 30-day encrypted retention; ZDR is team-wide and optional. Source: [xAI Security FAQ](https://docs.x.ai/developers/faq/security).

`local` at `127.0.0.1:8000` removes provider retention. It does not stop the model following OCR instructions or pasting a surviving secret into the typed transcript (`README.md` § Security: remote providers receive transcript, context, and spellings as JSON).

64 terms / 4 KiB cap blast radius. They do not stop a 6-digit OTP, a hyphenated recovery code, a `.env` identifier, or an instruction-shaped Title Case sentence. Default-off is required because Grok/Anthropic/OpenAI receive the terms (`README.md` already discloses that refine is the only network path).

Capture-at-refine-time vs record-start: Superwhisper documents the switch-window failure for refine-time application context. VoiceInk avoids it by capturing during recording. Refine-time is **fresher** for the paste target and **riskier** if the user opened a password manager during transcription. Neither timing is secret-safe. Prism cannot steal `pre_recording_command` (repo constraint), so refine-time is the correct seam — with lock-class skips and honest disclosure.

## Design critique

The proposed module is **deep** in the right place.

Interface the rest of Prism must learn:

- one boolean in `refine.toml` / workbench
- one optional JSON array
- two extra DEFAULT_SYSTEM sentences
- `collect_on_screen_spellings(...) -> list[str]` fail-closed
- `extract_spellings(text) -> list[str]` as the test surface

Deletion test: without the module, every caller reimplements grim geometry, timeouts, secret filters, byte caps, and fail-closed. That is leverage.

Locality: QML stays presentation-only (`AGENTS.md`, `ARCHITECTURE.md`). Capture bugs stay in `scripts/voxtype-refine`. `refine-dictionary.md` stays a user-owned 32 KiB file (`load_dictionary` / `MAX_DICTIONARY_BYTES` in `scripts/voxtype-refine`). `test-refine` must not live-capture (existing settings contract: `test-refine` is the only settings action allowed to contact a provider; it must not screenshot the workbench).

Seam placement: **inside the post-process child** is correct. Two adapters (`GrimTesseractSource`, `FixtureSource`) make the internal seam real. A third `AtspiSource` later is the same interface, not a new QML `Process`.

Shallower rejected designs in the plan stay rejected:

| Rejected | Why, with source |
|---|---|
| Append OCR to `refine-dictionary.md` | Persists secrets into a 32 KiB user file; races the workbench. Repo: `MAX_DICTIONARY_BYTES`, dictionary editor. |
| Dump OCR into `context_for_disambiguation_only` | That field is prior dictation (`VOXTYPE_CONTEXT`) and “must never be copied.” Repo: `DEFAULT_SYSTEM`. |
| Vision LLM on a screenshot | Wispr sends screenshots; Prism’s contract is text-only (`README.md` § Security). |
| QML `grabToImage` / Process grim | Breaks presentation-only. |
| Chain `pre_recording_command` | Voxtype compositor submaps. |
| Whisper `initial_prompt` / `[text].replacements` | Not per-take; Parakeet/Cohere have no equivalent. |

The plan is slightly **too shallow on the capture adapter**: it treats `grim -g` as “focused window.” That leaks neighboring windows. Depth belongs behind `collect_on_screen_spellings`: callers should not learn `stableId` vs geometry.

A hybrid that is strictly stronger than the plan as written, without moving the seam:

1. Same module and JSON field.
2. Capture adapter: `grim -T stableId` (geometry fallback only).
3. OCR: Tesseract LSTM, native resolution unless x-height is out of band; 1280 is not a rule.
4. Refine-time collection, started as early as `refine_text()` so grim/OCR overlap other local I/O.
5. AT-SPI later, same interface, tried first when it returns text.

Do not merge screen terms into `preferred_spellings`. VoiceInk’s vocabulary/context split and this repo’s dictionary contract both forbid it. Screen terms are noisy and secret-bearing; user terms are spelling authority.

## Claim accept / reject

| Plan claim | Decision | Why |
|---|---|---|
| Capture at refine time (not recording start) is correct | **Accept** | Superwhisper captures application context between transcription and AI processing. Prism cannot take `pre_recording_command`. Document the switch-window caveat Superwhisper already names. |
| grim + tesseract is the right v1 adapter | **Accept, with capture-method delta** | Already installed; no extra daemon; RapidOCR/Surya/VLM add packaging or latency depth. Use `grim -T`, not `-g`, as the production capture. |
| Separate JSON field `on_screen_spellings` | **Accept** | VoiceInk splits vocabulary vs window context. Anthropic/OpenAI recommend JSON-encoding untrusted data. Must not merge into `preferred_spellings` or `context_for_disambiguation_only` (`DEFAULT_SYSTEM` in `scripts/voxtype-refine`). |
| Live in `scripts/voxtype-refine`, not a new helper or QML Process | **Accept** | Only network path; fail-closed on non-zero exit; QML is presentation-only. |
| Default-off opt-in | **Accept** | Terms go to Grok/Anthropic/OpenAI (30-day provider logs even when training is off). VoiceInk’s screen flag defaults false; Wispr’s default-on screenshot is the anti-pattern. |
| 64 terms / 4 KiB / 1.5 s OCR timeout / 1280 px long edge | **Accept 64 / 4 KiB / 1.5 s as volume and deadline bounds; reject 1280 as a hard rule** | Caps do not stop a short secret. 1.5 s is plausible on this CPU for a modest window. 1280 is not Tesseract’s documented advice and can shrink UI x-height below 10 px. |
| ASR injection is a non-goal | **Accept** | Voxtype 0.7.5 has no per-utterance hotword seam for Parakeet/Cohere/Whisper-in-daemon. |

## Deltas to apply when implementing

Keep the module, JSON field, DEFAULT_SYSTEM sentences, workbench boolean, fail-closed OCR, fixture tests, and ASR non-goal.

Change:

1. **Production capture:** `grim -T` + `stableId`. Geometry crop is fallback only, documented as leaky.
2. **Scaling:** preserve native pixels unless x-height is outside ~10–30 px. Optional later cap (VoiceInk uses 2800, not 1280).
3. **Tesseract:** `--oem 1`; start `--psm 6`; consider `load_system_dawg=false` for code-only captures after a corpus exists.
4. **Lock skip:** fail-closed on hyprlock/greeter *class* as a heuristic; do not claim compositor lock-state observation.
5. **`parse_refine_toml` / `load_selection`:** read boolean `screen_context` (today only `provider`/`model`).
6. **Workbench copy:** extracted on-screen *words* go to the selected provider and may be retained ~30 days for abuse review even when not used for training.
7. **README:** document the new JSON field for people who replaced `refine-prompt.md` (existing invariant: user owns the full prompt).
8. **Start collection at the top of `refine_text()`** so capture overlaps dictionary/credential reads, still before `complete()`.
9. **Do not OCR both monitors.** Keep focused-window default.

Drop:

- Treating 1280 px as Tesseract doctrine.
- Treating `grim -g` as “the focused window.”
- Any implication that filters make remote refine secret-safe.

## Verdict

**Ship with listed deltas.**
