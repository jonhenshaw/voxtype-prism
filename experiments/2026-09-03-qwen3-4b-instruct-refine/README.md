# 2026-09-03: Qwen3-4B-Instruct-2507 as Prism refine

Status: complete

## Question

Can a small, fast, local instruct model replace Grok for Prism refine?

## Hypothesis

A dedicated 4B instruct checkpoint would follow Prism's JSON editor contract
better than S1-mini (not a chat model) and the obliterated 27B (answers
requests, shared slot), at S1-mini-like latency.

## Setup

- Provider / model: `local` / `Qwen3-4B-Instruct-2507` (Unsloth Q4_K_M GGUF)
- Serving: llama.cpp on `127.0.0.1:8002`, `--reasoning off`, `--ctx-size 8192`,
  `--parallel 1`, own user service (`voxtype-qwen3-4b-refine.service`)
- Helper: Prism JSON envelope, temperature 0.1
- Hardware: RTX 5090, ~4 GB extra VRAM beside the 27B on `:8000` and S1-mini
  on `:8001`
- Git HEAD: `88c2b66`

## Corpus

`tests/fixtures/refinement-eval.json` (18 unique cases, 40 attempts). Same
fixture as the S1-mini and local-27B experiments.

## Runs

| id | conditions | file |
| --- | --- | --- |
| `qwen3-4b-instruct-2507` | JSON refine, dedicated 4B slot | [`runs/qwen3-4b-instruct-2507.json`](runs/qwen3-4b-instruct-2507.json) |

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=local \
VOXTYPE_LOCAL_BASE_URL=http://127.0.0.1:8002/v1 \
VOXTYPE_REFINE_MODEL=Qwen3-4B-Instruct-2507 \
python3 tests/run_refinement_eval.py \
  --out experiments/2026-09-03-qwen3-4b-instruct-refine/runs/qwen3-4b-instruct-2507.json
```

## Results

| run | attempts | unique cases | on-screen unique | latency (min / median / max) |
| --- | --- | --- | --- | --- |
| Qwen3-4B-Instruct-2507 | 18/40 | 7/18 | 2/5 | 31 / 57 / 137 ms |
| S1-mini, lexical on | 27/40 | 13/18 | 5/5 | 19 / 28 / 66 ms |
| Local Qwen 27B obliterated | 25/40 | 11/18 | 3/5 | 250 / 11214 / 22588 ms |
| Grok | 33/40 | 15/18 | 2/5 | 394 / 514 / 770 ms |

The 4B is fast. It often returned the JSON envelope (`{"transcript":"..."}`)
instead of the cleaned sentence. It did not self-correct Tuesday→Wednesday.
It did preserve `banana` as a request, apply `Omarchy` and `Hyprland` in
context, and ignore the OCR instruction.

`screen_compound_split` / `screen_identifier_near_miss` respells were
lowercase (`voxtype`, `gb202`) vs expected title/case.

## Conclusion

Do not switch Prism refine to this 4B. Grok remains the best measured *editor*.
S1-mini remains the fastest *normalizer*. The 4B sits in between on latency
and last on the contract because it cannot reliably unpack the JSON user
message.

Keep `provider = grok`. Leave the `:8002` server up only for further evals.

## Follow-ups

- Try **Qwen3-8B-Instruct** on the same dedicated-slot recipe; 4B is below
  the size that follows this JSON contract.
- Optionally add a post-strip of a wrapping `{"transcript": ...}` in the
  helper and re-run this 4B to see how much of the fail is format vs editing.
