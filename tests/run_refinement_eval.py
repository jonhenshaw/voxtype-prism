#!/usr/bin/python3
"""Run the Prism refinement corpus against a live provider and print a table.

This is the measurement harness for swapping refine models. Exact-match pass
or fail is recorded for every case, including on-screen context cases, and the
run continues after failures. Archive the JSON under experiments/ (see
experiments/README.md).

  VOXTYPE_LIVE_REFINE_PROVIDER=s1mini python3 tests/run_refinement_eval.py
  VOXTYPE_LIVE_REFINE_PROVIDER=grok python3 tests/run_refinement_eval.py
  VOXTYPE_LIVE_REFINE_PROVIDER=grok python3 tests/run_refinement_eval.py --only 'screen_code_*'
  VOXTYPE_LIVE_REFINE_PROVIDER=s1mini VOXTYPE_S1MINI_LEXICAL=0 python3 tests/run_refinement_eval.py \
    --out experiments/2026-09-03-s1-mini-on-screen-refine/runs/s1mini-lexical-off.json
"""

from __future__ import annotations

import argparse
import fnmatch
import inspect
import json
import os
import subprocess
import sys
import time
from dataclasses import replace
from datetime import datetime, timezone
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "voxtype-refine"
CASES_PATH = Path(__file__).parent / "fixtures" / "refinement-eval.json"

LOADER = SourceFileLoader("voxtype_refine_eval_runner", str(SCRIPT))
SPEC = spec_from_loader("voxtype_refine_eval_runner", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = module_from_spec(SPEC)
sys.modules["voxtype_refine_eval_runner"] = MODULE
SPEC.loader.exec_module(MODULE)


def load_cases(only: str = "") -> list[dict]:
    cases = json.loads(CASES_PATH.read_text(encoding="utf-8"))
    patterns = [item.strip() for item in only.split(",") if item.strip()]
    if not patterns:
        return cases
    selected = [
        case
        for case in cases
        if any(fnmatch.fnmatchcase(case["name"], pattern) for pattern in patterns)
    ]
    if not selected:
        names = ", ".join(case["name"] for case in cases)
        raise SystemExit(f"no cases matched {only!r}; known names: {names}")
    return selected


def case_tags(case: dict) -> str:
    tags = []
    if case.get("on_screen_spellings"):
        tags.append("screen")
    if case.get("dictionary"):
        tags.append("dictionary")
    if case.get("context"):
        tags.append("context")
    return ",".join(tags) or "cleanup"


def git_head() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def apply_base_url(provider):
    if provider.id == "local":
        base_url = os.environ.get("VOXTYPE_LOCAL_BASE_URL", "").strip()
        if base_url:
            return replace(provider, base_url=base_url)
    if provider.id == "s1mini":
        base_url = os.environ.get("VOXTYPE_S1MINI_BASE_URL", "").strip()
        if base_url:
            return replace(provider, base_url=base_url)
    return provider


def make_eval_request(module, provider, case: dict) -> tuple[str, str]:
    transcript = case["transcript"]
    context = case.get("context", "")
    dictionary = "\n".join(case.get("dictionary", []))
    on_screen = case.get("on_screen_spellings")
    preference = case.get("preference", module.DEFAULT_SYSTEM)
    builder = getattr(module, "build_provider_request", None)
    if callable(builder):
        return builder(
            provider,
            transcript,
            context,
            dictionary,
            on_screen_spellings=on_screen,
            system_prompt=preference,
        )
    kwargs = {}
    if "on_screen_spellings" in inspect.signature(module.build_refinement_input).parameters:
        kwargs["on_screen_spellings"] = on_screen
    user = module.build_refinement_input(transcript, context, dictionary, **kwargs)
    return user, module.compose_system_prompt(preference)


def unique_case_stats(rows: list[dict]) -> dict[str, dict[str, int]]:
    by_name: dict[str, list[dict]] = {}
    for row in rows:
        by_name.setdefault(row["name"], []).append(row)

    def score(selected: dict[str, list[dict]]) -> dict[str, int]:
        passed = sum(1 for group in selected.values() if group and all(item["ok"] for item in group))
        return {"passed": passed, "total": len(selected)}

    screen = {
        name: group
        for name, group in by_name.items()
        if any("screen" in item["tags"] for item in group)
    }
    return {"all": score(by_name), "screen": score(screen)}


def run(out_path: str = "", only: str = "") -> int:
    provider_id = os.environ.get("VOXTYPE_LIVE_REFINE_PROVIDER", "").strip().lower()
    if not provider_id:
        print("set VOXTYPE_LIVE_REFINE_PROVIDER to grok, anthropic, openai, local, or s1mini", file=sys.stderr)
        return 2
    if provider_id not in MODULE.PROVIDERS:
        print(f"unknown provider {provider_id!r}", file=sys.stderr)
        return 2
    provider = apply_base_url(MODULE.PROVIDERS[provider_id])
    model = os.environ.get("VOXTYPE_REFINE_MODEL", "").strip() or provider.model
    cases = load_cases(only=only)
    rows = []
    passed = 0
    failed = 0
    for case in cases:
        repetitions = int(case.get("repetitions", 1))
        for attempt in range(1, repetitions + 1):
            user, system = make_eval_request(MODULE, provider, case)
            started = time.monotonic()
            error = ""
            actual = ""
            try:
                actual = MODULE.complete(provider, model, user, system)
                dictionary = "\n".join(case.get("dictionary", []))
                actual = MODULE.finish_refinement(
                    actual, dictionary, case.get("on_screen_spellings")
                )
            except Exception as exc:  # noqa: BLE001 — eval harness records provider errors
                error = f"{type(exc).__name__}: {exc}"
            elapsed_ms = round((time.monotonic() - started) * 1000)
            expected = case["expected"]
            ok = (not error) and actual == expected
            if ok:
                passed += 1
            else:
                failed += 1
            rows.append(
                {
                    "name": case["name"],
                    "attempt": attempt,
                    "tags": case_tags(case),
                    "ok": ok,
                    "elapsed_ms": elapsed_ms,
                    "expected": expected,
                    "actual": actual,
                    "error": error,
                    "user": user,
                }
            )

    unique = unique_case_stats(rows)
    lexical = None
    if hasattr(MODULE, "lexical_hints_enabled"):
        lexical = MODULE.lexical_hints_enabled()
    elif provider.id == "s1mini" and hasattr(MODULE, "s1mini_lexical_enabled"):
        lexical = MODULE.s1mini_lexical_enabled()
    print(f"provider={provider.id} model={model} base_url={provider.base_url}")
    if lexical is not None:
        print(f"lexical={'on' if lexical else 'off'}")
    print(f"passed={passed} failed={failed} total={passed + failed}")
    print(
        f"unique={unique['all']['passed']}/{unique['all']['total']} "
        f"screen_unique={unique['screen']['passed']}/{unique['screen']['total']}"
    )
    print("")
    print(f"{'case':<32} {'tag':<18} {'ms':>5} result")
    for row in rows:
        mark = "PASS" if row["ok"] else "FAIL"
        suffix = f"  {row['attempt']}" if any(
            other["name"] == row["name"] and other["attempt"] != row["attempt"] for other in rows
        ) else ""
        print(f"{row['name'] + suffix:<32} {row['tags']:<18} {row['elapsed_ms']:>5} {mark}")
        if not row["ok"]:
            if row["error"]:
                print(f"  error: {row['error']}")
            else:
                print(f"  expected: {row['expected']!r}")
                print(f"  actual:   {row['actual']!r}")

    screen_rows = [row for row in rows if "screen" in row["tags"]]
    if screen_rows:
        screen_pass = sum(1 for row in screen_rows if row["ok"])
        print("")
        print(f"on-screen cases: {screen_pass}/{len(screen_rows)} passed")

    out = out_path.strip() or os.environ.get("VOXTYPE_EVAL_JSON", "").strip()
    if out:
        payload = {
            "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "git_head": git_head(),
            "corpus": "tests/fixtures/refinement-eval.json",
            "provider": provider.id,
            "model": model,
            "base_url": provider.base_url,
            "lexical": lexical,
            "passed": passed,
            "failed": failed,
            "unique": unique,
            "rows": rows,
        }
        destination = Path(out)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {out}")
    return 0 if failed == 0 else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default="",
        help="write JSON results (otherwise VOXTYPE_EVAL_JSON, if set)",
    )
    parser.add_argument(
        "--only",
        default="",
        help="comma-separated case names or globs (e.g. screen_code_*)",
    )
    args = parser.parse_args(argv)
    return run(out_path=args.out, only=args.only)


if __name__ == "__main__":
    raise SystemExit(main())
