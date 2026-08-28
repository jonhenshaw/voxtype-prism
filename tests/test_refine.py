from __future__ import annotations

import importlib.util
import json
import os
import sqlite3
import stat
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-refine"
LOADER = SourceFileLoader("voxtype_refine", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_refine", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["voxtype_refine"] = MODULE
SPEC.loader.exec_module(MODULE)


class RefineHelperTests(unittest.TestCase):
    @staticmethod
    def write_credential_database(path: Path, provider: str, payload: object) -> None:
        connection = sqlite3.connect(path)
        try:
            connection.execute("create table auth_credentials (provider text, data text)")
            connection.execute(
                "insert into auth_credentials values (?, ?)",
                (provider, json.dumps(payload)),
            )
            connection.commit()
        finally:
            connection.close()

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

    def test_provider_change_preserves_model_override_and_future_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "refine.toml"
            path.write_text(
                '# keep me\nprovider = "grok"\nmodel = "custom-model"\nfuture = "yes"\n',
                encoding="utf-8",
            )
            MODULE.write_refine_config(path, "anthropic")
            text = path.read_text(encoding="utf-8")
            self.assertIn('# keep me', text)
            self.assertIn('provider = "anthropic"', text)
            self.assertIn('model = "custom-model"', text)
            self.assertIn('future = "yes"', text)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

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
            default_text = created.read_text(encoding="utf-8")
            self.assertTrue(default_text.startswith("# Custom dictionary"))
            for entry in (
                "OH-MAH-CHI -> Omarchy",
                "HERDER -> herdr",
                "Hyper Land -> Hyprland",
            ):
                self.assertIn(entry, default_text)
            created.write_text("Voxtype\n", encoding="utf-8")
            MODULE.ensure_dictionary_file(path)
            self.assertEqual(path.read_text(encoding="utf-8"), "Voxtype\n")

    def test_all_refine_text_reads_reject_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target"
            target.write_text('provider = "grok"\n', encoding="utf-8")
            for name, loader in (
                ("refine.toml", MODULE.load_selection),
                ("prompt.md", MODULE.load_system_prompt),
                ("dictionary.md", MODULE.load_dictionary),
            ):
                with self.subTest(name=name):
                    link = root / name
                    link.symlink_to(target)
                    with self.assertRaisesRegex(RuntimeError, "unsafe"):
                        loader(link)

    def test_atomic_write_skips_preplanted_temporary_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "refine.toml"
            victim = root / "victim"
            victim.write_text("sentinel\n", encoding="utf-8")
            planted = root / ".refine.toml.tmp.deadbeef"
            planted.symlink_to(victim)
            with patch.object(MODULE.secrets, "token_hex", side_effect=("deadbeef", "cafebabe")):
                MODULE.atomic_write_text(
                    path,
                    'provider = "grok"\n',
                    MODULE.MAX_REFINE_CONFIG_BYTES,
                    "refine config",
                    expected=None,
                )
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertTrue(planted.is_symlink())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(list(root.glob(".refine.toml.tmp.cafebabe")), [])

    def test_atomic_write_replaces_destination_symlink_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target"
            path = root / "prompt.md"
            target.write_text("sentinel\n", encoding="utf-8")
            path.symlink_to(target)
            MODULE.atomic_write_text(path, "safe\n", 1024, "prompt")
            self.assertEqual(target.read_text(encoding="utf-8"), "sentinel\n")
            self.assertFalse(path.is_symlink())
            self.assertEqual(path.read_text(encoding="utf-8"), "safe\n")

    def test_expected_absent_never_overwrites_concurrent_create(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            original_publish = MODULE._publish_noreplace

            def create_before_publish(directory_fd, temporary_name, destination_name):
                descriptor = os.open(
                    destination_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                    0o600,
                    dir_fd=directory_fd,
                )
                try:
                    os.write(descriptor, b"concurrent\n")
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
                return original_publish(directory_fd, temporary_name, destination_name)

            with patch.object(MODULE, "_publish_noreplace", side_effect=create_before_publish):
                with self.assertRaisesRegex(RuntimeError, "changed concurrently"):
                    MODULE.atomic_write_text(path, "candidate\n", 1024, "prompt", expected=None)

            self.assertEqual(path.read_text(encoding="utf-8"), "concurrent\n")
            self.assertEqual(list(root.glob(".prompt.md.tmp.*")), [])
            self.assertEqual(list(root.glob(".prompt.md.cas.*")), [])

    def test_expected_text_restores_concurrent_regular_replacement_before_exchange(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            path.write_text("expected\n", encoding="utf-8")
            original_exchange = MODULE._rename_exchange
            calls = 0

            def replace_before_exchange(directory_fd, temporary_name, destination_name):
                nonlocal calls
                calls += 1
                if calls == 1:
                    replacement = root / "replacement"
                    replacement.write_text("concurrent\n", encoding="utf-8")
                    os.replace(replacement, path)
                return original_exchange(directory_fd, temporary_name, destination_name)

            with patch.object(MODULE, "_rename_exchange", side_effect=replace_before_exchange):
                with self.assertRaisesRegex(RuntimeError, "changed concurrently"):
                    MODULE.atomic_write_text(
                        path,
                        "candidate\n",
                        1024,
                        "prompt",
                        expected="expected\n",
                    )

            self.assertEqual(path.read_text(encoding="utf-8"), "concurrent\n")
            self.assertEqual(list(root.glob(".prompt.md.cas.*")), [])
            self.assertEqual(list(root.glob(".prompt.md.tmp.*")), [])

    def test_expected_text_preserves_concurrent_symlink_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            victim = root / "victim"
            path.write_text("expected\n", encoding="utf-8")
            victim.write_text("sentinel\n", encoding="utf-8")
            original_exchange = MODULE._rename_exchange
            calls = 0

            def replace_with_symlink(directory_fd, source, destination):
                nonlocal calls
                calls += 1
                if calls == 1:
                    os.unlink(destination, dir_fd=directory_fd)
                    os.symlink(victim.name, destination, dir_fd=directory_fd)
                return original_exchange(directory_fd, source, destination)

            with patch.object(MODULE, "_rename_exchange", side_effect=replace_with_symlink):
                with self.assertRaisesRegex(RuntimeError, "changed concurrently"):
                    MODULE.atomic_write_text(
                        path,
                        "candidate\n",
                        1024,
                        "prompt",
                        expected="expected\n",
                    )

            self.assertTrue(path.is_symlink())
            self.assertEqual(os.readlink(path), victim.name)
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertEqual(list(root.glob(".prompt.md.tmp.*")), [])
            self.assertEqual(list(root.glob(".prompt.md.cas.*")), [])

    def test_expected_exchange_never_makes_canonical_path_absent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            path.write_text("expected\n", encoding="utf-8")
            original_exchange = MODULE._rename_exchange
            observed: list[str] = []

            def exchange_then_read(directory_fd, temporary_name, destination_name):
                original_exchange(directory_fd, temporary_name, destination_name)
                os.lstat(path)
                observed.append(path.read_text(encoding="utf-8"))

            with patch.object(MODULE, "_rename_exchange", side_effect=exchange_then_read):
                MODULE.atomic_write_text(
                    path,
                    "candidate\n",
                    1024,
                    "prompt",
                    expected="expected\n",
                )

            self.assertEqual(observed, ["candidate\n"])
            self.assertEqual(path.read_text(encoding="utf-8"), "candidate\n")

    def test_failure_after_exchange_keeps_canonical_and_rolls_back(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            path.write_text("expected\n", encoding="utf-8")
            original_snapshot = MODULE._entry_snapshot_at
            calls = 0

            def fail_first_post_exchange_snapshot(directory_fd, name, limit, label):
                nonlocal calls
                calls += 1
                if calls == 2:
                    os.lstat(path)
                    raise OSError("injected failure after exchange")
                return original_snapshot(directory_fd, name, limit, label)

            with patch.object(
                MODULE,
                "_entry_snapshot_at",
                side_effect=fail_first_post_exchange_snapshot,
            ):
                with self.assertRaisesRegex(OSError, "injected failure"):
                    MODULE.atomic_write_text(
                        path,
                        "candidate\n",
                        1024,
                        "prompt",
                        expected="expected\n",
                    )

            os.lstat(path)
            self.assertEqual(path.read_text(encoding="utf-8"), "expected\n")
            self.assertEqual(list(root.glob(".prompt.md.tmp.*")), [])

    def test_concurrent_replacement_after_exchange_remains_canonical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            path.write_text("expected\n", encoding="utf-8")
            original_snapshot = MODULE._entry_snapshot_at
            calls = 0

            def replace_after_exchange(directory_fd, name, limit, label):
                nonlocal calls
                calls += 1
                if calls == 2:
                    replacement = root / "replacement"
                    replacement.write_text("concurrent later\n", encoding="utf-8")
                    os.replace(replacement, path)
                return original_snapshot(directory_fd, name, limit, label)

            with patch.object(MODULE, "_entry_snapshot_at", side_effect=replace_after_exchange):
                MODULE.atomic_write_text(
                    path,
                    "candidate\n",
                    1024,
                    "prompt",
                    expected="expected\n",
                )

            self.assertEqual(path.read_text(encoding="utf-8"), "concurrent later\n")
            self.assertEqual(list(root.glob(".prompt.md.tmp.*")), [])

    def test_cas_remove_never_deletes_a_concurrent_later_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "prompt.md"
            path.write_text("our candidate\n", encoding="utf-8")
            original_read = MODULE._read_bounded_text_at

            def read_then_create(directory_fd, quarantine_name, limit, label):
                displaced = original_read(directory_fd, quarantine_name, limit, label)
                descriptor = os.open(
                    path.name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                    0o600,
                    dir_fd=directory_fd,
                )
                try:
                    os.write(descriptor, b"concurrent later entry\n")
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
                return displaced

            with patch.object(MODULE, "_read_bounded_text_at", side_effect=read_then_create):
                MODULE.atomic_remove_text(path, "our candidate\n", 1024, "prompt")

            self.assertEqual(path.read_text(encoding="utf-8"), "concurrent later entry\n")
            self.assertEqual(list(root.glob(".prompt.md.cas.*")), [])

    def test_bounded_response_rejects_stream_without_content_length(self) -> None:
        class EndlessResponse:
            headers: dict[str, str] = {}

            def __init__(self) -> None:
                self.remaining = MODULE.MAX_NETWORK_RESPONSE_BYTES + 1

            def read(self, amount: int) -> bytes:
                if self.remaining <= 0:
                    return b""
                count = min(amount, self.remaining)
                self.remaining -= count
                return b"x" * count

        with self.assertRaisesRegex(RuntimeError, "byte limit"):
            MODULE.read_bounded_response(EndlessResponse())

    def test_bounded_response_rejects_large_content_length_before_read(self) -> None:
        class Response:
            headers = {"Content-Length": str(MODULE.MAX_NETWORK_RESPONSE_BYTES + 1)}

            def read(self, _amount: int) -> bytes:
                raise AssertionError("oversized response should not be read")

        with self.assertRaisesRegex(RuntimeError, "byte limit"):
            MODULE.read_bounded_response(Response())

    def test_oauth_rejects_symlinked_credential_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "real-agent.db"
            self.write_credential_database(database, "xai-oauth", {"access": "secret"})
            link = root / "agent.db"
            link.symlink_to(database)

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(link)}):
                with self.assertRaisesRegex(RuntimeError, "unsafe credential database"):
                    MODULE.load_oauth("xai-oauth")

    def test_oauth_rejects_oversized_credential_database_before_sqlite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "agent.db"
            with database.open("wb") as stream:
                stream.truncate(MODULE.MAX_CREDENTIAL_DB_BYTES + 1)

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(database)}):
                with patch.object(MODULE.sqlite3, "connect") as connect:
                    with self.assertRaisesRegex(RuntimeError, "unexpectedly large"):
                        MODULE.load_oauth("xai-oauth")
                connect.assert_not_called()

    def test_oauth_rejects_oversized_json_row_before_parsing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "agent.db"
            self.write_credential_database(
                database,
                "xai-oauth",
                {"access": "x" * MODULE.MAX_CREDENTIAL_JSON_BYTES},
            )

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(database)}):
                with self.assertRaisesRegex(RuntimeError, "credential data is too large"):
                    MODULE.load_oauth("xai-oauth")

    def test_oauth_detects_path_identity_change_after_sqlite_open(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "agent.db"
            replacement = root / "replacement.db"
            self.write_credential_database(database, "xai-oauth", {"access": "original"})
            self.write_credential_database(replacement, "xai-oauth", {"access": "replacement"})
            real_connect = MODULE.sqlite3.connect

            def connect_then_replace(*args, **kwargs):
                connection = real_connect(*args, **kwargs)
                os.replace(replacement, database)
                return connection

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(database)}):
                with patch.object(MODULE.sqlite3, "connect", side_effect=connect_then_replace):
                    with self.assertRaisesRegex(RuntimeError, "changed while reading"):
                        MODULE.load_oauth("xai-oauth")

    def test_oauth_missing_ok_returns_none_but_normal_load_requires_access(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "missing-agent.db"
            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(database)}):
                self.assertIsNone(MODULE.load_oauth("xai-oauth", missing_ok=True))
                with self.assertRaisesRegex(RuntimeError, "no OhMyPi login"):
                    MODULE.load_oauth("xai-oauth")

    def test_oauth_accepts_normal_real_shaped_row(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "agent.db"
            payload = {
                "access": "access-token",
                "refresh": "refresh-token",
                "expires": 1_900_000_000_000,
                "accountId": "account-id",
            }
            self.write_credential_database(database, "openai-codex", payload)

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(database)}):
                self.assertEqual(MODULE.load_oauth("openai-codex"), payload)

    def test_oauth_validates_object_shape_and_requires_nonempty_access(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            invalid = root / "invalid.db"
            empty = root / "empty.db"
            self.write_credential_database(invalid, "xai-oauth", ["not", "an", "object"])
            self.write_credential_database(empty, "xai-oauth", {"access": ""})

            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(invalid)}):
                with self.assertRaisesRegex(RuntimeError, "invalid shape"):
                    MODULE.load_oauth("xai-oauth", missing_ok=True)
            with patch.dict(os.environ, {"VOXTYPE_OMP_AGENT_DB": str(empty)}):
                self.assertIsNone(MODULE.load_oauth("xai-oauth", missing_ok=True))
                self.assertFalse(MODULE.oauth_available("xai-oauth"))
                with self.assertRaisesRegex(RuntimeError, "missing an access token"):
                    MODULE.load_oauth("xai-oauth")




if __name__ == "__main__":
    unittest.main()
