# Lexicon & evals design review

Date: 2026-09-04

Plan reviewed: [docs/lexicon-evals-design.html](lexicon-evals-design.html)

This is a primary-source review of the proposed take-log / record-start /
recency / harvest-eval work packages. It does not implement the feature and
does not edit the plan.

Evidence kinds:

- **Published source** — product or protocol source inspected at a named path.
- **Official documentation** — first-party docs/specs.
- **Local runtime** — this machine (Hyprland 0.56.2 `efb5099`, grim 1.5, tesseract 5.5.3, voxtype-bin 1.0.1 / `voxtype-onnx-cuda-13`, dual 4K at scale 1.6).
- **Repo constraint** — named files in this repository.

## Verdict

**Revise.** Keep P1 (local take log) and the *idea* of minting identifier unit
cases from harvest. Do not implement P2, P3-as-Grok-payload, P4-at-refine-time,
or auto-append into `tests/fixtures/refinement-eval.json` until the plan names
a real recording-start seam, splits “lexicon used by the local joiner” from
“strings sent to Grok,” and replaces auto-git with an inbox a human commits.
As written, P2 revives the rejected cache-file design with no Voxtype hook
this machine can call; P5 can promote personal transcripts, session secrets,
and invented snake_case into the product corpus; P3/P4 enlarge the unspoken
insertion surface the Juniper eval already forbids.

## What the plan gets right

The three hard rules in the HTML (`docs/lexicon-evals-design.html:280-284`)
match shipped contracts:

- Pixels stay local. Repo: `ARCHITECTURE.md:52-54`, `README.md:236-244`,
  `scripts/voxtype-refine:1246-1248` (temp PNG fd, unlinked after tesseract).
- OCR never writes `refine-dictionary.md`. Repo:
  `docs/on-screen-context-plan.md:95-96`, `scripts/voxtype-refine:43`
  (`MAX_DICTIONARY_BYTES`), workbench dictionary editor.
- Unspoken screen terms must not be inserted. Repo: `DEFAULT_SYSTEM`
  (`scripts/voxtype-refine:66`), eval `screen_unrelated_not_inserted`
  (`tests/fixtures/refinement-eval.json:94-98`), joiner test
  (`tests/test_refine.py:1196-1200`).

The capture adapter stays behind `collect_on_screen_spellings()` /
`extract_spellings()` (`scripts/voxtype-refine:850-1078`). That is the
module the previous review accepted. AT-SPI and tmux as later adapters on
the same interface is consistent with v1.5 in
`docs/on-screen-context-plan.md:72-73`.

P1 is the right first package. Voxtype already logs only
`Post-processed: changed: true/false` (local runtime: `journalctl --user -u voxtype`).
The child already has raw, out, screen, and window class in process. A 0600
jsonl under `$XDG_STATE_HOME` is the same privacy class as
`scripts/voxtype-prism-settings:150-156` (`$XDG_STATE_HOME/voxtype-prism/`).
No extra gesture, no git.

P6’s “never silent OCR append” is the correct dictionary policy. Confirm-to-pin
after repeated successful joins is an explicit amendment of the v1 non-goal
“learning screen terms into the user dictionary”
(`docs/on-screen-context-plan.md:196`), not a revival of append-OCR.

The v1 ceiling is still true and still a Voxtype fact: refine can only respell
a near-miss already in the transcript (`docs/on-screen-context-plan.md:23-24`).
Record-start OCR cannot recover a dropped word.

Factory A’s *shape* — harvest a real identifier, invent the spoken split, run
`apply_lexical_hints` in-process, mint a joiner unit case on failure — is how
`screen_code_*` was built (`experiments/README.md:117-125`). That should stay
local and synthetic.

Current helper behavior the plan correctly restates
(`docs/lexicon-evals-design.html:297-299`):

- Capture is refine-time `GrimTesseractSource.read_text()`
  (`scripts/voxtype-refine:1223-1248`, called from `refine_text`
  `scripts/voxtype-refine:2065-2071`).
- Timeouts are capture 3.0s / tesseract 5.0s (`scripts/voxtype-refine:56-57`).
- 5-minute runtime cache, persisted only when `source is None`
  (`scripts/voxtype-refine:1297-1307`).
- `_utterance_identifier_hint` joins a 3–6 fragment identifier-shaped
  utterance to snake_case when `on_screen_spellings is not None`, including
  `[]` (`scripts/voxtype-refine:998-1014`, `1424-1429`).
- Empty-OCR join is already unit-tested:
  `tests/test_refine.py:1452-1470`.

## Product / runtime facts the plan depends on

| Fact | Source |
|---|---|
| Live post-process command is the **plugin** copy, timeout 30s | Local: `~/.config/voxtype/config.toml:91-93`; journal `Post-processing enabled: … timeout=30000ms` |
| Work-repo trampoline exists but is not the live hook | Local: `~/.config/voxtype/llm-refine.py` `runpy`s the work-repo script; `[post_process]` (TUI bug table) points there; `[output.post_process]` does not |
| Plugin and work-repo helpers are currently byte-identical (2222 lines) | Local: `diff -q` silent. They will drift; workbench writes the plugin path (`scripts/voxtype-prism-settings:159-161`) |
| Recording starts on **evdev HOME**, push-to-talk | Local: `~/.config/voxtype/config.toml:14-18` `hotkey.enabled = true`, `key = "HOME"` |
| Hyprland has **no** start/stop bind; Escape only cancels | Local: `~/.config/hypr/bindings.lua:50-66` |
| Omarchy still binds F9 PTT + Super+Ctrl+X toggle | Official/local: `/usr/share/omarchy/default/hypr/bindings/voxtype.lua:1-4`, loaded because `~/.config/hypr/hyprland.lua:17` requires `default.hypr.omarchy` and does not set `omarchy_default_bindings = false` |
| `pre_recording_command` is **not** a settable 1.0.1 schema key | Local: `voxtype config get output.pre_recording_command` → `unknown config key`. Comments remain in `/etc/voxtype/config.toml:189-201` and upstream `config/default.toml`. Binary still contains `voxtype setup compositor` strings for Hyprland/Sway/River submaps |
| Post-process child cwd is `/home/henny`, not the focused project | Local: `readlink /proc/$(systemctl --user show -p MainPID voxtype.service)/cwd` |
| Voxtype does not pass a recording generation id | Published: `post_process.rs` stdin = transcript, env = optional `VOXTYPE_CONTEXT` (prior take, 60s). Local: `$XDG_RUNTIME_DIR/voxtype/state` is `idle`/`recording`/`transcribing` |
| Session stores are huge and secret-bearing | Local sizes: `~/.hermes` 8.3G (`state.db` 359M), `~/.codex/sessions` 683M, `~/.claude/projects` 376M, `~/.grok/sessions` 144M |
| Live 5-minute cache is a **flat** 64-term list, not keyed by `stableId` | Repo: `scripts/voxtype-refine:1251-1307`. Local file currently holds OCR junk and Title Case UI words (`SESSIONS`, `PINNED`, `Show`, …) |
| Exact-match eval harness | Repo: `tests/run_refinement_eval.py:167`, `experiments/README.md:103-104` |
| Personal transcripts must not enter git | Repo: `experiments/README.md:132`, `AGENTS.md:16-19` |
| `test-refine` never live-captures | Repo: `scripts/voxtype-prism-settings:1381-1418`, `ARCHITECTURE.md:142-143` |

## Issues

### Issue 1 -- Severity: blocker

- File: `docs/lexicon-evals-design.html:369-380` and `:419-423`
- Description: P2 “record-start grim on hotkey-down … without stealing `pre_recording_command`” has **no implementation seam** on this machine or in Voxtype 1.0.1.

  The plan wants: on hotkey-down, grim the focused window to a runtime PNG with
  a generation id; refine OCRs it if younger than the recording; merge with the
  post-ASR shot; delete both.

  What actually starts recording:

  1. **Evdev HOME** inside `voxtype.service` (`config.toml:14-18`). Prism is
     not in that path. Hyprland never sees the key as a bind.
  2. **Omarchy F9** / Super+Ctrl+X (`/usr/share/omarchy/default/hypr/bindings/voxtype.lua:1-4`).
     A Hyprland grim wrapper on F9 would miss HOME, which is how this desktop
     actually dictates.
  3. User Hyprland config has **no** `voxtype record start` bind
     (`~/.config/hypr/bindings.lua:50-66` is cancel-only).

  Voxtype’s only documented recording-start command is still
  `pre_recording_command`, and it is still the Hyprland/Sway/River **submap**
  hook. Official: upstream `config/default.toml` (fetched 2026-09-04)
  “Compositor integration hooks” / `voxtype setup compositor`. Local:
  `/etc/voxtype/config.toml:189-201`. The previous review **accepted**
  refine-time capture and **rejected** recording-start capture that needs a
  cache file (`docs/on-screen-context-plan-review.md:203`, `:30`;
  `docs/on-screen-context-plan.md:99`).

  On voxtype-bin 1.0.1 the TUI schema no longer lists
  `pre_recording_command` as settable (`voxtype config schema` has
  `output.post_process.command` and not the compositor hooks). The daemon
  binary still embeds the setup-compositor strings. Either way, Prism cannot
  “call a tiny helper Voxtype can call” — there is no such callback — and
  taking the old field still collides with `voxtype setup compositor`.

  The only unified signal for HOME **and** F9 is
  `$XDG_RUNTIME_DIR/voxtype/state` flipping to `recording`. Watching that is
  exactly the rejected design: extra daemon + cache file to wipe
  (`docs/on-screen-context-plan.md:99`). Voxtype does not pass a generation
  id to the post-process child (published: `src/output/post_process.rs` on
  `peteonrails/voxtype` main; stdin is the transcript, env is
  `VOXTYPE_CONTEXT`). “Younger than the recording” is therefore mtime
  guesswork. A cancelled take leaves a PNG that the next dictation can OCR.

- Suggestion: Either (a) drop P2 and treat refine-time + local joiner +
  session-harvest-offline as the scrolled-window answer, or (b) explicitly
  amend `on-screen-context-plan.md` to allow a state-file watcher, specify
  the unit (`systemd --user` path unit vs long-lived helper), the PNG
  lifetime (unlink on idle/cancel, not only after refine), and that this is
  the extra daemon previously rejected. Do not claim a Hyprland hotkey-down
  hook unless it wraps **both** HOME (impossible without evdev or
  `pre_recording_command`) and F9. Do not put a generation id in the plan
  until Voxtype has a field to carry it.
- Status: open

### Issue 2 -- Severity: blocker

- File: `docs/lexicon-evals-design.html:336-343` and `:435-438`
- Description: Auto-accept into `tests/fixtures/refinement-eval.json` can
  commit personal identifiers, session-mined secrets, and wrong expected
  strings despite the filter.

  Corpus rules (`experiments/README.md:106-132`): product cases belong in
  `refinement-eval.json`; names unique; identifier cases are **synthetic
  spoken splits of real tokens**; **do not paste personal session text**;
  crowded shared `on_screen_spellings` so a hit must pick the spoken
  identifier. Auto-accept from the take log inverts that: live ASR text
  becomes `transcript`, and factory B’s worked example
  (`docs/lexicon-evals-design.html:346-358`) promotes
  `Screen code spoken case name.` → expected `screen_code_spoken_case_name.`
  That utterance is a personal dictation of a fixture name, not a synthetic
  split authored for git.

  The filter is insufficient:

  1. `extract_spellings` already keeps hyphenated tokens
     (`scripts/voxtype-refine:895-896`). Bare `sk-live`-shaped keys survive
     when they are not on a `password|token|api key =` line
     (`SECRET_ASSIGNMENT_RE` at `:709-711`; tests only cover assignment
     lines, `tests/test_refine.py:858-896`).
  2. “no paths under `/home/henny/`” does not catch `henny`, `Work`,
     `voxtype-signal-osd` as separate tokens (`TOKEN_RE` at
     `scripts/voxtype-refine:717`; `tests/test_refine.py:852-856` keeps
     `voxtype-signal-osd` from a prompt-looking path).
  3. “dictionary secrets” only compares against `refine-dictionary.md`.
     Session JSONL/SQLite is the actual secret store (Hermes `state.db`
     359M, Codex/Claude/Grok jsonl). Factory A harvests those through
     `extract_spellings` only — that filter was built for **visible OCR**,
     not tool results, env dumps, or `auth.json` adjacent files.
  4. Factory B mints `expected` as “that token” from screen/cache **or**
     invents snake_case from fragments when OCR is polluted (worked
     example step 4). If the real on-screen identifier was camelCase, git
     locks the wrong gold string (see Issue 3).
  5. Auto-accepted cases land in the **live Grok exact-match** corpus
     (`tests/run_refinement_eval.py:167`, `tests/test_refine_live.py:138`).
     Joiner unit cases do not belong there unless `expected` already has
     sentence casing and a final period (`experiments/README.md:123-125`).
     Factory B’s `raw` transcript is ASR casing (`Screen code…`), so Grok
     polish fails exact match even when the joiner is correct.

  “You should never copy a case” (`docs/lexicon-evals-design.html:301-302`)
  and “identifier cases promote themselves” (`:343`) skip the human who
  still has to `git commit` a public plugin repo.

- Suggestion: `harvest-evals` writes **only**
  `tests/fixtures/refinement-eval.inbox.json` (or a gitignored inbox under
  `$XDG_STATE_HOME`). Auto-accept, if it exists at all, copies into the
  product corpus only when: (1) `expected` is produced by factory A from a
  harvested identifier, not from live `raw`; (2) `transcript` is the
  synthetic spoken split, not the take-log sentence; (3) the on-screen list
  is the shared crowded fixture, not the live OCR dump; (4) a human runs
  a promote command. Keep factory B/C in the private log.
- Status: open

### Issue 3 -- Severity: bug

- File: `docs/lexicon-evals-design.html:332` and `:346-358`;
  `scripts/voxtype-refine:998-1014`, `:1424-1429`;
  `tests/test_refine.py:1340-1375`
- Description: Factory B and `_utterance_identifier_hint` overlap, and the
  worked miss mints the **wrong** expected when camelCase is the real token.

  Today, with `screen_context = true`, empty OCR already joins
  `Screen code spoken case name.` → `screen_code_spoken_case_name.`
  (`tests/test_refine.py:1452-1470`). Factory B’s worked example is that
  exact utterance and would mint a corpus case for a join the helper
  **already performs**. A live `changed: false` on that string is now a
  stale-plugin / timeout / `screen_context=false` incident, not a missing
  factory.

  When the screen **does** have a folded match, the joiner prefers it over
  invented snake_case:

  ```text
  apply_lexical_hints("Screen code spoken case name.",
                      on_screen_spellings=["screenCodeSpokenCaseName"])
  → "screenCodeSpokenCaseName."
  ```

  (`tests/test_refine.py:1369-1375`; skip-if-same-fold at
  `scripts/voxtype-refine:1427-1429`). Factory B’s worked example ignores
  that and mints `screen_code_spoken_case_name.`. Auto-accept would then
  fail (or “fix”) the real camelCase behavior.

  Factory B’s other clause — `changed: false` + identifier-shaped + same
  fold on screen/cache — is the useful one, and it is a **recency/OCR-miss**
  detector, not an eval of Grok. If cache still holds `playerId` from
  another window, it will mint `playerId` as expected even when the user
  was looking at a tiny prompt. That encodes Issue 4 as a “passing” eval.

- Suggestion: Delete the worked-example snake invention. Factory B should
  mint only when a **screen/cache token** (not the utterance joiner) has
  the same fold and `apply_lexical_hints` did not apply it. Expected is
  that on-screen token’s spelling, not `_utterance_identifier_hint`. Do
  not put those cases in the Grok corpus; they are joiner unit tests.
- Status: open

### Issue 4 -- Severity: bug

- File: `docs/lexicon-evals-design.html:368-369`, `:425-428`;
  `scripts/voxtype-refine:66`, `:1251-1307`;
  `tests/fixtures/refinement-eval.json:94-98`
- Description: Recency across last-K windows, keyed by `stableId`, still
  feeds `on_screen_spellings` to Grok. That is the Juniper insertion
  failure mode, scaled up.

  The hard rule is “unspoken names stay out”
  (`docs/lexicon-evals-design.html:284`). The local joiner already obeys
  it (`apply_lexical_hints` + `Juniper` test, `tests/test_refine.py:1196-1200`).
  Grok does not; `screen_unrelated_not_inserted` exists because the model
  will paste a nearby identifier. `DEFAULT_SYSTEM:66` is prompt text, not
  enforcement (`docs/on-screen-context-plan-review.md:140-144`).

  Today’s cache is already a 5-minute **global** bag
  (`scripts/voxtype-refine:1304-1307`, no `stableId`). Local runtime
  `on-screen-lexicon.json` currently holds OCR debris and Title Case UI
  words. Those already occupy the 64/4KiB cap
  (`scripts/voxtype-refine:52-54`) and are sent to Grok whenever
  `screen_context` is on (`refine_text:2065-2081` →
  `build_refinement_input:1513-1515`). P3 “merge last K focused windows”
  makes the bag larger and more cross-window, which is what the user asked
  about and what Superwhisper documents as the switch-window failure
  (`docs/on-screen-context-plan-review.md:32-41`).

  The P3 test (“spoken identifier from window A still joins after focus
  moves to tiny window B”) is a **joiner** test. It does not prove Grok
  will leave `playerId` / `Juniper` / `canonicalPlayerId` uninserted.

- Suggestion: Split the stores. Recency cache may feed `apply_lexical_hints`
  only. The JSON field sent to Grok / Anthropic / OpenAI should be
  **this-shot** tokens (record-start merge if P2 exists, else refine-time
  live OCR), not last-K windows. Keep the 64/4KiB cap on the provider
  payload. Document that recency is TTL, not learning — the HTML says
  this (`:368`) but P3’s merge-into-`collect_on_screen_spellings` does
  not implement it.
- Status: open

### Issue 5 -- Severity: bug

- File: `docs/lexicon-evals-design.html:331`, `:406-410`, `:430-433`
- Description: P4 “cwd-scoped” session + `git ls-files` harvest is not
  cwd-scoped from the refine child, and running it on refine will miss
  the 30s timeout and scrape secret-bearing stores.

  The post-process child inherits `voxtype.service` cwd `/home/henny`
  (local runtime). `/home/henny` is not a git work tree. `git ls-files`
  from that cwd is empty or wrong. Focused Ghostty cwd is not in
  `hyprctl activewindow -j` (local sample: class/title/pid/`stableId`/geometry
  only). Grok sessions *are* laid out by project path
  (`~/.grok/sessions/%2Fhome%2Fhenny%2FWork/…`), Claude by encoded cwd
  (`~/.claude/projects/-home-henny-Work-…`). That mapping is doable, but
  it is **not** `os.getcwd()`.

  Factory A says “timer or on refine”
  (`docs/lexicon-evals-design.html:331`). On refine, walking Hermes
  `state.db` (359M) + Codex 683M + Claude 376M + Grok 144M through
  `extract_spellings`, plus two grim/tesseract passes (3s+5s each worst
  case, `scripts/voxtype-refine:56-57`), plus Grok, will hit Voxtype’s
  30s fallback (`config.toml:93`; published `post_process.rs` timeout →
  original transcript). Empty/timeout looks like `changed: false` and
  poisons factory B.

  `extract_spellings` is the wrong gate for session files. It drops
  emails, JWTs, long hex, and `password=` lines
  (`scripts/voxtype-refine:1053-1063`). It keeps screaming env names
  (`FOURTH_DOWN_MODEL_BASE_URL` is in the crowded fixture on purpose,
  `tests/fixtures/refinement-eval.json:329-348`), kebab filenames, and
  any camelCase local variable from a tool result. Plan text “Do not put
  full session transcripts, `.env`, or clipboard contents into Grok”
  (`:410`) is correct; P4’s “same `extract_spellings`” does not implement
  that for SQLite/jsonl.

- Suggestion: Harvest **offline** in `harvest-evals`, never inside
  `refine_text()`. Resolve project identity from the focused window’s
  `/proc/<pid>/cwd` (Ghostty) or from agent session path encoding — name
  the adapter. Cap bytes read (the helper already has bounded readers).
  Allowlist file globs (`*.jsonl` session transcripts in a known layout),
  never `state.db` / `auth.json`. `git ls-files` only after a resolved
  work tree, basenames only, skip `.env*` / `id_*` / `*.pem`. Harvested
  tokens feed factory A and the **local** joiner, not the provider JSON,
  unless they also appear in this-shot OCR (Issue 4).
- Status: open

### Issue 6 -- Severity: bug

- File: `docs/lexicon-evals-design.html:369-370`, `:421-423`;
  `scripts/voxtype-refine:56-57`, `:2065-2090`;
  `~/.config/voxtype/config.toml:93`
- Description: Two OCR passes plus Grok do not fit a worst-case 30s
  budget, and stale record-start PNGs are not generation-safe.

  Current refine already overlaps one `collect_on_screen_spellings()` with
  dictionary/prompt IO (`scripts/voxtype-refine:2066-2071`). Adding a
  second grim+tesseract (3s + 5s timeouts each) sequentially leaves ~14s
  for Grok on a slow window; two timeouts plus a slow provider hit 30s
  and Voxtype pastes the raw transcript (published `post_process.rs`
  fallback; local journal will then show `changed: false` even when the
  joiner would have worked). The live misses that motivated P2 were
  tesseract 1.5s timeouts; the helper already raised that to 5s. A second
  pass reintroduces the deadline.

  “Younger than the recording” cannot be implemented: no recording
  timestamp is passed in. State file mtime changes on idle→recording→
  transcribing→idle. A PNG from a cancelled PTT can still be “young.”
  Tests “stale file ignored; missing file is `[]`” are necessary but do
  not define stale.

- Suggestion: If record-start capture exists, OCR that PNG **instead of**
  a second live shot when it matches the watcher generation, or OCR both
  **in parallel** under the existing 3s/5s caps and merge tokens. Bound
  total OCR wall time so `complete()` still has ≥10s. Treat missing/stale
  as `[]` without blocking. Delete on `state=idle` and on cancel, not
  only after a successful refine.
- Status: open

### Issue 7 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:317-328`, `:394`
- Description: A 30-day jsonl of every dictation is a PII store next to
  the lexicon, and P1 as specified logs more than harvest needs.

  `raw` is the full ASR sentence (the plan itself uses “um send the
  report…” as the prose that must never become a repo eval,
  `:342-343`). `screen` is the 64-term OCR list (secret-bearing;
  `README.md:236-244`). `window` is a class string (fine). 0600 and
  “not git” are correct and match how the helper writes the lexicon cache
  (`scripts/voxtype-refine:1290`). They do not encrypt, rotate, or redact.
  `ok_lex` in the sample record (`:323`) is undefined in P1
  (`:417`).

  Identifier harvest only needs: folded utterance shape, screen/cache
  tokens, changed, timestamps. Full prose is for factory C and debugging.

- Suggestion: Default log: `t`, `changed`, `window`, `screen` (already
  filtered), `fold` of `raw`, `out` only when `changed`, boolean
  `ident_shaped`. Keep full `raw`/`out` behind an explicit
  `take_log_transcripts = true` in `refine.toml`, default false. Rotate
  by age **and** bytes. Define `ok_lex` or drop it. Reuse
  `atomic_write_text` / append-with-0600; do not copy the cache’s
  non-atomic `os.open` (`:1290-1292`).
- Status: open

### Issue 8 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:436`;
  `scripts/voxtype-prism-settings:159-161`;
  `~/.config/voxtype/config.toml:91-96`
- Description: `voxtype-refine harvest-evals` is not in the current CLI
  (`scripts/voxtype-refine:2168-2178`), and whichever copy grows it is
  not necessarily the live hook.

  Live dictation runs
  `~/.config/omarchy/plugins/io.github.jonhenshaw.voxtype-prism/scripts/voxtype-refine`.
  The work-repo trampoline is a second file. They are identical **today**;
  workbench save rewrites the plugin path, not the trampoline. Auto-accept
  that writes `tests/fixtures/refinement-eval.json` relative to the script
  would write into the plugin tree if invoked as the live binary, or into
  the work repo if invoked from HEAD. Two corpora, or a plugin dirty tree
  that Omarchy reloads (`scripts/voxtype-prism-settings:32-33` already
  warns about plugin-tree writes causing reload loops).

- Suggestion: Take-log writes from whichever child ran (XDG path, fine).
  `harvest-evals` is a work-repo-only command that reads XDG and writes
  the inbox next to `tests/fixtures/`. Document that live plugin sync is
  required for P1 fields to exist. Do not auto-write the plugin checkout.
- Status: open

### Issue 9 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:332`;
  `tests/run_refinement_eval.py:167`;
  `experiments/README.md:103-125`
- Description: Exact-match scoring and auto-minted punctuation/casing
  will disagree.

  Product identifier cases already bake sentence case + final period so
  the harness scores the identifier, not polish
  (`experiments/README.md:123-125`). Factory B using live `raw` as
  `transcript` keeps ASR capitalization (`Screen code spoken case name.`).
  Grok often emits `Screen_code_spoken_case_name.` or keeps the words and
  adds a period. `actual == expected` fails. The plan says most identifier
  evals should call `apply_lexical_hints` not Grok (`:344`), but P5 still
  auto-appends the same JSON the live harness reads.

- Suggestion: Minted joiner cases go to a separate fixture or a
  `"mode": "lexical"` field the live harness skips. Live corpus stays
  hand-shaped `screen_code_*` with the crowded list.
- Status: open

### Issue 10 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:333`
- Description: Factory C (“wrong” chord; next dictation or next typed
  replacement in the same window is `expected`) has no observer.

  Refine sees stdin + `VOXTYPE_CONTEXT` (prior take, 60s) + optional
  screen terms. It does not see ydotool/paste edits, clipboard (v1
  non-goal, `docs/on-screen-context-plan.md:197-198`), or AT-SPI
  (Ghostty has no text tree;
  `docs/on-screen-context-plan-review.md:115-119`). “Next typed
  replacement in the same window” is a new accessibility/clipboard
  adapter. A chord that only marks “the next take’s `raw` is expected”
  is implementable in the take log; the typed-replacement half is not.

- Suggestion: C is a one-bit flag in the take log: next refine record
  copies `raw`→`expected` into the **inbox**, never git. Drop “typed
  replacement” or schedule it with AT-SPI v1.5.
- Status: open

### Issue 11 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:372-384`
- Description: AT-SPI and tmux adapters are listed as “next” without
  restating the Ghostty ceiling.

  Typical dictation target on this machine is Ghostty (agent TUIs).
  Ghostty 1.3 Linux has no AT-SPI text path
  (`docs/on-screen-context-plan-review.md:115-119`). Tmux scrollback
  “only when we can prove the pane” is unproven for Ghostty+tmux: window
  title may not include pane id; `stableId` is the Hyprland toplevel,
  not a tty. Shipping either as v1 will return `[]` for the actual
  workload, same as AT-SPI-first was rejected for v1.

- Suggestion: Keep both behind `ScreenTextSource`, v1.5+, fail-closed.
  Do not market them as the scrolled-off-identifier fix. Session harvest
  (offline) is the adapter that actually sees off-screen identifiers in
  agent TUIs.
- Status: open

### Issue 12 -- Severity: suggestion

- File: `docs/lexicon-evals-design.html:400`, `:440-443`;
  `SettingsPanel.qml:693-702`, `:1029-1096`
- Description: P6 confirm-to-pin has no path from the post-process child
  to the workbench.

  QML is presentation-only (`AGENTS.md:3-4`, `ARCHITECTURE.md:78-80`).
  The workbench can edit the dictionary file through
  `voxtype-prism-settings` apply; it has no pin prompt today (dictionary
  page is a textarea + format guide). Refine cannot summon the panel.
  Counting “three successful joins” needs the take log (P1) plus a
  pending-pin file the workbench snapshots. A notification from the
  helper would be a new UX surface. Default-no is correct.

- Suggestion: Defer P6 until P1 exists. Store pin candidates in XDG
  (term, count, last fold). Workbench snapshot grows an optional list;
  QML shows “pin `apply_lexical_hints`?” on the dictionary page when
  summoned. No dbus from refine. Never write the dictionary from
  `refine_text()`.
- Status: open

### Issue 13 -- Severity: nit

- File: `docs/lexicon-evals-design.html:276`, `:301-315`
- Description: The lede oversells “evals that write themselves” and “a
  lexicon that learns from use.”

  Learning, in the body, is: ephemeral 5-minute cache, optional
  confirm-to-pin, and minted **evals**. That is not a lexicon that
  learns. Automatic evals still require `harvest-evals` to run, a human
  to commit, and filters that (Issue 2) cannot be complete. The filmstrip
  “Keep / git only if clean” is the honest picture; the h1 is not.

- Suggestion: Title the spec as take-log + identifier eval harvest +
  recency cache. Keep “never auto-write the dictionary” in the h1.
- Status: open

### Issue 14 -- Severity: nit

- File: `docs/lexicon-evals-design.html:323`; `scripts/voxtype-refine:2168-2178`
- Description: Sample jsonl field `ok_lex` and subcommand
  `harvest-evals` are unspecified in P1/P5 tests. P1 tests name tempfile
  via env, 0600, and “secrets already stripped by extract_spellings stay
  stripped” — the last is tautological if `screen` is the already-filtered
  list, and false if P1 logs `raw`.
- Suggestion: Specify the record schema in P1. Test that `raw` is omitted
  or redacted under default config (Issue 7).
- Status: open

## Reconciliation with on-screen-context-plan.md

| Topic | Relation |
|---|---|
| Module, JSON field, fail-closed OCR, QML boolean, pixels local, dictionary untouched | **Extends.** Do not reopen. |
| Refine-time capture as the v1 seam | **Contradicted** by P2. The previous review **accepted** refine-time and **rejected** recording-start + cache file (`on-screen-context-plan-review.md:203`, `:30`; plan `:99`). P2 must be an explicit amendment, not a footnote “without stealing `pre_recording_command`.” |
| `pre_recording_command` | Still reserved for compositor submaps. Voxtype 1.0.1 hid it from `config schema` but `voxtype setup compositor` still emits it. Do not chain. |
| Continuous capture while recording | Still a non-goal (`on-screen-context-plan.md:199`). One-shot at hotkey-down is not continuous; it **is** still a cache file. Name that in the amendment. |
| Learning screen terms into the dictionary | v1 non-goal (`:196`). P6 confirm-to-pin is a valid v1.5 amendment if it is never silent. |
| Recency / other windows | Not in the v1 plan. The 5-minute cache already shipped as a helper delta. P3 must say recency is **joiner-only** or it contradicts “never insert unspoken terms” (`DEFAULT_SYSTEM` + Juniper eval). |
| Session / git harvest | New adapter. Allowed as `ScreenTextSource` **if** it is token-only, cwd-resolved, offline, and not dumped into Grok. |
| Eval phase | v1 plan phase 5 is a **hand-authored** adversarial corpus (`on-screen-context-plan.md:173-175`). Auto-append from live takes contradicts `experiments/README.md` personal-transcript rule. Inbox-only harvest extends phase 5; auto-git does not. |
| ASR `initial_prompt` / `[text].replacements` | Still rejected. Unchanged. |
| AT-SPI | Still v1.5 because Ghostty. HTML is honest (“often will not”); do not promote. |
| Append OCR to dictionary / dump OCR into `context_for_disambiguation_only` / vision LLM / QML grab | Still rejected. P6 and P1 must not back-door them. |

Required amendments to `on-screen-context-plan.md` before implementing
P2/P3/P5-auto-git: capture timing, cache-file policy, recency vs provider
payload, eval promotion rules, dictionary pin.

## Eval loop

Is it actually automatic? **No.** A human still has to:

1. Run `harvest-evals` (nightly/on-demand — not on every take unless Issue 5
   is ignored).
2. Open the inbox for anything that is not a clean spoken-split identifier.
3. `git add` / commit the product fixture if auto-accept is allowed to
   touch it (plugin marketplace repo, not a private notebook).
4. Optionally press factory C’s chord.
5. Keep the plugin copy of the helper in sync so live takes actually
   contain the fields harvest expects (Issue 8).
6. Confirm dictionary pins (P6) in the workbench.

What can run unattended: P1 append; factory A **unit** tests of
`apply_lexical_hints` against harvested tokens; factory B inbox rows.

Failure modes of auto-accept (Issue 2 + 3 + 9):

- Live `raw` with a period / Title Case becomes a Grok exact-match landmine.
- Invented snake_case expected vs camelCase on screen.
- Session-mined `AWS_*` / `sk-` / project codenames / usernames that pass
  “looks like a code token.”
- Crowded-list invariant broken because live OCR dump is used as
  `on_screen_spellings`.
- Duplicate names (`screen_code_spoken_case_name` already exists,
  `tests/fixtures/refinement-eval.json:486-511`).
- Plugin-tree writes reload Omarchy.

The friction the user wanted to avoid — pasting JSON — is real. The
replacement is an **inbox**, not a self-committing corpus. Factory A from
`git ls-files` basenames + known session layouts, emitting synthetic
spoken splits, is the actually frictionless path and does not need the
take log.

## Recommended implementation order

Do not write code in this review. If the plan is revised:

1. **P1 take log** — XDG jsonl, 0600, env-overridable path, default
   **without** full transcripts (Issue 7). Tests only.
2. **Joiner unit harvest (factory A)** — offline, work-repo command,
   `git ls-files` of an explicit root + allowlisted session jsonl,
   synthetic splits, write **inbox**. No provider, no git mutate.
3. **Split recency from provider payload** (Issue 4) — current 5-minute
   cache already helps scrolled identifiers for the joiner
   (`tests/test_refine.py:1560-1583`). Stop sending the bag to Grok.
   That is the cheap “tiny / scrolled window” fix without P2.
4. **Factory B inbox only** — requires P1; never auto-accept; expected
   must be an on-screen token (Issue 3).
5. **P2** only after Issue 1’s amendment (state watcher + PNG lifetime)
   and Issue 6’s deadline. Not before 1–4.
6. **P4 in refine_text** — do not. Keep harvest offline.
7. **P6** last, workbench snapshot + confirm, no silent write.

P5 as specified (auto-accept into `refinement-eval.json`) should not ship.
P2 as specified (Hyprland hook / helper Voxtype can call, no
`pre_recording_command`) should not ship.

Does not implement.
