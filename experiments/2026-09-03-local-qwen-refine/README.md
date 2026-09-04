# 2026-09-03: local Qwen 3.8 27B as Prism refine

Status: complete

## Question

Should Prism leave S1-mini and use the local Qwen 3.8 27B already served on
`:8000` as the refine model?

## Hypothesis

A 27B chat model would follow Prism's JSON editor contract better than
S1-mini, use on-screen spellings without a separate lexical pass, and keep
OCR terms on-box. The served build is an "obliterated" uncensored GGUF sharing
a 150k-context llama.cpp slot with other agents, so instruction-preservation
and latency were both risks.

## Setup

- Provider / model: `local` / `Qwen3.8-27B-OBLITERATED-GGUF`
- Serving: llama.cpp on `127.0.0.1:8000`, Q4_K_M, `--reasoning off`,
  `--ctx-size 150000`, `--parallel 1`
- Helper: Prism JSON envelope (`transcript`, dictionary, `on_screen_spellings`)
- Temperature: 0.1 (helper default for non-S1-mini)
- Hardware: RTX 5090, same box as S1-mini on `:8001`
- Git HEAD: `447825b`
- Contention: another agent was using this slot (`n_tokens_max` reached 94363
  during the run). Quality failures below are still model behavior; the
  11 s median is not a clean idle-latency number.

## Corpus

`tests/fixtures/refinement-eval.json` (18 unique cases, 40 attempts). Same
fixture as [`2026-09-03-s1-mini-on-screen-refine`](../2026-09-03-s1-mini-on-screen-refine/).

## Runs

| id | conditions | file |
| --- | --- | --- |
| `local-qwen-obliterated` | JSON refine, shared 27B slot | [`runs/local-qwen-obliterated.json`](runs/local-qwen-obliterated.json) |

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=local \
VOXTYPE_REFINE_MODEL=Qwen3.8-27B-OBLITERATED-GGUF \
python3 tests/run_refinement_eval.py \
  --out experiments/2026-09-03-local-qwen-refine/runs/local-qwen-obliterated.json
```

## Results

| run | attempts | unique cases | on-screen unique | latency (min / median / max) |
| --- | --- | --- | --- | --- |
| Local Qwen 27B obliterated | 25/40 | 11/18 | 3/5 | 250 / 11214 / 22588 ms |
| S1-mini, lexical on (prior) | 27/40 | 13/18 | 5/5 | 19 / 28 / 66 ms |
| Grok (prior) | 33/40 | 15/18 | 2/5 | 394 / 514 / 770 ms |

Unique failures:

| case | expected | actual |
| --- | --- | --- |
| `ordinary_cleanup` | `Send the report on Wednesday morning.` | `Send the report on Tuesday, not Wednesday morning.` |
| `exact_output_request` | keep the request as text | `banana` |
| `preserve_uncertainty` | keep `I think maybe…` | dropped `I think` |
| `code_question` | no extra markup | wrapped the command in backticks |
| `dictionary_match` | `I use Omarchy every day.` | `Omarchy` |
| `screen_near_miss` | `I use Hyprland every day.` | `Hyper Land` |
| `screen_compound_split` | `Open the Voxtype settings.` | `VoxType` / `Vox Type` |

It passed role labels, nested JSON, prior-context injection, and the two
negative on-screen cases. When it used a spelling hint, it often emitted the
term alone instead of editing the sentence. Self-correction chose the abandoned
value.

Later attempts dropped to 250–775 ms once the shared slot was idle, so the
11 s median is mostly queue/KV from the other agent, not decode of a short
refine.

## Conclusion

Do not point Prism refine at this local Qwen. It is a real LLM, but the
obliterated build answers requests instead of editing them, mishandles
self-correction, and shares a contended 150k-context slot.

Switch refine back to Grok (`grok-4.20-0309-non-reasoning`), keep
`screen_context = true`. A dedicated, non-obliterated local instruct model
would be a different experiment.

## Follow-ups

- Re-run this corpus on a non-obliterated Qwen 3.8 27B, idle slot, ctx sized
  for dictation rather than 150k agent sessions.
- Do not treat shared Local Studio `:8000` as a refine SLA until it has its
  own parallel slot or a separate server.
