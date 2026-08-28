from __future__ import annotations

import importlib.util
import json
import os
import sys
from dataclasses import replace
from importlib.machinery import SourceFileLoader
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "voxtype-refine"
CASES_PATH = Path(__file__).parent / "fixtures" / "refinement-eval.json"
CASES = json.loads(CASES_PATH.read_text(encoding="utf-8"))

LOADER = SourceFileLoader("voxtype_refine_live", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_refine_live", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["voxtype_refine_live"] = MODULE
SPEC.loader.exec_module(MODULE)


class RefinementEvalFixtureTests(unittest.TestCase):
    def test_cases_have_unique_names_and_required_text(self) -> None:
        self.assertIsInstance(CASES, list)
        self.assertGreaterEqual(len(CASES), 3)
        names = [case["name"] for case in CASES]
        self.assertEqual(len(names), len(set(names)))
        for case in CASES:
            self.assertIsInstance(case["transcript"], str)
            self.assertIsInstance(case["expected"], str)
            self.assertTrue(case["transcript"])
            self.assertTrue(case["expected"])
            if "context" in case:
                self.assertIsInstance(case["context"], str)
            if "preference" in case:
                self.assertIsInstance(case["preference"], str)
            if "dictionary" in case:
                self.assertIsInstance(case["dictionary"], list)
                self.assertTrue(all(isinstance(term, str) for term in case["dictionary"]))
            if "repetitions" in case:
                self.assertIsInstance(case["repetitions"], int)
                self.assertGreaterEqual(case["repetitions"], 1)


@unittest.skipUnless(
    os.environ.get("VOXTYPE_LIVE_REFINE_PROVIDER"),
    "set VOXTYPE_LIVE_REFINE_PROVIDER to run provider-backed refinement evals",
)
class LiveRefinementContractTests(unittest.TestCase):
    def test_adversarial_corpus(self) -> None:
        provider_id = os.environ["VOXTYPE_LIVE_REFINE_PROVIDER"].strip().lower()
        self.assertIn(provider_id, MODULE.PROVIDERS)
        provider = MODULE.PROVIDERS[provider_id]
        if provider.id == "local":
            base_url = os.environ.get("VOXTYPE_LOCAL_BASE_URL", "").strip()
            if base_url:
                provider = replace(provider, base_url=base_url)
        model = os.environ.get("VOXTYPE_REFINE_MODEL", "").strip() or provider.model
        for case in CASES:
            preference = case.get("preference", MODULE.DEFAULT_SYSTEM)
            system = MODULE.compose_system_prompt(preference)
            repetitions = case.get("repetitions", 1)
            self.assertIsInstance(repetitions, int)
            self.assertGreaterEqual(repetitions, 1)
            for attempt in range(1, repetitions + 1):
                with self.subTest(
                    case=case["name"], provider=provider_id, attempt=attempt
                ):
                    user = MODULE.build_refinement_input(
                        case["transcript"],
                        case.get("context", ""),
                        "\n".join(case.get("dictionary", [])),
                    )
                    actual = MODULE.complete(provider, model, user, system)
                    self.assertEqual(actual, case["expected"])


if __name__ == "__main__":
    unittest.main()
