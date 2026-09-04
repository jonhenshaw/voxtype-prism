# 2026-09-03: session-mined code identifier evals

Status: complete

## Question

Do on-screen spellings catch real code identifiers (variables, types, files,
env vars) the way they appear in Claude Code / Hermes / Codex / Grok sessions,
without inserting unspoken siblings from a crowded window?

## Hypothesis

Grok would respell spoken near-misses to the on-screen identifier when the
folded form matches, and would leave sibling identifiers alone. A busy
18-term screen (the realistic OCR case) would be harder than the old
single-term Hyprland / GB202 fixtures.

## Setup

- Provider / model: `grok` / `grok-4.20-0309-non-reasoning`; `s1mini` / `s1-mini`
- Serving: xAI API; local llama-server `:8001` for S1-mini
- Helper options: Prism JSON `on_screen_spellings`; S1-mini lexical pass on
- Hardware: existing workstation GPU for S1-mini only
- Git HEAD: `4d0590a` plus uncommitted helper/eval work

Tokens were mined with `extract_spellings` from local session stores
(`~/.claude/projects`, `~/.hermes/state.db`, `~/.codex/sessions`,
`~/.grok/sessions`). Spoken transcripts are synthetic ASR splits of those
tokens. No personal session text is in the corpus.

## Corpus

`tests/fixtures/refinement-eval.json` cases named `screen_code_*` (13 unique,
19 attempts). Shared crowded screen:

`leagueId`, `playerId`, `accountId`, `canonicalPlayerId`, `schemaVersion`,
`accessibilityLabel`, `testID`, `SlotPicker`, `GlassCard`,
`ActivityIndicator`, `LeagueSwitcher`, `PlayerProfile`, `SettingsPanel.qml`,
`voxtype-refine`, `fourth-down-platform`, `FOURTH_DOWN_MODEL_BASE_URL`,
`created_at`, `collect_on_screen_spellings`.

Transcripts already have sentence casing and a final period so exact match
scores the identifier, not polish.

Ran with:

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=grok python3 tests/run_refinement_eval.py \
  --only 'screen_code_*' --out experiments/2026-09-03-code-identifier-evals/runs/grok.json
VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py \
  --only 'screen_code_*' --out experiments/2026-09-03-code-identifier-evals/runs/s1mini-lexical-on.json
```

## Runs

| id | conditions | file |
| --- | --- | --- |
| grok | production chat refine | `runs/grok.json` |
| s1mini-lexical-on | local lexical near-miss then S1-mini | `runs/s1mini-lexical-on.json` |

## Results

| condition | unique | attempts | median ms |
| --- | --- | --- | --- |
| grok | 8/13 | 14/19 | 513 |
| s1mini-lexical-on | 11/13 | 17/19 | 21 |

Grok **caught** camelCase `leagueId` / `testID`, snake `created_at`, env
`FOURTH_DOWN_MODEL_BASE_URL`, file `SettingsPanel.qml`, and both identifiers
in `rename leagueId to accountId`. It **did not insert** `ActivityIndicator`
for "indicator" or any crowded-screen term into "Ship it tomorrow."

Grok **missed**:

| case | expected | actual |
| --- | --- | --- |
| `screen_code_camel_canonical_player` (1/2) | `canonicalPlayerId` | `canonical player ID` |
| `screen_code_camel_accessibility` | `accessibilityLabel` | `accessibility label` |
| `screen_code_pascal_slot_picker` | `SlotPicker` | `slot picker` |
| `screen_code_snake_collect` | `collect_on_screen_spellings` | `collect on screen spellings` |
| `screen_code_kebab_repo` | `fourth-down-platform` | `fourth down platform` |

S1-mini plus the local lexical pass caught every identifier Grok missed,
including the `playerId` vs `canonicalPlayerId` suffix collision after the
helper started preferring longer exact folds. It then **undid** two hits:
`fourth-down-platform` → `fourth-down platform`, and
`FOURTH` → `4th` in the env var. Those are normalizer edits, not lexicon
misses.

## Conclusion

Keep Grok as production refine. These cases belong in the shared corpus:
they show Grok is conservative on PascalCase components, kebab repo names,
and long snake_case functions, and that a busy screen does **not** cause
unspoken-term insertion. Do not switch to S1-mini; it catches more
identifiers locally but then rewrites digits and hyphens.

The lexical overlap change (longer exact fold wins) is required for
`canonicalPlayerId` when `playerId` is also on screen. Unit tests cover
that without a live provider.

## Follow-ups

- Measure Grok again after any prompt change aimed at PascalCase / kebab /
  long snake_case joins.
- If a local lexical pass is ever applied *before* Grok, re-run this
  `--only 'screen_code_*'` slice; S1-mini shows the pass helps identifiers
  and can still be damaged by a later normalizer.
