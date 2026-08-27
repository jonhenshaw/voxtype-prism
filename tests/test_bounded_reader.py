from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "voxtype-prism-read"
LOADER = SourceFileLoader("voxtype_prism_read", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_prism_read", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BoundedReaderTests(unittest.TestCase):
    def write_prism_settings(self, root: Path, payload: object) -> Path:
        settings = root / "voxtype-prism" / "indicator.json"
        settings.parent.mkdir(parents=True)
        settings.write_text(json.dumps(payload), encoding="utf-8")
        return settings

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

    def test_prism_settings_emit_only_normalized_allowlisted_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_home = Path(directory)
            settings = self.write_prism_settings(
                config_home,
                {
                    "version": 1,
                    "preset": "bar-pulse",
                    "position": "top-center",
                    "scale": 1.25,
                    "motion": False,
                    "glow": 0.35,
                    "secret": "never emitted",
                },
            )
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config_home)}):
                normalized = json.loads(MODULE.prism_settings_status(settings))

            self.assertEqual(
                normalized,
                {
                    "styleId": "bar-pulse",
                    "position": "top-center",
                    "scaleFactor": 1.25,
                    "motionEnabled": False,
                    "glowIntensity": 0.35,
                },
            )

    def test_prism_settings_default_invalid_enums_and_cap_ranges(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_home = Path(directory)
            settings = self.write_prism_settings(
                config_home,
                {
                    "version": 1,
                    "preset": ["halo"],
                    "position": {"value": "top-center"},
                    "scale": 99,
                    "motion": "yes",
                    "glow": -12,
                },
            )
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config_home)}):
                normalized = json.loads(MODULE.prism_settings_status(settings))
                self.assertEqual(normalized["styleId"], "signal")
                self.assertEqual(normalized["position"], "bottom-center")
                self.assertEqual(normalized["scaleFactor"], 1.5)
                self.assertTrue(normalized["motionEnabled"])
                self.assertEqual(normalized["glowIntensity"], 0.0)

                settings.write_text(
                    json.dumps(
                        {
                            "version": 1,
                            "preset": "halo",
                            "position": "bottom-center",
                            "scale": -1,
                            "motion": True,
                            "glow": 50,
                        }
                    ),
                    encoding="utf-8",
                )
                normalized = json.loads(MODULE.prism_settings_status(settings))
                self.assertEqual(normalized["scaleFactor"], 0.75)
                self.assertEqual(normalized["glowIntensity"], 1.0)

    def test_prism_settings_fail_closed_for_wrong_path_symlink_and_oversize(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config_home = root / "config"
            expected = json.loads(MODULE.prism_defaults_status())
            settings = self.write_prism_settings(
                config_home,
                {
                    "version": 1,
                    "preset": "halo",
                    "position": "top-center",
                    "scale": 1.2,
                    "motion": False,
                    "glow": 0.8,
                },
            )
            other = root / "other.json"
            other.write_text(settings.read_text(encoding="utf-8"), encoding="utf-8")

            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config_home)}):
                self.assertEqual(json.loads(MODULE.prism_settings_status(other)), expected)

                target = root / "target.json"
                target.write_text(settings.read_text(encoding="utf-8"), encoding="utf-8")
                settings.unlink()
                settings.symlink_to(target)
                self.assertEqual(json.loads(MODULE.prism_settings_status(settings)), expected)

                settings.unlink()
                settings.write_bytes(b"x" * (MODULE.MAX_PRISM_SETTINGS_BYTES + 1))
                self.assertEqual(json.loads(MODULE.prism_settings_status(settings)), expected)

    def test_prism_settings_fail_closed_for_invalid_version_or_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_home = Path(directory)
            expected = json.loads(MODULE.prism_defaults_status())
            settings = self.write_prism_settings(config_home, {"version": 2, "preset": "halo"})
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config_home)}):
                self.assertEqual(json.loads(MODULE.prism_settings_status(settings)), expected)
                settings.write_text("[]", encoding="utf-8")
                self.assertEqual(json.loads(MODULE.prism_settings_status(settings)), expected)

    def test_qml_never_collects_the_source_files(self) -> None:
        config_qml = (ROOT / "VoxtypeConfig.qml").read_text(encoding="utf-8")
        state_qml = (ROOT / "StateReader.qml").read_text(encoding="utf-8")
        palette_qml = (ROOT / "OmarchyPalette.qml").read_text(encoding="utf-8")
        prism_qml = (ROOT / "IndicatorRuntimeConfig.qml").read_text(encoding="utf-8")
        boundary_qml = (ROOT / "BoundedValueReader.qml").read_text(encoding="utf-8")
        for path in ROOT.glob("*.qml"):
            self.assertNotIn("FileView", path.read_text(encoding="utf-8"), path.name)
        self.assertIn("BoundedValueReader", config_qml)
        self.assertIn("BoundedValueReader", state_qml)
        self.assertIn("BoundedValueReader", palette_qml)
        self.assertIn("BoundedValueReader", prism_qml)
        self.assertIn('mode: "prism-settings"', prism_qml)
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

    def test_workbench_manifest_launcher_and_shared_preview_are_wired(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        panel = (ROOT / "SettingsPanel.qml").read_text(encoding="utf-8")

        self.assertEqual(manifest["kinds"], ["service", "panel"])
        self.assertEqual(manifest["entryPoints"]["service"], "Service.qml")
        self.assertEqual(manifest["entryPoints"]["panel"], "SettingsPanel.qml")
        self.assertTrue(manifest["keepLoaded"])
        self.assertIn("LauncherManager", service)
        self.assertIn("VOXTYPE_PRISM_DISABLE_LAUNCHER", service)
        self.assertIn("function settings()", service)
        self.assertIn("FloatingWindow", panel)
        self.assertIn("IndicatorVisual", panel)
        self.assertNotIn("PanelWindow", panel)

    def test_motion_off_freezes_audio_driven_levels(self) -> None:
        controller = (ROOT / "IndicatorController.qml").read_text(encoding="utf-8")
        self.assertIn("if (!root.motionEnabled || !root.levelVisible) return", controller)
        self.assertIn("onMotionEnabledChanged", controller)
        self.assertIn("root.clearLevels()", controller)

    def test_workbench_keeps_reviewed_state_and_safety_contracts(self) -> None:
        panel = (ROOT / "SettingsPanel.qml").read_text(encoding="utf-8")
        backend = (ROOT / "SettingsBackend.qml").read_text(encoding="utf-8")
        editor = (ROOT / "PrismTextArea.qml").read_text(encoding="utf-8")

        self.assertIn('property string revision: ""', backend)
        self.assertIn("revisionConflictSnapshot", backend)
        self.assertIn("errorDetails.committed === true", backend)
        self.assertIn("savedRefine.modelOverride", panel)
        self.assertIn("function onClosing(closeEvent)", panel)
        self.assertIn("closeEvent.accepted = false", panel)
        self.assertIn("readonly property bool opened", panel)
        self.assertIn("if (window.visible && dirty)", panel)
        self.assertIn("Keep draft", panel)
        self.assertIn("Reload external", panel)
        self.assertIn("Ui.Toggle {", panel)
        self.assertIn("Quickshell.execDetached", panel)
        self.assertLess(panel.index("Quickshell.execDetached"), panel.index("shell.hide(pluginId)"))
        self.assertIn("maximumBytes: 4096", panel)
        self.assertIn("maximumBytes: 32768", panel)
        self.assertIn("byteCount", editor)


if __name__ == "__main__":
    unittest.main()
