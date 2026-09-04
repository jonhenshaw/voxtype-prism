# Experiments

Recorded trials against Prism's refinement corpus. The corpus is the product;
an experiment is one dated attempt to answer a question with that corpus.

## Where things live

| Path | Role |
| --- | --- |
| [`tests/fixtures/refinement-eval.json`](../tests/fixtures/refinement-eval.json) | Shared eval corpus. Add cases here, not inside an experiment folder. |
| [`tests/run_refinement_eval.py`](../tests/run_refinement_eval.py) | Live harness. Runs every case, continues after failures, writes JSON. |
| [`tests/test_refine_live.py`](../tests/test_refine_live.py) | Schema checks plus a strict exact-match live test (opt-in via env). |
| `experiments/YYYY-MM-DD-slug/` | One experiment: question, setup, runs, conclusion. |
| [`TEMPLATE.md`](TEMPLATE.md) | Copy this to `experiments/YYYY-MM-DD-slug/README.md`. |

Do not fork the corpus into an experiment directory. Point at the fixture
(and a git SHA if the fixture moved). Attach run JSON under that experiment.

## Start a new experiment

1. Copy the template:

   ```bash
   slug=2026-09-03-short-question
   mkdir -p experiments/$slug/runs
   cp experiments/TEMPLATE.md experiments/$slug/README.md
   ```

2. Fill `README.md` before you run, at least **Question**, **Hypothesis**, and
   **Setup**. Fill **Results** and **Conclusion** from the JSON, not from memory.

3. Create `meta.json` from the schema below.

4. Run the harness once per condition, writing into `runs/`:

   ```bash
   VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py \
     --out experiments/$slug/runs/s1mini.json
   ```

5. Commit the folder when the write-up names every run file and the conclusion
   is checkable against those files.

Directory name: `YYYY-MM-DD-slug`. Date is the day of the runs. Slug is
lowercase, hyphenated, and names the question (`s1-mini-on-screen-refine`),
not the outcome.

## Layout

```text
experiments/YYYY-MM-DD-slug/
  README.md      # human write-up (from TEMPLATE.md)
  meta.json      # machine-readable index
  runs/          # raw harness JSON, one file per condition
  summary.json   # optional roll-up of unique-case / latency stats
```

Optional: `notes.md` for dead ends that would clutter the summary. Do not add
screenshots, model weights, logs with credentials, or OhMyPi tokens.

## `meta.json`

```json
{
  "id": "2026-09-03-s1-mini-on-screen-refine",
  "date": "2026-09-03",
  "status": "complete",
  "question": "Can S1-mini by Superwhisper replace Grok for Prism refine, including on-screen spellings?",
  "corpus": "tests/fixtures/refinement-eval.json",
  "harness": "tests/run_refinement_eval.py",
  "git_head": "optional SHA at run time",
  "runs": [
    {
      "id": "s1mini-lexical-on",
      "file": "runs/s1mini-lexical-on.json",
      "provider": "s1mini",
      "model": "s1-mini",
      "conditions": {"lexical": true}
    }
  ]
}
```

`status` is `planned`, `running`, `complete`, or `abandoned`.

## README sections

Use the headings in [`TEMPLATE.md`](TEMPLATE.md). They are required, in that
order:

1. **Question** — one sentence. What decision does this inform?
2. **Hypothesis** — what you expected, before seeing the numbers.
3. **Setup** — provider, model, serving flags, hardware, helper options.
4. **Corpus** — path plus any fixture SHA or note if cases were added for this run.
5. **Runs** — table of condition → `runs/*.json`.
6. **Results** — attempt counts, unique-case counts, on-screen subset, latency.
   Quote failures with expected vs actual.
7. **Conclusion** — what you will do (ship, keep Grok, change the helper, add cases).
8. **Follow-ups** — next measurements, not a backlog of unrelated work.

Exact-match against `expected` is the default score. If a failure is only
punctuation, say so; do not silently treat it as a pass.

## Corpus rules

- New product invariants belong in `tests/fixtures/refinement-eval.json`.
- Give each case a stable `name`. Do not reuse names.
- Use `on_screen_spellings`, `dictionary`, and `context` only when that field
  is the thing under test.
- Set `repetitions` on flaky or adversarial cases. The harness counts each
  attempt; unique-case pass means every attempt passed.
- Keep `expected` conservative-editor output unless the experiment is
  explicitly scoring a normalizer. If you add normalizer-shaped expects,
  say that in the experiment README so Grok/S1-mini comparisons stay honest.

## What not to store

- API keys, OhMyPi database copies, Authorization headers
- Model weight files (record the Hub id and revision instead)
- Full llama.cpp logs
- Personal transcripts (the corpus is synthetic)

Run JSON from the harness includes the provider `user` payload. That is the
synthetic case text, not a credential.
