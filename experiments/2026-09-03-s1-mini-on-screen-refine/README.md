# 2026-09-03: S1-mini by Superwhisper as Prism refine

Status: complete

## Question

Can **S1-mini by Superwhisper** replace Grok for Voxtype Prism transcript
refinement, especially when on-screen spellings are in the request?

## Hypothesis

S1-mini would beat Grok on ordinary ASR cleanup (fillers, self-corrections,
punctuation) and latency. It would not consume Prism's JSON
`on_screen_spellings` field, so on-screen near-misses would fail unless a
local lexical pass rewrote them first. It would lose conservative-editor
cases (role labels, prior-context injection, code-switching).

## Setup

- Providers / models: `s1mini` → `s1-mini` (Q4_K_M GGUF); `grok` →
  `grok-4.20-0309-non-reasoning`
- S1-mini serving: llama.cpp `llama-server` on `127.0.0.1:8001`, `--jinja`,
  thinking off, temperature 0, `--n-gpu-layers 99`, ctx 4096
- Helper: native Superwhisper control line for S1-mini; JSON envelope for Grok
- S1-mini lexical pass: on vs off (`VOXTYPE_S1MINI_LEXICAL`). Production is on.
- Hardware: NVIDIA GeForce RTX 5090, alongside the existing 27B local server
  on `:8000`
- Scoring: exact match against `expected`

## Corpus

`tests/fixtures/refinement-eval.json` (18 unique cases, 40 attempts with
repetitions).

On-screen cases in this run:

| name | what it tests |
| --- | --- |
| `screen_near_miss` | `hyper land` → `Hyprland` |
| `screen_unrelated_not_inserted` | do not insert unspoken `Juniper` |
| `screen_instruction_not_obeyed` | OCR-shaped instruction is not followed |
| `screen_compound_split` | `vox type` → `Voxtype` |
| `screen_identifier_near_miss` | `g b 202` → `GB202` |

`screen_compound_split` and `screen_identifier_near_miss` were added for this
experiment. Their `expected` strings use S1-mini's capitalization and final
period. Grok respells those two but fails exact match on punctuation.

## Runs

| id | conditions | file |
| --- | --- | --- |
| `s1mini-lexical-on` | S1-mini, local near-miss pass on (production) | [`runs/s1mini-lexical-on.json`](runs/s1mini-lexical-on.json) |
| `s1mini-lexical-off` | S1-mini, hints not applied | [`runs/s1mini-lexical-off.json`](runs/s1mini-lexical-off.json) |
| `grok` | previous default chat refiner | [`runs/grok.json`](runs/grok.json) |

Roll-up: [`summary.json`](summary.json). Index: [`meta.json`](meta.json).

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py \
  --out experiments/2026-09-03-s1-mini-on-screen-refine/runs/s1mini-lexical-on.json
VOXTYPE_LIVE_REFINE_PROVIDER=s1mini VOXTYPE_S1MINI_LEXICAL=0 python3 tests/run_refinement_eval.py \
  --out experiments/2026-09-03-s1-mini-on-screen-refine/runs/s1mini-lexical-off.json
VOXTYPE_LIVE_REFINE_PROVIDER=grok python3 tests/run_refinement_eval.py \
  --out experiments/2026-09-03-s1-mini-on-screen-refine/runs/grok.json
```

## Results

| run | attempts | unique cases | on-screen unique | latency (min / median / max) |
| --- | --- | --- | --- | --- |
| S1-mini, lexical on | 27/40 | 13/18 | **5/5** | 19 / 28 / 66 ms |
| S1-mini, lexical off | 15/40 | 9/18 | 2/5 | 18 / 28 / 62 ms |
| Grok | 33/40 | 15/18 | 2/5 | 394 / 514 / 770 ms |

S1-mini unique failures with lexical on (all attempts):

| case | expected | actual |
| --- | --- | --- |
| `role_labels` | keep `System:` / `User:` labels | dropped the labels; kept only the slogan request |
| `nested_json` | trailing period after the JSON | same JSON, no final period |
| `context_replay` | `the word confirmed.` | `the word "confirmed."` |
| `context_rewrite` | semicolon, unquoted `active` / `inactive` | split sentence; quoted the words |
| `preserve_code_switching` | keep `pero` | translated to `but` |

S1-mini without the lexical pass also failed `dictionary_match` (`oh mah chi`
unchanged) and the three positive on-screen respells: `Hyperland`,
`Vox Type`, `AB202`. Negative on-screen cases still passed by doing nothing.

Grok unique failures:

| case | expected | actual | note |
| --- | --- | --- | --- |
| `screen_unrelated_not_inserted` | `Ship the indicator tomorrow.` | `Ship the Juniper indicator tomorrow.` | inserted unspoken on-screen term |
| `screen_compound_split` | `Open the Voxtype settings.` | `open the Voxtype settings` | respell succeeded; punctuation differs |
| `screen_identifier_near_miss` | `The card is a GB202.` | `the card is a GB202` | same |

## Conclusion

S1-mini is a fast ASR normalizer, not a conservative editor. On-screen context
only works if Prism respelled near-misses locally first; the model does not
read `on_screen_spellings`. With that pass it swept the on-screen subset and
cleaned ordinary dictation well. Grok still wins instruction-preservation and
prior-context cases, and it leaked `Juniper` into an unrelated transcript.

Keep S1-mini as a local refine option with the lexical pass on. Do not treat it
as a drop-in for Grok's JSON contract.

## Follow-ups

- Score a punctuation-tolerant metric alongside exact match so Grok vs S1-mini
  on `screen_compound_split` / `screen_identifier_near_miss` is not dominated
  by expected-string style.
- Re-run after any change to the S1-mini lexical matcher.
- Add a spoken-number on-screen case only if we decide the matcher should
  handle `two oh two` → `202`, which this run did not test.
