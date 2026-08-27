from __future__ import annotations

import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-refine"
LOADER = SourceFileLoader("voxtype_refine", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_refine", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["voxtype_refine"] = MODULE
SPEC.loader.exec_module(MODULE)


class RefineHelperTests(unittest.TestCase):
    def test_default_provider_is_grok(self) -> None:
        self.assertEqual(MODULE.DEFAULT_PROVIDER, "grok")
        self.assertEqual(MODULE.PROVIDERS["grok"].model, "grok-4.20-0309-non-reasoning")
        self.assertEqual(MODULE.PROVIDERS["openai"].model, "gpt-5.3-codex-spark")


    def test_parse_and_round_trip_refine_toml(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine.toml"
            MODULE.write_refine_config(path, "anthropic")
            provider, model = MODULE.load_selection(path)
            self.assertEqual(provider.id, "anthropic")
            self.assertEqual(model, "claude-haiku-4-5")

    def test_unknown_provider_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine.toml"
            path.write_text('provider = "nope"\n', encoding="utf-8")
            with self.assertRaises(RuntimeError):
                MODULE.load_selection(path)

    def test_openai_and_anthropic_extractors(self) -> None:
        openai = MODULE.openai_message_text(
            {"choices": [{"message": {"content": "  Hello world.  "}}]}
        )
        anthropic = MODULE.anthropic_message_text(
            {"content": [{"type": "text", "text": "Hello "}, {"type": "text", "text": "world."}]}
        )
        self.assertEqual(openai, "Hello world.")
        self.assertEqual(anthropic, "Hello world.")

    def test_codex_sse_collects_output_text(self) -> None:
        raw = (
            b"data: {\"type\":\"response.created\"}\n\n"
            b"data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello \"}\n\n"
            b"data: {\"type\":\"response.output_text.delta\",\"delta\":\"world.\"}\n\n"
            b"data: {\"type\":\"response.completed\"}\n\n"
        )
        self.assertEqual(MODULE.collect_codex_sse(raw), "Hello world.")

    def test_think_tags_are_stripped(self) -> None:
        self.assertEqual(MODULE.strip_output("<think>nope</think>\nReady."), "Ready.")

    def test_prompt_file_overrides_default(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine-prompt.md"
            path.write_text("Be terse.\n", encoding="utf-8")
            self.assertEqual(MODULE.load_system_prompt(path), "Be terse.")

    def test_missing_or_empty_prompt_uses_default(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.md"
            empty = Path(directory) / "empty.md"
            empty.write_text("   \n", encoding="utf-8")
            self.assertEqual(MODULE.load_system_prompt(missing), MODULE.DEFAULT_SYSTEM)
            self.assertEqual(MODULE.load_system_prompt(empty), MODULE.DEFAULT_SYSTEM)

    def test_ensure_prompt_file_writes_default_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine-prompt.md"
            created = MODULE.ensure_prompt_file(path)
            self.assertEqual(created.read_text(encoding="utf-8").strip(), MODULE.DEFAULT_SYSTEM.strip())
            created.write_text("Custom.\n", encoding="utf-8")
            MODULE.ensure_prompt_file(path)
            self.assertEqual(path.read_text(encoding="utf-8"), "Custom.\n")

    def test_missing_dictionary_leaves_prompt_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.md"
            self.assertEqual(MODULE.load_dictionary(missing), "")
            self.assertEqual(MODULE.compose_system_prompt("Be terse.", ""), "Be terse.")

    def test_dictionary_appends_after_stripping_comments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine-dictionary.md"
            path.write_text("# ignore\n\nOmarchy\n  hypr land → Hyprland  \n", encoding="utf-8")
            self.assertEqual(MODULE.load_dictionary(path), "Omarchy\nhypr land → Hyprland")
            assembled = MODULE.compose_system_prompt("Be terse.", MODULE.load_dictionary(path))
            self.assertEqual(
                assembled,
                "Be terse.\n\nPreferred spellings and proper nouns:\nOmarchy\nhypr land → Hyprland",
            )

    def test_ensure_dictionary_file_writes_stub_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine-dictionary.md"
            created = MODULE.ensure_dictionary_file(path)
            self.assertTrue(created.read_text(encoding="utf-8").startswith("# Custom dictionary"))
            created.write_text("Voxtype\n", encoding="utf-8")
            MODULE.ensure_dictionary_file(path)
            self.assertEqual(path.read_text(encoding="utf-8"), "Voxtype\n")




if __name__ == "__main__":
    unittest.main()
