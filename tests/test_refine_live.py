from __future__ import annotations

import importlib.util
import json
import os
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "voxtype-refine"
CASES_PATH = Path(__file__).parent / "fixtures" / "refinement-eval.json"
CASES = json.loads(CASES_PATH.read_text(encoding="utf-8"))
RUNNER_PATH = Path(__file__).parent / "run_refinement_eval.py"

LOADER = SourceFileLoader("voxtype_refine_live", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_refine_live", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["voxtype_refine_live"] = MODULE
SPEC.loader.exec_module(MODULE)

RUNNER_LOADER = SourceFileLoader("voxtype_refine_eval_runner_for_tests", str(RUNNER_PATH))
RUNNER_SPEC = importlib.util.spec_from_loader("voxtype_refine_eval_runner_for_tests", RUNNER_LOADER)
assert RUNNER_SPEC is not None and RUNNER_SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
sys.modules["voxtype_refine_eval_runner_for_tests"] = RUNNER
RUNNER_SPEC.loader.exec_module(RUNNER)


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
            if "on_screen_spellings" in case:
                self.assertIsInstance(case["on_screen_spellings"], list)
                self.assertTrue(all(isinstance(term, str) and term for term in case["on_screen_spellings"]))
                self.assertLessEqual(len(case["on_screen_spellings"]), 64)
                self.assertTrue(all(len(term) <= 128 for term in case["on_screen_spellings"]))
            if "repetitions" in case:
                self.assertIsInstance(case["repetitions"], int)
                self.assertGreaterEqual(case["repetitions"], 1)

    def test_screen_code_cases_use_crowded_session_identifiers(self) -> None:
        code_cases = [case for case in CASES if case["name"].startswith("screen_code_")]
        self.assertGreaterEqual(len(code_cases), 8)
        shared = [
            case
            for case in code_cases
            if case["name"]
            not in {"screen_code_spoken_eval_name", "screen_code_spoken_case_name"}
        ]
        screens = [tuple(case["on_screen_spellings"]) for case in shared]
        self.assertEqual(len(set(screens)), 1)
        screen = set(screens[0])
        for token in (
            "leagueId",
            "playerId",
            "canonicalPlayerId",
            "accessibilityLabel",
            "SlotPicker",
            "ActivityIndicator",
            "created_at",
            "collect_on_screen_spellings",
            "fourth-down-platform",
            "FOURTH_DOWN_MODEL_BASE_URL",
            "SettingsPanel.qml",
            "testID",
        ):
            self.assertIn(token, screen)
        hits = {case["name"]: case for case in code_cases}
        self.assertIn("leagueId", hits["screen_code_camel_league_id"]["expected"])
        self.assertIn("canonicalPlayerId", hits["screen_code_camel_canonical_player"]["expected"])
        self.assertNotIn("canonical playerId", hits["screen_code_camel_canonical_player"]["expected"])
        self.assertIn("leagueId", hits["screen_code_two_identifiers"]["expected"])
        self.assertIn("accountId", hits["screen_code_two_identifiers"]["expected"])
        self.assertNotIn("ActivityIndicator", hits["screen_code_prefix_not_expanded"]["expected"])
        for token in screen:
            self.assertNotIn(token, hits["screen_code_busy_unspoken"]["expected"])
        spoken = hits["screen_code_spoken_eval_name"]
        self.assertIn("`screen_identifier_near_miss`", spoken["expected"])
        self.assertIn("×3", spoken["expected"])
        self.assertIn("`screen_identifier_near_miss`", spoken["on_screen_spellings"])
        self.assertIn("×3", spoken["on_screen_spellings"])
        case_name = hits["screen_code_spoken_case_name"]
        self.assertEqual(case_name["expected"], "screen_code_spoken_case_name.")
        self.assertIn("screen_code_spoken_case_name", case_name["on_screen_spellings"])

    def test_eval_runner_only_filters_by_glob(self) -> None:
        selected = RUNNER.load_cases("screen_code_*")
        self.assertTrue(selected)
        self.assertTrue(all(case["name"].startswith("screen_code_") for case in selected))
        self.assertLess(len(selected), len(CASES))
        with self.assertRaises(SystemExit):
            RUNNER.load_cases("no_such_case")


@unittest.skipUnless(
    os.environ.get("VOXTYPE_LIVE_REFINE_PROVIDER"),
    "set VOXTYPE_LIVE_REFINE_PROVIDER to run provider-backed refinement evals",
)
class LiveRefinementContractTests(unittest.TestCase):
    def test_adversarial_corpus(self) -> None:
        provider_id = os.environ["VOXTYPE_LIVE_REFINE_PROVIDER"].strip().lower()
        self.assertIn(provider_id, MODULE.PROVIDERS)
        provider = RUNNER.apply_base_url(MODULE.PROVIDERS[provider_id])
        model = os.environ.get("VOXTYPE_REFINE_MODEL", "").strip() or provider.model
        for case in CASES:
            repetitions = case.get("repetitions", 1)
            self.assertIsInstance(repetitions, int)
            self.assertGreaterEqual(repetitions, 1)
            for attempt in range(1, repetitions + 1):
                with self.subTest(
                    case=case["name"], provider=provider_id, attempt=attempt
                ):
                    user, system = RUNNER.make_eval_request(MODULE, provider, case)
                    actual = MODULE.complete(provider, model, user, system)
                    dictionary = "\n".join(case.get("dictionary", []))
                    actual = MODULE.finish_refinement(
                        actual, dictionary, case.get("on_screen_spellings")
                    )
                    self.assertEqual(actual, case["expected"])


if __name__ == "__main__":
    unittest.main()
