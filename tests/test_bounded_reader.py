from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "voxtype-prism-read"
LOADER = SourceFileLoader("voxtype_prism_read", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_prism_read", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BoundedReaderTests(unittest.TestCase):
    def test_config_reports_disabled_without_exposing_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_text("[osd]\nenabled = false\nsecret = 'not emitted'\n", encoding="utf-8")
            self.assertEqual(MODULE.config_status(config), "stock-disabled")

    def test_config_preserves_stock_enabled_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_text('engine = "parakeet"\n', encoding="utf-8")
            self.assertEqual(MODULE.config_status(config), "stock-enabled")
            config.write_text(
                "[osd]  # visual feedback\nenabled = true  # stock\n",
                encoding="utf-8",
            )
            self.assertEqual(MODULE.config_status(config), "stock-enabled")

    def test_config_fails_closed_when_oversized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_bytes(b"x" * (MODULE.MAX_CONFIG_BYTES + 1))
            self.assertEqual(MODULE.config_status(config), "unavailable")

    def test_config_fails_closed_for_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.toml"
            config = root / "config.toml"
            target.write_text("[osd]\nenabled = false\n", encoding="utf-8")
            config.symlink_to(target)
            self.assertEqual(MODULE.config_status(config), "unavailable")

    def test_runtime_state_accepts_only_known_small_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            for value in MODULE.RUNTIME_STATES:
                state.write_text(value + "\n", encoding="utf-8")
                self.assertEqual(MODULE.runtime_status(state), value)
            state.write_text("recording\nforged-extra-data\n", encoding="utf-8")
            self.assertEqual(MODULE.runtime_status(state), "idle")

    def test_runtime_state_rejects_oversized_and_non_regular_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            state.write_bytes(b"r" * (MODULE.MAX_RUNTIME_STATE_BYTES + 1))
            self.assertEqual(MODULE.runtime_status(state), "idle")
            state.unlink()
            os.mkfifo(state)
            self.assertEqual(MODULE.runtime_status(state), "idle")

    def test_palette_emits_only_allowlisted_colors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            palette = Path(directory) / "colors.toml"
            palette.write_text(
                'accent = "#112233"\nsecret = "#445566"\nred = "#AABBCC"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE.palette_status(palette),
                '{"accent":"#112233","red":"#AABBCC"}',
            )

    def test_palette_rejects_oversized_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            palette = Path(directory) / "colors.toml"
            palette.write_bytes(b"x" * (MODULE.MAX_PALETTE_BYTES + 1))
            self.assertEqual(MODULE.palette_status(palette), "{}")

    def test_qml_never_collects_the_source_files(self) -> None:
        config_qml = (ROOT / "VoxtypeConfig.qml").read_text(encoding="utf-8")
        state_qml = (ROOT / "StateReader.qml").read_text(encoding="utf-8")
        palette_qml = (ROOT / "OmarchyPalette.qml").read_text(encoding="utf-8")
        boundary_qml = (ROOT / "BoundedValueReader.qml").read_text(encoding="utf-8")
        self.assertNotIn("FileView", config_qml)
        self.assertNotIn("FileView", state_qml)
        self.assertNotIn("FileView", palette_qml)
        self.assertIn("BoundedValueReader", config_qml)
        self.assertIn("BoundedValueReader", state_qml)
        self.assertIn("BoundedValueReader", palette_qml)
        self.assertIn("SplitParser", boundary_qml)
        self.assertIn("voxtype-prism-read", boundary_qml)

    def test_standard_install_wires_explicit_activation(self) -> None:
        activation_qml = (ROOT / "PrismActivation.qml").read_text(encoding="utf-8")
        service_qml = (ROOT / "Service.qml").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn('command: [root.helperPath, "setup"]', activation_qml)
        self.assertIn("onClicked: root.activate()", activation_qml)
        self.assertIn("PrismActivation {", service_qml)
        self.assertIn("requires no second\nterminal command", readme)


if __name__ == "__main__":
    unittest.main()
