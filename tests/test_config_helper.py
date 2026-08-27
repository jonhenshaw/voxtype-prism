from __future__ import annotations

import importlib.util
import argparse
from importlib.machinery import SourceFileLoader
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-prism-config"
LOADER = SourceFileLoader("voxtype_prism_config", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_prism_config", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ConfigEditingTests(unittest.TestCase):
    def test_pre_release_state_path_is_preserved_for_migration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            legacy = root / "voxtype-signal-osd" / "setup.json"
            legacy.parent.mkdir(parents=True)
            legacy.write_text("{}\n", encoding="utf-8")
            with patch.dict(os.environ, {"XDG_STATE_HOME": str(root)}):
                self.assertEqual(MODULE.existing_state_path(), legacy)

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

    def test_state_write_is_atomic_private_and_round_trips(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state" / "setup.json"
            payload = {
                "backup": "/tmp/config.toml.backup",
                "config": "/tmp/config.toml",
                "original_osd_enabled": True,
                "setup_at": "2026-08-26T12:00:00+00:00",
            }
            MODULE.write_state(state, payload)
            self.assertEqual(MODULE.load_state(state), payload)
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)
            self.assertEqual(list(state.parent.glob(f".{state.name}.tmp.*")), [])

    def test_state_write_replaces_symlink_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.json"
            state = root / "setup.json"
            target.write_text("sentinel\n", encoding="utf-8")
            state.symlink_to(target)

            payload = {
                "backup": "/tmp/config.toml.backup",
                "config": "/tmp/config.toml",
                "original_osd_enabled": True,
                "setup_at": "2026-08-26T12:00:00+00:00",
            }
            MODULE.write_state(state, payload)

            self.assertEqual(target.read_text(encoding="utf-8"), "sentinel\n")
            self.assertFalse(state.is_symlink())
            self.assertEqual(MODULE.load_state(state), payload)

    def test_state_read_rejects_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.json"
            state = root / "setup.json"
            target.write_text("{}\n", encoding="utf-8")
            state.symlink_to(target)
            with self.assertRaisesRegex(RuntimeError, "unsafe setup-state path"):
                MODULE.load_state(state)

    def test_state_read_rejects_non_regular_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "setup.json"
            os.mkfifo(state)
            with self.assertRaisesRegex(RuntimeError, "not a regular file"):
                MODULE.load_state(state)

    def test_state_read_rejects_oversized_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "setup.json"
            state.write_bytes(b"x" * (MODULE.MAX_STATE_BYTES + 1))
            with self.assertRaisesRegex(RuntimeError, "unexpectedly large"):
                MODULE.load_state(state)

    def test_config_read_rejects_symlink_and_oversized_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.toml"
            config = root / "config.toml"
            target.write_text("[osd]\nenabled = false\n", encoding="utf-8")
            config.symlink_to(target)
            with self.assertRaisesRegex(RuntimeError, "unsafe Voxtype config path"):
                MODULE.read_config(config)
            config.unlink()
            config.write_bytes(b"x" * (MODULE.MAX_CONFIG_BYTES + 1))
            with self.assertRaisesRegex(RuntimeError, "unexpectedly large"):
                MODULE.read_config(config)

    def test_backup_does_not_follow_preplanted_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config.toml"
            target = root / "target.txt"
            timestamp = "20260826T120000Z"
            config.write_text("[osd]\nenabled = true\n", encoding="utf-8")
            target.write_text("sentinel\n", encoding="utf-8")
            planted = root / f"config.toml.voxtype-prism.{timestamp}.deadbeef.bak"
            planted.symlink_to(target)

            with patch.object(
                MODULE.secrets,
                "token_hex",
                side_effect=("deadbeef", "cafebabe"),
            ):
                backup = MODULE.create_backup(
                    config,
                    config.read_text(encoding="utf-8"),
                    timestamp,
                )

            self.assertEqual(target.read_text(encoding="utf-8"), "sentinel\n")
            self.assertTrue(planted.is_symlink())
            self.assertEqual(backup.name, f"config.toml.voxtype-prism.{timestamp}.cafebabe.bak")
            self.assertFalse(backup.is_symlink())
            self.assertEqual(backup.read_text(encoding="utf-8"), config.read_text(encoding="utf-8"))

    def test_forged_regular_state_cannot_redirect_restore(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config_home = root / "config-home"
            legitimate = config_home / "voxtype" / "config.toml"
            legitimate.parent.mkdir(parents=True)
            legitimate.write_text("[osd]\nenabled = false\n", encoding="utf-8")
            victim = root / "victim.txt"
            victim.write_text("sentinel\n", encoding="utf-8")
            state = root / "setup.json"
            MODULE.write_state(
                state,
                {
                    "backup": str(root / "backup.toml"),
                    "config": str(victim),
                    "original_osd_enabled": True,
                    "setup_at": "2026-08-26T12:00:00+00:00",
                },
            )
            args = argparse.Namespace(config=None, state=str(state), no_restart=True)
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config_home)}):
                with self.assertRaisesRegex(RuntimeError, "belongs to"):
                    MODULE.restore(args)
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertEqual(legitimate.read_text(encoding="utf-8"), "[osd]\nenabled = false\n")

    def test_state_requires_strict_schema_types(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "setup.json"
            state.write_text(
                '{"backup":"/tmp/backup","config":"/tmp/config",'
                '"original_osd_enabled":"false","setup_at":"now"}\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "original_osd_enabled"):
                MODULE.load_state(state)

    def test_setup_preserves_concurrent_config_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config.toml"
            state = root / "setup.json"
            config.write_text("original = 1\n[osd]\nenabled = true\n", encoding="utf-8")
            original_create_backup = MODULE.create_backup
            replaced = False

            def create_backup_then_replace(path, text, timestamp):
                nonlocal replaced
                backup = original_create_backup(path, text, timestamp)
                if not replaced:
                    replacement = root / "replacement.toml"
                    replacement.write_text(
                        "concurrent = 1\n[osd]\nenabled = true\n",
                        encoding="utf-8",
                    )
                    os.replace(replacement, config)
                    replaced = True
                return backup

            args = argparse.Namespace(config=str(config), state=str(state), no_restart=True)
            with patch.object(MODULE, "create_backup", side_effect=create_backup_then_replace):
                self.assertEqual(MODULE.setup(args), 0)

            final = config.read_text(encoding="utf-8")
            self.assertIn("concurrent = 1", final)
            self.assertNotIn("original = 1", final)
            self.assertIn("enabled = false", final)


if __name__ == "__main__":
    unittest.main()
