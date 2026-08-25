from __future__ import annotations

import importlib.util
import argparse
from importlib.machinery import SourceFileLoader
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-signal-config"
LOADER = SourceFileLoader("voxtype_signal_config", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_signal_config", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ConfigEditingTests(unittest.TestCase):
    def test_absent_osd_section_appends_one(self) -> None:
        original = 'engine = "parakeet"\n'
        changed = MODULE.set_osd_enabled(original, False)
        self.assertIn("[osd]\nenabled = false\n", changed)
        self.assertFalse(MODULE.read_osd_enabled(changed))

    def test_section_header_comment_is_supported(self) -> None:
        original = "[osd]  # visual feedback\nenabled = true\n"
        changed = MODULE.set_osd_enabled(original, False)
        self.assertEqual(changed, "[osd]  # visual feedback\nenabled = false\n")

    def test_only_osd_enabled_changes(self) -> None:
        original = "[meeting]\nenabled = true\n\n[osd]\nenabled = true\nmargin_px = 24\n"
        changed = MODULE.set_osd_enabled(original, False)
        self.assertIn("[meeting]\nenabled = true", changed)
        self.assertIn("[osd]\nenabled = false", changed)
        self.assertIn("margin_px = 24", changed)

    def test_comment_is_preserved(self) -> None:
        original = "[osd]\n  enabled = true  # stock visualizer\n"
        changed = MODULE.set_osd_enabled(original, False)
        self.assertEqual(changed, "[osd]\n  enabled = false  # stock visualizer\n")

    def test_restore_uses_recorded_original_value(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config.toml"
            state = root / "setup.json"
            config.write_text("[osd]\nenabled = true\n", encoding="utf-8")
            args = argparse.Namespace(config=str(config), state=str(state), no_restart=True)
            self.assertEqual(MODULE.setup(args), 0)
            self.assertFalse(MODULE.read_osd_enabled(config.read_text(encoding="utf-8")))
            self.assertEqual(MODULE.restore(args), 0)
            self.assertTrue(MODULE.read_osd_enabled(config.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
