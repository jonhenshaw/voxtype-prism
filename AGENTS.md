# Agents

QML is presentation-only. LLM refine is `scripts/voxtype-refine`, a Voxtype
post-process child, not an `omarchy-shell` path.

User-owned files (not in this repo):

- `~/.config/voxtype/refine.toml` — provider (`grok` default, `anthropic`, `openai`, `local`, `s1mini`)
- `~/.config/voxtype/refine-prompt.md` — system prompt; edit in place or `scripts/voxtype-refine edit-prompt`
- `~/.config/voxtype/refine-dictionary.md` — terms appended to the system prompt; `scripts/voxtype-refine edit-dictionary`


Credentials stay in `~/.omp/agent/agent.db`. `scripts/voxtype-prism-config` only
toggles `[osd] enabled`. Human-facing commands: README.md § LLM refine.

Refinement eval corpus: `tests/fixtures/refinement-eval.json`. Live measurement
harness: `tests/run_refinement_eval.py` (`--only 'screen_code_*'` for
session-mined identifier cases). Save provider/model trials under
`experiments/` using [`experiments/README.md`](experiments/README.md).

Live OCR tokens go in the provider JSON `on_screen_spellings`. The 5-minute
recency cache is joiner-only (`finish_refinement` / s1mini lexical), not Grok.

`scripts/voxtype-refine harvest-evals` writes `tests/fixtures/refinement-eval.inbox.json`
only; it never writes the product corpus. Take log:
`$XDG_STATE_HOME/voxtype/refine-takes.jsonl` (or `VOXTYPE_TAKE_LOG`). Default
records omit `raw`/`out` unless `VOXTYPE_TAKE_LOG_TRANSCRIPTS` is 1/true/yes.
