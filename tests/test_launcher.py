from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-prism-launcher"
LOADER = importlib.machinery.SourceFileLoader("voxtype_prism_launcher", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_prism_launcher", LOADER)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class LauncherTests(unittest.TestCase):
    def test_install_is_private_atomic_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "applications" / "voxtype-configure.desktop"
            self.assertTrue(MODULE.atomic_install(target))
            self.assertFalse(MODULE.atomic_install(target))
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)
            self.assertIn(MODULE.MARKER, target.read_text(encoding="utf-8").splitlines())
            self.assertEqual(MODULE.status(target)["state"], "prism")
            self.assertEqual(list(target.parent.glob("*.tmp.*")), [])

    def test_install_refuses_unowned_regular_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            target.write_text("[Desktop Entry]\nName=Mine\n", encoding="utf-8")
            with self.assertRaisesRegex(MODULE.LauncherError, "unowned"):
                MODULE.atomic_install(target)
            self.assertEqual(target.read_text(encoding="utf-8"), "[Desktop Entry]\nName=Mine\n")

    def test_install_does_not_follow_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            victim = root / "victim"
            victim.write_text("keep", encoding="utf-8")
            target = root / "voxtype-configure.desktop"
            target.symlink_to(victim)
            with self.assertRaisesRegex(MODULE.LauncherError, "unsafe"):
                MODULE.atomic_install(target)
            self.assertEqual(victim.read_text(encoding="utf-8"), "keep")

    def test_install_never_overwrites_concurrent_new_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            original_link = MODULE.os.link
            injected = False

            def racing_link(source, destination, **kwargs):
                nonlocal injected
                if not injected and destination == target.name:
                    injected = True
                    target.write_text("[Desktop Entry]\nName=Foreign\n", encoding="utf-8")
                return original_link(source, destination, **kwargs)

            with patch.object(MODULE.os, "link", side_effect=racing_link):
                with self.assertRaisesRegex(MODULE.LauncherError, "concurrently"):
                    MODULE.atomic_install(target)
            self.assertEqual(target.read_text(encoding="utf-8"), "[Desktop Entry]\nName=Foreign\n")

    def test_install_restores_concurrent_replacement_moved_to_quarantine(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            MODULE.atomic_install(target)
            replacement = "[Desktop Entry]\nName=Foreign\n"
            original_rename = MODULE.os.rename
            injected = False

            def racing_rename(source, destination, **kwargs):
                nonlocal injected
                if not injected and source == target.name:
                    injected = True
                    target.write_text(replacement, encoding="utf-8")
                return original_rename(source, destination, **kwargs)

            changed_content = MODULE.DESKTOP_CONTENT.replace(
                "Comment=Configure Voxtype Prism", "Comment=Updated Voxtype Prism"
            )
            with patch.object(MODULE.os, "rename", side_effect=racing_rename):
                with self.assertRaisesRegex(MODULE.LauncherError, "concurrently"):
                    MODULE.atomic_install(target, changed_content)
            self.assertEqual(target.read_text(encoding="utf-8"), replacement)

    def test_remove_only_owned_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            MODULE.atomic_install(target)
            self.assertTrue(MODULE.remove_owned(target))
            self.assertFalse(target.exists())
            self.assertFalse(MODULE.remove_owned(target))

    def test_remove_restores_concurrent_unowned_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            MODULE.atomic_install(target)
            replacement = "[Desktop Entry]\nName=Foreign\n"
            original_rename = MODULE.os.rename
            injected = False

            def racing_rename(source, destination, **kwargs):
                nonlocal injected
                if not injected and source == target.name:
                    injected = True
                    target.write_text(replacement, encoding="utf-8")
                return original_rename(source, destination, **kwargs)

            with patch.object(MODULE.os, "rename", side_effect=racing_rename):
                with self.assertRaisesRegex(MODULE.LauncherError, "concurrently"):
                    MODULE.remove_owned(target)
            self.assertEqual(target.read_text(encoding="utf-8"), replacement)

    def test_status_action_never_emits_desktop_contents(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-configure.desktop"
            MODULE.atomic_install(target)
            with patch.dict(os.environ, {"VOXTYPE_PRISM_DESKTOP_TARGET": str(target)}):
                with patch("builtins.print") as output:
                    self.assertEqual(MODULE.main(["status"]), 0)
            payload = json.loads(output.call_args.args[0])
            self.assertEqual(payload["state"], "prism")
            self.assertNotIn("Exec", output.call_args.args[0])

    def test_open_accepts_only_affirmative_shell_result(self) -> None:
        completed = __import__("subprocess").CompletedProcess([], 0, stdout="true\n", stderr="")
        with patch.object(MODULE, "apply_window_rules"), patch.object(
            MODULE.shutil, "which", return_value="/usr/bin/omarchy-shell"
        ), patch.object(MODULE.subprocess, "run", return_value=completed) as runner, patch.object(
            MODULE, "exec_stock"
        ) as fallback:
            self.assertEqual(MODULE.open_panel(), 0)
            fallback.assert_not_called()
            self.assertEqual(runner.call_args.args[0][-2:], [MODULE.PLUGIN_ID, "{}"])

    def test_open_falls_back_when_panel_is_unavailable(self) -> None:
        completed = __import__("subprocess").CompletedProcess([], 0, stdout="unknown\n", stderr="")
        with patch.object(MODULE, "apply_window_rules"), patch.object(
            MODULE.shutil, "which", return_value="/usr/bin/omarchy-shell"
        ), patch.object(MODULE.subprocess, "run", return_value=completed), patch.object(
            MODULE, "exec_stock", return_value=7
        ) as fallback:
            self.assertEqual(MODULE.open_panel(), 7)
            fallback.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
