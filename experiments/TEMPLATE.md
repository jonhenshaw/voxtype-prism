# YYYY-MM-DD: short title

Status: planned | running | complete | abandoned

## Question

One sentence. The decision this measurement should inform.

## Hypothesis

What you expected before the runs.

## Setup

- Provider / model:
- Serving (endpoint, quant, thinking, temperature):
- Helper options (screen context, lexical pass, prompt file):
- Hardware:
- Git HEAD:

## Corpus

`tests/fixtures/refinement-eval.json`

Note any cases added for this experiment.

## Runs

| id | conditions | file |
| --- | --- | --- |
| | | `runs/…json` |

Commands:

```bash
VOXTYPE_LIVE_REFINE_PROVIDER=… python3 tests/run_refinement_eval.py \
  --out experiments/YYYY-MM-DD-slug/runs/condition.json
```

## Results

Attempt pass/fail, unique-case pass/fail, on-screen subset, latency.

Failures: case name, expected, actual, whether it is punctuation-only.

## Conclusion

What you will do with the refine stack as a result.

## Follow-ups

Next measurement only.
