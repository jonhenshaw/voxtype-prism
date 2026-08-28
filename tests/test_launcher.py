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
            target = Path(directory) / "applications" / "voxtype-prism.desktop"
            self.assertTrue(MODULE.atomic_install(target))
            self.assertFalse(MODULE.atomic_install(target))
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)
            self.assertIn(MODULE.MARKER, target.read_text(encoding="utf-8").splitlines())
            self.assertEqual(MODULE.status(target)["state"], "prism")
            self.assertEqual(list(target.parent.glob("*.tmp.*")), [])
            self.assertIn(r"\\$", target.read_text(encoding="utf-8"))
            self.assertIn("Name=Voxtype Prism", target.read_text(encoding="utf-8"))
            self.assertNotIn("Name=Voxtype Configuration", target.read_text(encoding="utf-8"))

    def test_install_refuses_unowned_regular_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-prism.desktop"
            target.write_text("[Desktop Entry]\nName=Mine\n", encoding="utf-8")
            with self.assertRaisesRegex(MODULE.LauncherError, "unowned"):
                MODULE.atomic_install(target)
            self.assertEqual(target.read_text(encoding="utf-8"), "[Desktop Entry]\nName=Mine\n")

    def test_install_does_not_follow_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            victim = root / "victim"
            victim.write_text("keep", encoding="utf-8")
            target = root / "voxtype-prism.desktop"
            target.symlink_to(victim)
            with self.assertRaisesRegex(MODULE.LauncherError, "unsafe"):
                MODULE.atomic_install(target)
            self.assertEqual(victim.read_text(encoding="utf-8"), "keep")

    def test_install_never_overwrites_concurrent_new_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-prism.desktop"
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
            target = Path(directory) / "voxtype-prism.desktop"
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
            target = Path(directory) / "voxtype-prism.desktop"
            MODULE.atomic_install(target)
            self.assertTrue(MODULE.remove_owned(target))
            self.assertFalse(target.exists())
            self.assertFalse(MODULE.remove_owned(target))

    def test_remove_restores_concurrent_unowned_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "voxtype-prism.desktop"
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
            target = Path(directory) / "voxtype-prism.desktop"
            MODULE.atomic_install(target)
            legacy = Path(directory) / "voxtype-configure.desktop"
            with patch.dict(os.environ, {
                "VOXTYPE_PRISM_DESKTOP_TARGET": str(target),
                "VOXTYPE_PRISM_LEGACY_DESKTOP_TARGET": str(legacy),
            }):
                with patch("builtins.print") as output:
                    self.assertEqual(MODULE.main(["status"]), 0)
            payload = json.loads(output.call_args.args[0])
            self.assertEqual(payload["state"], "prism")
            self.assertNotIn("Exec", output.call_args.args[0])

    def test_install_migrates_owned_legacy_override_to_separate_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            data_home = Path(directory)
            applications = data_home / "applications"
            legacy = applications / MODULE.LEGACY_DESKTOP_NAME
            legacy_content = MODULE.DESKTOP_CONTENT.replace(
                "Name=Voxtype Prism", "Name=Voxtype Configuration"
            )
            MODULE.atomic_install(legacy, legacy_content)

            with patch.dict(os.environ, {
                "XDG_DATA_HOME": str(data_home),
                "VOXTYPE_PRISM_DESKTOP_TARGET": "",
                "VOXTYPE_PRISM_LEGACY_DESKTOP_TARGET": "",
            }), patch.object(MODULE, "install_window_rule"), patch("builtins.print") as output:
                self.assertEqual(MODULE.main(["install"]), 0)

            target = applications / MODULE.PRISM_DESKTOP_NAME
            payload = json.loads(output.call_args.args[0])
            self.assertFalse(legacy.exists())
            self.assertTrue(target.exists())
            self.assertEqual(payload["legacyOverride"], "removed")
            self.assertEqual(payload["state"], "prism")
            self.assertIn("Name=Voxtype Prism", target.read_text(encoding="utf-8"))

    def test_install_preserves_foreign_native_configuration_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            data_home = Path(directory)
            applications = data_home / "applications"
            applications.mkdir(parents=True)
            legacy = applications / MODULE.LEGACY_DESKTOP_NAME
            foreign = "[Desktop Entry]\nName=My Voxtype Settings\n"
            legacy.write_text(foreign, encoding="utf-8")

            with patch.dict(os.environ, {
                "XDG_DATA_HOME": str(data_home),
                "VOXTYPE_PRISM_DESKTOP_TARGET": "",
                "VOXTYPE_PRISM_LEGACY_DESKTOP_TARGET": "",
            }), patch.object(MODULE, "install_window_rule"), patch("builtins.print") as output:
                self.assertEqual(MODULE.main(["install"]), 0)

            payload = json.loads(output.call_args.args[0])
            self.assertEqual(legacy.read_text(encoding="utf-8"), foreign)
            self.assertEqual(payload["legacyOverride"], "preserved")
            self.assertTrue((applications / MODULE.PRISM_DESKTOP_NAME).exists())

    def test_remove_cleans_new_and_owned_legacy_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            data_home = Path(directory)
            applications = data_home / "applications"
            target = applications / MODULE.PRISM_DESKTOP_NAME
            legacy = applications / MODULE.LEGACY_DESKTOP_NAME
            MODULE.atomic_install(target)
            MODULE.atomic_install(legacy)

            with patch.dict(os.environ, {
                "XDG_DATA_HOME": str(data_home),
                "VOXTYPE_PRISM_DESKTOP_TARGET": "",
                "VOXTYPE_PRISM_LEGACY_DESKTOP_TARGET": "",
            }), patch("builtins.print") as output:
                self.assertEqual(MODULE.main(["remove"]), 0)

            payload = json.loads(output.call_args.args[0])
            self.assertFalse(target.exists())
            self.assertFalse(legacy.exists())
            self.assertEqual(payload["legacyOverride"], "removed")
            self.assertEqual(payload["state"], "absent")

    def test_open_accepts_only_affirmative_shell_result(self) -> None:
        completed = __import__("subprocess").CompletedProcess([], 0, stdout="true\n", stderr="")
        with patch.object(MODULE, "install_window_rule"), patch.object(
            MODULE, "apply_window_rules"
        ) as window_rules, patch.object(
            MODULE.shutil, "which", return_value="/usr/bin/omarchy-shell"
        ), patch.object(MODULE.subprocess, "run", return_value=completed) as runner, patch.object(
            MODULE, "exec_stock"
        ) as fallback:
            self.assertEqual(MODULE.open_panel(), 0)
            fallback.assert_not_called()
            window_rules.assert_called_once_with()
            self.assertEqual(runner.call_args.args[0][-2:], [MODULE.PLUGIN_ID, "{}"])

    def test_open_falls_back_when_panel_is_unavailable(self) -> None:
        completed = __import__("subprocess").CompletedProcess([], 0, stdout="unknown\n", stderr="")
        with patch.object(MODULE, "install_window_rule"), patch.object(
            MODULE, "apply_window_rules"
        ), patch.object(
            MODULE.shutil, "which", return_value="/usr/bin/omarchy-shell"
        ), patch.object(MODULE.subprocess, "run", return_value=completed), patch.object(
            MODULE, "exec_stock", return_value=7
        ) as fallback:
            self.assertEqual(MODULE.open_panel(), 7)
            fallback.assert_called_once_with()

    def test_window_rule_uses_current_hyprland_lua_api(self) -> None:
        subprocess = __import__("subprocess")
        completed = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with patch.dict(os.environ, {"VOXTYPE_PRISM_HYPRCTL": "/fake/hyprctl"}), patch.object(
            MODULE.subprocess, "run", return_value=completed
        ) as runner:
            MODULE.install_window_rule()

        command = runner.call_args.args[0]
        self.assertEqual(command[:2], ["/fake/hyprctl", "eval"])
        self.assertIn("hl.window_rule", command[2])
        self.assertIn('title = "^(Voxtype Prism)$"', command[2])
        self.assertIn("size = { 1120, 760 }", command[2])

    def test_current_hyprland_dispatch_floats_sizes_and_centers_window(self) -> None:
        subprocess = __import__("subprocess")

        def run(command, **kwargs):
            if command[1:] == ["clients", "-j"]:
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=json.dumps([
                        {
                            "address": "0xabc123",
                            "title": "Voxtype Prism",
                            "floating": False,
                        }
                    ]),
                    stderr="",
                )
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with patch.dict(os.environ, {"VOXTYPE_PRISM_HYPRCTL": "/fake/hyprctl"}), patch.object(
            MODULE.subprocess, "run", side_effect=run
        ) as runner:
            MODULE.apply_window_rules()

        commands = [call.args[0] for call in runner.call_args_list]
        expressions = [command[2] for command in commands if command[1] == "dispatch"]
        self.assertEqual(len(expressions), 3)
        self.assertIn("hl.dsp.window.float", expressions[0])
        self.assertIn("address:0xabc123", expressions[0])
        self.assertIn("x = 1120, y = 760", expressions[1])
        self.assertIn("hl.dsp.window.center", expressions[2])
        self.assertFalse(any("keyword" in command for command in commands))

    def test_current_hyprland_dispatch_does_not_toggle_floating_window(self) -> None:
        subprocess = __import__("subprocess")

        def run(command, **kwargs):
            if command[1:] == ["clients", "-j"]:
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=json.dumps([
                        {
                            "address": "0xdef456",
                            "title": "Voxtype Prism",
                            "floating": True,
                        }
                    ]),
                    stderr="",
                )
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with patch.dict(os.environ, {"VOXTYPE_PRISM_HYPRCTL": "/fake/hyprctl"}), patch.object(
            MODULE.subprocess, "run", side_effect=run
        ) as runner:
            MODULE.apply_window_rules()

        expressions = [
            call.args[0][2]
            for call in runner.call_args_list
            if call.args[0][1] == "dispatch"
        ]
        self.assertEqual(len(expressions), 2)
        self.assertFalse(any("hl.dsp.window.float" in expression for expression in expressions))


if __name__ == "__main__":
    unittest.main()
