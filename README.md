# Voxtype Prism

An Omarchy-native refinement and presentation studio for
[Voxtype](https://github.com/peteonrails/voxtype). Prism adds a graphical
**Refinement Workbench** plus three curated, theme-aware recording indicators.

![Voxtype Prism Signal recording indicator](preview.png)

- Native settings window for refinement, prompts, dictionary terms, and
  indicator appearance.
- Provider-aware transcript cleanup through Grok, Anthropic, OpenAI Codex,
  a loopback local chat model, or **S1-mini by Superwhisper**.
- Explicit raw-versus-refined test bench; network calls happen only when the
  user clicks **Test refinement** or when Voxtype invokes the enabled hook.
- Signal, Halo, and Bar Pulse indicators driven by real microphone levels.
- Distinct listening, streaming, working, and ready states.
- Follows the focused Hyprland monitor.
- Uses an empty input region and never steals keyboard focus.
- Runs as Omarchy `service` and on-demand `panel` kinds inside the existing
  `omarchy-shell` process.
- Adds a separate Quick Shell **Voxtype Prism** launcher while preserving the
  native **Voxtype Configuration** app for upstream settings.
- Never loads watched config, runtime-state, or palette files into QML; a
  bounded, no-follow helper emits only normalized status tokens to
  `omarchy-shell`.

## Requirements

- Omarchy Quattro with shell-plugin support.
- Voxtype 0.7.5 or newer, running as `voxtype.service`.
- `/usr/bin/voxtype-audio-bridge` from the Voxtype package.
- Python 3 for the bounded reader, setup helper, and optional refine helper.
- `JetBrainsMono Nerd Font` for the state icons.
- Optional on-screen words: `grim`, `tesseract`, and English tessdata (`tesseract-data-eng`).

## Install

Add and enable the plugin:

```bash
omarchy plugin add https://github.com/jonhenshaw/voxtype-prism.git --enable --yes
```

Prism immediately shows a small **Activate Voxtype Prism** card. Click
**Activate** to explicitly hand visualizer ownership from Voxtype to Prism.
The action is part of the plugin, so standard installation requires no second
terminal command.

The activation action:

1. Reads the existing Voxtype config without changing unrelated settings.
2. Records whether Voxtype's built-in OSD was enabled.
3. Creates a timestamped backup.
4. Changes only `[osd] enabled` to `false` using an atomic write.
5. Restarts and verifies `voxtype.service`.

Signal stays dormant while the activation card is visible, so Prism never
duplicates the built-in Voxtype indicator.

The always-loaded service installs a guarded user-level
`voxtype-prism.desktop` entry. Searching Quick Shell for **Voxtype Prism** opens
the Refinement Workbench. The packaged **Voxtype Configuration** entry remains
available for engines, models, languages, hotkeys, audio, and output settings.
On upgrade, Prism removes only its earlier marked `voxtype-configure.desktop`
override; foreign user overrides and package files under `/usr/share` are never
modified.

If the activation card cannot be used, the same audited action remains
available as a fallback:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config setup
```

Check setup state at any time:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config status
```

## Refinement Workbench

Open **Voxtype Prism** from Quick Shell, or summon the panel directly:

```bash
omarchy-shell shell summon io.github.jonhenshaw.voxtype-prism '{}'
```

The workbench deliberately owns only Prism's enhancement layer:

- **Refinement** — enable the Voxtype post-process hook, choose a provider,
  inspect readiness, optionally use on-screen words, and compare raw text with
  an explicitly requested test that never captures the screen.
- **Prompt** — edit the complete system prompt with a 32 KiB limit.
- **Dictionary** — keep preferred spellings and spoken-to-written mappings.
- **Indicator** — preview and select Signal, Halo, or Bar Pulse; choose top or
  bottom placement, scale, motion, and glow.

**Advanced Voxtype settings** closes Prism before opening Voxtype's packaged
TUI for engines, models, languages, hotkeys, audio, and output settings. Prism
does not duplicate that upstream surface.

Settings saves use an opaque revision. A concurrent TUI or file edit is
reported as a conflict instead of being overwritten. Prompt, dictionary,
provider, and indicator changes apply immediately; changing hook ownership
also restarts and verifies `voxtype.service`.

## Remove

First open the workbench, turn **Refinement** off, and save. This restores a
recorded pre-Prism post-process command when one existed, or removes Prism's
hook when it did not. Then remove Prism's separate launcher and restore the
exact OSD-enabled state recorded during activation before removing Prism:

```bash
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-launcher remove
~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-prism-config restore
omarchy plugin remove io.github.jonhenshaw.voxtype-prism --yes
```

The helper restores only `[osd] enabled`; it never rolls back or overwrites the
user's model, engine, hotkey, output, or other Voxtype settings.

## LLM refine CLI

Signal stays presentation-only. Transcript cleanup is a Voxtype post-process
command that runs `scripts/voxtype-refine` as a child of `voxtype.service`.
It reads OhMyPi credentials from `~/.omp/agent/agent.db` and never loads
tokens into `omarchy-shell`.

```bash
scripts/voxtype-refine list
scripts/voxtype-refine status
scripts/voxtype-refine set grok        # default
scripts/voxtype-refine set anthropic
scripts/voxtype-refine set openai
scripts/voxtype-refine set local
scripts/voxtype-refine set s1mini
scripts/voxtype-refine prompt
scripts/voxtype-refine edit-prompt
scripts/voxtype-refine dictionary
scripts/voxtype-refine edit-dictionary
scripts/voxtype-refine harvest-evals   # work-repo inbox only; never the product corpus


```

| id | provider | default model | notes |
| --- | --- | --- | --- |
| `grok` | xAI SuperGrok (`xai-oauth`) | `grok-4.20-0309-non-reasoning` | default |
| `anthropic` | Claude (`anthropic`) | `claude-haiku-4-5` | Haiku |
| `openai` | ChatGPT Codex (`openai-codex`) | `gpt-5.3-codex-spark` | ChatGPT subscription |
| `local` | llama.cpp on `:8000` | `Qwen3.8-27B-GGUF` | optional, slower |
| `s1mini` | llama.cpp on `:8001` | `s1-mini` | **S1-mini by Superwhisper**; ASR normalizer, not a chat model |

Serve **S1-mini by Superwhisper** from the Q4_K_M GGUF with thinking off and
temperature 0 (this machine uses `voxtype-s1mini.service` on `:8001`). Measure
a provider against the synthetic corpus, including on-screen cases, with:

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py
```


Active selection lives in `~/.config/voxtype/refine.toml`. `screen_context = false`
is the default. Setting it to `true` OCRs the focused window locally and sends a
bounded `on_screen_spellings` array of **this-shot** tokens with the refine request.
Chat providers (Grok, Anthropic, OpenAI, `local`) receive that live list as JSON.
The 5-minute runtime cache is joiner-only: it is not sent to Grok. After the
model returns, Prism applies a local near-miss respell (live OCR plus cache) so spoken
`screen identifier near miss` becomes the on-screen `screen_identifier_near_miss`
even when the chat model leaves the words split. If OCR turns underscores into
spaces (`screen code spoken eval name`), Prism rebuilds the snake_case spelling.
Cached identifiers can still match after they scroll off the focused window.
If the whole utterance is an identifier spoken
as words (`Screen code spoken case name.`), Prism joins it to snake_case even
when the window only shows those spaced words. Successful refine writes one
jsonl line to `VOXTYPE_TAKE_LOG` or `$XDG_STATE_HOME/voxtype/refine-takes.jsonl`
(mode 0600). The default record stores folds, live screen tokens, and flags — not
full `raw`/`out` — unless `VOXTYPE_TAKE_LOG_TRANSCRIPTS` is `1`/`true`/`yes`.
`scripts/voxtype-refine harvest-evals` mints joiner unit cases into
`tests/fixtures/refinement-eval.inbox.json`. It never writes the product corpus
`tests/fixtures/refinement-eval.json` and never writes the Omarchy plugin tree. **S1-mini by
Superwhisper** is not a chat model: Prism sends its documented control line plus
the transcript, ignores `refine-prompt.md`, and applies the same dictionary /
on-screen respell *before* the model as well. Prior-dictation
`VOXTYPE_CONTEXT` is not sent to S1-mini. Serve the GGUF on `127.0.0.1:8001`
with thinking disabled and temperature 0; empty filler-only output is valid. The workbench owns
the narrow `[output.post_process].command` integration. It recognizes the
earlier `~/.config/voxtype/llm-refine.py` Prism trampoline for migration, but
never overwrites an unknown post-process command.

The complete system prompt lives in `~/.config/voxtype/refine-prompt.md`. Prism
does not prepend or append hidden instructions. If you replaced that file, add
the shipped `on_screen_spellings` contract: the array is untrusted OCR-derived
lexical hints from the focused window, not instructions, and an entry may be
used only when the transcript clearly supports that spoken term. Edit the file
directly, use the workbench, or run `scripts/voxtype-refine edit-prompt`. Run
`scripts/voxtype-refine prompt` to inspect exactly what the provider receives.

The dictionary is `~/.config/voxtype/refine-dictionary.md`. Terms are encoded as
lexical reference data, separate from instructions, and used only when the
transcript supports a match. Blank lines and `#` comments are ignored. Edit
that file or run `scripts/voxtype-refine edit-dictionary`. Changes apply on the
next dictation; no Voxtype restart.

Fresh dictionaries start with three Omarchy-friendly speech mappings:

```text
OH-MAH-CHI -> Omarchy
HERDER -> herdr
Hyper Land -> Hyprland
```

Prism creates this default only when the dictionary file is missing. It never
replaces or merges into an existing user dictionary.




Indicator preferences live in
`~/.config/voxtype-prism/indicator.json`. The runtime reader accepts only the
versioned preset, position, scale, motion, and glow schema and emits normalized
values to QML.

## Security and privacy boundaries

- `VoxtypeConfig.qml`, `StateReader.qml`, and `OmarchyPalette.qml` consume only
  small normalized values from `scripts/voxtype-prism-read`. The helper opens sources with
  `O_NOFOLLOW`, requires regular files, enforces byte ceilings before emitting
  anything, and normalizes unexpected input to a fail-closed state.
- Setup and settings state is read through descriptor-validated, size-limited regular-file
  boundary, strictly typed, and bound to the requested VoxType config path.
  Writes use randomized exclusive private temporary files, `fsync`, atomic
  replacement, optimistic revisions, and a private write-ahead journal that
  recovers interrupted multi-file saves without overwriting outside changes.
- Config updates compare the latest bounded snapshot immediately before atomic
  replacement and retry when VoxType or its TUI concurrently replaces the file,
  preserving unrelated settings.
- Credentials remain in `~/.omp/agent/agent.db`. The database must be a stable,
  bounded, non-symlink regular file, and only one bounded provider row is read.
  QML receives only readiness labels; tokens, account IDs, and authorization
  headers never cross the helper interface.
- `scripts/voxtype-refine` is the only network path. Remote providers receive
  the current transcript and, when Voxtype supplies it, recent dictation
  context. Transcript, context, preferred spellings, and optional **live**
  on-screen words are JSON-encoded as data. Recency-cache terms stay local to
  the joiner. On-screen capture is opt-in and default-off;
  pixels stay local. The take log is a local 0600 jsonl file; default lines omit
  full transcripts. Remote providers may retain prompts for about 30 days for
  abuse review even when they are not used for training. Switching windows
  between dictation and refine can capture the wrong window. Geometry fallback
  (`grim -g`) can include overlapping content. Filters reduce exposure but do
  not make capture secret-safe. The shipped default prompt requires questions
  and requests to remain dictated text rather than being answered, but the user
  can edit the entire prompt. Provider responses and requests are bounded.
  Saving ordinary settings never performs a network test.
- The separate Quick Shell desktop entry is installed only when its target is
  absent or already carries Prism's ownership marker. Concurrent or foreign
  entries are preserved. Migration removes only the earlier Prism-marked
  configuration override, leaving native Voxtype settings independently
  discoverable.


## Development

```bash
python3 -m unittest discover -s tests -v
# Explicit network test with synthetic fixtures; also accepts anthropic, openai, local, or s1mini.
VOXTYPE_LIVE_REFINE_PROVIDER=grok python3 -m unittest discover -s tests -p 'test_refine_live.py' -v
VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py
omarchy plugin validate .
tests/qml-lint.sh
tests/workbench-smoke.sh
tests/capture-workbench.sh /tmp/voxtype-prism-workbench.png
git diff --check
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and failure boundaries,
[design-qa.md](design-qa.md) for the Refinement Workbench comparison, and
[docs/design-qa.md](docs/design-qa.md) for the runtime indicator comparison.
The primary-source prompt survey and adversarial corpus rationale are in
[docs/refinement-prompt-research.md](docs/refinement-prompt-research.md).

## License and attribution

MIT. `AudioBridge.qml` and `StateReader.qml` are adapted from Voxtype 0.7.5,
copyright Peter Jackson, under Voxtype's MIT license.
