from __future__ import annotations

import importlib.util
import json
import os
import sqlite3
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "voxtype-prism-settings"
LOADER = SourceFileLoader("voxtype_prism_settings", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("voxtype_prism_settings", LOADER)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["voxtype_prism_settings"] = MODULE
SPEC.loader.exec_module(MODULE)

READ_SCRIPT = SCRIPT.with_name("voxtype-prism-read")
READ_LOADER = SourceFileLoader("voxtype_prism_settings_contract_reader", str(READ_SCRIPT))
READ_SPEC = importlib.util.spec_from_loader("voxtype_prism_settings_contract_reader", READ_LOADER)
assert READ_SPEC is not None and READ_SPEC.loader is not None
READ_MODULE = importlib.util.module_from_spec(READ_SPEC)
sys.modules["voxtype_prism_settings_contract_reader"] = READ_MODULE
READ_SPEC.loader.exec_module(READ_MODULE)


class RecordingRunner:
    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def __call__(self, command: list[str]) -> SimpleNamespace:
        self.commands.append(command)
        return SimpleNamespace(returncode=0)


class SimulatedCrash(BaseException):
    """Bypass normal exception rollback to model abrupt process death."""


class SettingsBackendTests(unittest.TestCase):
    @contextmanager
    def isolated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config_home = root / "config"
            state_home = root / "state"
            voxtype = config_home / "voxtype"
            voxtype.mkdir(parents=True)
            config = voxtype / "config.toml"
            config.write_text(
                '[output]\nmode = "paste"\n\n[output.post_process]\ntimeout_ms = 30000\n',
                encoding="utf-8",
            )
            env = {
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_STATE_HOME": str(state_home),
                "VOXTYPE_CONFIG": str(config),
                "VOXTYPE_REFINE_CONFIG": str(voxtype / "refine.toml"),
                "VOXTYPE_REFINE_PROMPT": str(voxtype / "refine-prompt.md"),
                "VOXTYPE_REFINE_DICTIONARY": str(voxtype / "refine-dictionary.md"),
                "VOXTYPE_PRISM_INDICATOR": str(config_home / "voxtype-prism" / "indicator.json"),
                "VOXTYPE_PRISM_HOOK_STATE": str(state_home / "voxtype-prism" / "refine-hook.json"),
                "VOXTYPE_PRISM_REFINE_COMMAND": str(SCRIPT.with_name("voxtype-refine")),
                "VOXTYPE_PRISM_LEGACY_TRAMPOLINE": str(voxtype / "llm-refine.py"),
                "VOXTYPE_OMP_AGENT_DB": str(root / "missing-agent.db"),
            }
            with patch.dict(os.environ, env, clear=False):
                for name in ("VOXTYPE_REFINE_PROVIDER", "VOXTYPE_REFINE_MODEL", "VOXTYPE_LOCAL_BASE_URL"):
                    os.environ.pop(name, None)
                yield root, config

    def request(self, patch_payload: dict, revision: str | None = None) -> dict:
        if revision is None:
            revision = MODULE.snapshot()["revision"]
        return {
            "protocol": 1,
            "expectedRevision": revision,
            "patch": patch_payload,
        }

    def test_snapshot_is_normalized_and_credential_free(self) -> None:
        with self.isolated() as (root, _config):
            database = root / "agent.db"
            connection = sqlite3.connect(database)
            connection.execute("create table auth_credentials (provider text, data text)")
            token = "super-secret-access-token"
            connection.execute(
                "insert into auth_credentials values (?, ?)",
                (
                    "xai-oauth",
                    json.dumps(
                        {
                            "access": token,
                            "refresh": "also-secret",
                            "expires": 1_900_000_000_000,
                            "accountId": "private-account-id",
                        }
                    ),
                ),
            )
            connection.commit()
            connection.close()
            os.environ["VOXTYPE_OMP_AGENT_DB"] = str(database)

            result = MODULE.snapshot()
            serialized = json.dumps(result)
            self.assertEqual(result["protocol"], 1)
            self.assertTrue(result["ok"])
            self.assertEqual(
                result["settings"]["indicator"],
                {
                    "version": 1,
                    "preset": "signal",
                    "position": "bottom-center",
                    "scale": 1.0,
                    "motion": True,
                    "glow": 0.6,
                },
            )
            self.assertEqual(result["settings"]["refine"]["readiness"], "ready")
            self.assertNotIn(token, serialized)
            self.assertNotIn("also-secret", serialized)
            self.assertNotIn("private-account-id", serialized)
            self.assertNotIn("accountId", serialized)

    def test_snapshot_reports_missing_readiness_without_creating_database(self) -> None:
        with self.isolated() as (root, _config):
            database = root / "missing-agent.db"
            result = MODULE.snapshot()
            providers = {
                provider["id"]: provider["readiness"]
                for provider in result["catalog"]["providers"]
            }

            self.assertEqual(result["settings"]["refine"]["readiness"], "missing")
            self.assertEqual(providers["grok"], "missing")
            self.assertEqual(providers["anthropic"], "missing")
            self.assertEqual(providers["openai"], "missing")
            self.assertEqual(providers["local"], "ready")
            self.assertFalse(database.exists())

    def test_apply_omitted_fields_unchanged_and_writes_exact_indicator_schema(self) -> None:
        with self.isolated() as (_root, _config):
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("Keep this prompt.\n", encoding="utf-8")
            runner = RecordingRunner()
            result = MODULE.apply_request(
                self.request({"indicator": {"preset": "halo", "scale": 1.25}}),
                runner,
            )
            indicator = json.loads(MODULE.indicator_path().read_text(encoding="utf-8"))
            self.assertEqual(
                indicator,
                {
                    "version": 1,
                    "preset": "halo",
                    "position": "bottom-center",
                    "scale": 1.25,
                    "motion": True,
                    "glow": 0.6,
                },
            )
            self.assertEqual(prompt.read_text(encoding="utf-8"), "Keep this prompt.\n")
            self.assertEqual(stat.S_IMODE(MODULE.indicator_path().stat().st_mode), 0o600)
            self.assertEqual(runner.commands, [])
            self.assertFalse(result["restart"]["required"])

    def test_indicator_validation_is_strict(self) -> None:
        with self.isolated():
            revision = MODULE.snapshot()["revision"]
            cases = (
                ({"preset": "unknown"}, "indicator.preset"),
                ({"position": "left"}, "indicator.position"),
                ({"scale": 0.74}, "indicator.scale"),
                ({"scale": True}, "indicator.scale"),
                ({"motion": "yes"}, "indicator.motion"),
                ({"glow": 1.01}, "indicator.glow"),
                ({"future": True}, "indicator.future"),
            )
            for candidate, field in cases:
                with self.subTest(candidate=candidate):
                    with self.assertRaises(MODULE.SettingsError) as caught:
                        MODULE.apply_request(self.request({"indicator": candidate}, revision))
                    self.assertEqual(caught.exception.field, field)

    def test_indicator_reader_contract_accepts_4096_bytes_and_rejects_4097(self) -> None:
        with self.isolated():
            indicator = MODULE.indicator_path()
            indicator.parent.mkdir(parents=True)
            payload = dict(MODULE.DEFAULT_INDICATOR, preset="halo")
            canonical = json.dumps(payload)
            indicator.write_text(
                canonical + (" " * (MODULE.MAX_INDICATOR_BYTES - len(canonical))),
                encoding="utf-8",
            )
            self.assertEqual(indicator.stat().st_size, 4096)
            self.assertEqual(MODULE.snapshot()["settings"]["indicator"]["preset"], "halo")
            runtime = json.loads(READ_MODULE.prism_settings_status(indicator))
            self.assertEqual(runtime["styleId"], "halo")

            indicator.write_text(canonical + (" " * (4097 - len(canonical))), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unexpectedly large"):
                MODULE.snapshot()
            runtime = json.loads(READ_MODULE.prism_settings_status(indicator))
            self.assertEqual(runtime["styleId"], "signal")

    def test_stale_revision_causes_no_write(self) -> None:
        with self.isolated() as (_root, _config):
            stale = MODULE.snapshot()["revision"]
            MODULE.REFINE.prompt_path().write_text("concurrent\n", encoding="utf-8")
            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(self.request({"indicator": {"preset": "halo"}}, stale))
            self.assertEqual(caught.exception.code, "revision_conflict")
            self.assertFalse(MODULE.indicator_path().exists())

    def test_provider_only_patch_preserves_model_override_and_future_keys(self) -> None:
        with self.isolated():
            refine = MODULE.REFINE.refine_config_path()
            refine.write_text(
                'provider = "grok"\nmodel = "my-override"\nfuture = "untouched"\n',
                encoding="utf-8",
            )
            result = MODULE.apply_request(self.request({"refine": {"provider": "anthropic"}}))
            text = refine.read_text(encoding="utf-8")
            self.assertIn('provider = "anthropic"', text)
            self.assertIn('model = "my-override"', text)
            self.assertIn('future = "untouched"', text)
            self.assertEqual(result["snapshot"]["settings"]["refine"]["model"], "my-override")

    def test_prompt_dictionary_and_config_writes_are_private_and_leave_no_temps(self) -> None:
        with self.isolated():
            result = MODULE.apply_request(
                self.request(
                    {
                        "refine": {
                            "provider": "local",
                            "model": "custom-local",
                            "prompt": "Clean carefully.\n",
                            "dictionary": "vox type → Voxtype\n",
                        }
                    }
                )
            )
            self.assertTrue(result["ok"])
            for path in (
                MODULE.REFINE.refine_config_path(),
                MODULE.REFINE.prompt_path(),
                MODULE.REFINE.dictionary_path(),
            ):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertEqual(list(path.parent.glob(f".{path.name}.tmp.*")), [])

    def test_failure_on_later_write_rolls_back_all_completed_files(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()
            calls = 0

            def fail_second(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected second-write failure")
                MODULE._write_checked(path, text, limit, label, expected)

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            },
                            "indicator": {"preset": "halo"},
                        },
                        before["revision"],
                    ),
                    writer=fail_second,
                )
            self.assertEqual(caught.exception.code, "commit_failed_rolled_back")
            self.assertFalse(caught.exception.committed)
            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertFalse(MODULE.indicator_path().exists())
            self.assertFalse(MODULE.transaction_journal_path().exists())
            self.assertEqual(MODULE.snapshot()["revision"], before["revision"])

    def test_prepared_journal_recovers_after_crash_after_first_write(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()
            calls = 0

            def crash_after_first(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                MODULE._write_checked(path, text, limit, label, expected)
                if calls == 1:
                    raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        },
                        before["revision"],
                    ),
                    writer=crash_after_first,
                )

            self.assertEqual(prompt.read_text(encoding="utf-8"), "replacement prompt\n")
            self.assertTrue(MODULE.transaction_journal_path().exists())

            recovered = MODULE.snapshot()

            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertFalse(MODULE.transaction_journal_path().exists())
            self.assertEqual(recovered["revision"], before["revision"])

    def test_prepared_journal_exists_before_the_first_target_write(self) -> None:
        with self.isolated():
            observed_states: list[str] = []

            def inspect_then_write(path, text, limit, label, expected):
                journal = MODULE.transaction_journal_path()
                observed_states.append(
                    json.loads(journal.read_text(encoding="utf-8"))["state"]
                )
                self.assertEqual(stat.S_IMODE(journal.stat().st_mode), 0o600)
                MODULE._write_checked(path, text, limit, label, expected)

            MODULE.apply_request(
                self.request({"indicator": {"preset": "halo"}}),
                writer=inspect_then_write,
            )

            self.assertEqual(observed_states, ["prepared"])
            self.assertFalse(MODULE.transaction_journal_path().exists())

    def test_prepared_journal_recovers_after_crash_after_nth_write(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()
            calls = 0

            def crash_after_second(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                MODULE._write_checked(path, text, limit, label, expected)
                if calls == 2:
                    raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            },
                            "indicator": {"preset": "halo"},
                        },
                        before["revision"],
                    ),
                    writer=crash_after_second,
                )

            self.assertEqual(prompt.read_text(encoding="utf-8"), "replacement prompt\n")
            self.assertEqual(
                MODULE.REFINE.dictionary_path().read_text(encoding="utf-8"),
                "Voxtype\n",
            )
            self.assertFalse(MODULE.indicator_path().exists())

            recovered = MODULE.snapshot()

            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertFalse(MODULE.indicator_path().exists())
            self.assertFalse(MODULE.transaction_journal_path().exists())
            self.assertEqual(recovered["revision"], before["revision"])

    def test_prepared_journal_rolls_back_crash_after_all_writes_before_commit_mark(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()

            with patch.object(
                MODULE,
                "_mark_transaction_committed",
                side_effect=SimulatedCrash("injected pre-commit crash"),
            ):
                with self.assertRaises(SimulatedCrash):
                    MODULE.apply_request(
                        self.request(
                            {
                                "refine": {
                                    "prompt": "replacement prompt\n",
                                    "dictionary": "Voxtype\n",
                                },
                                "indicator": {"preset": "halo"},
                            },
                            before["revision"],
                        )
                    )

            self.assertEqual(prompt.read_text(encoding="utf-8"), "replacement prompt\n")
            self.assertTrue(MODULE.REFINE.dictionary_path().exists())
            self.assertTrue(MODULE.indicator_path().exists())
            journal = json.loads(MODULE.transaction_journal_path().read_text(encoding="utf-8"))
            self.assertEqual(journal["state"], "prepared")

            recovered = MODULE.snapshot()

            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertFalse(MODULE.indicator_path().exists())
            self.assertFalse(MODULE.transaction_journal_path().exists())
            self.assertEqual(recovered["revision"], before["revision"])

    def test_committed_journal_is_cleaned_without_rolling_back_candidates(self) -> None:
        with self.isolated():
            before = MODULE.snapshot()

            with patch.object(
                MODULE,
                "_remove_transaction_journal",
                side_effect=SimulatedCrash("injected post-commit crash"),
            ):
                with self.assertRaises(SimulatedCrash):
                    MODULE.apply_request(
                        self.request(
                            {
                                "refine": {"prompt": "committed prompt\n"},
                                "indicator": {"preset": "halo"},
                            },
                            before["revision"],
                        )
                    )

            journal = json.loads(MODULE.transaction_journal_path().read_text(encoding="utf-8"))
            self.assertEqual(journal["state"], "committed")
            self.assertEqual(
                MODULE.REFINE.prompt_path().read_text(encoding="utf-8"),
                "committed prompt\n",
            )

            recovered = MODULE.snapshot()

            self.assertEqual(recovered["settings"]["refine"]["prompt"], "committed prompt\n")
            self.assertEqual(recovered["settings"]["indicator"]["preset"], "halo")
            self.assertNotEqual(recovered["revision"], before["revision"])
            self.assertFalse(MODULE.transaction_journal_path().exists())

    def test_prepared_recovery_never_overwrites_a_concurrent_value(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            calls = 0

            def crash_after_second(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                MODULE._write_checked(path, text, limit, label, expected)
                if calls == 2:
                    raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        }
                    ),
                    writer=crash_after_second,
                )
            self.assertEqual(
                MODULE.REFINE.dictionary_path().read_text(encoding="utf-8"),
                "Voxtype\n",
            )
            prompt.write_text("concurrent owner\n", encoding="utf-8")

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.snapshot()

            self.assertEqual(caught.exception.code, "transaction_recovery_required")
            self.assertEqual(prompt.read_text(encoding="utf-8"), "concurrent owner\n")
            self.assertEqual(
                MODULE.REFINE.dictionary_path().read_text(encoding="utf-8"),
                "Voxtype\n",
            )
            self.assertTrue(MODULE.transaction_journal_path().exists())
            self.assertIn("prompt", caught.exception.details["sources"])

    def test_recovery_rejects_a_symlinked_transaction_journal(self) -> None:
        with self.isolated() as (root, _config):
            victim = root / "victim-journal"
            victim.write_text("sentinel\n", encoding="utf-8")
            journal = MODULE.transaction_journal_path()
            journal.parent.mkdir(parents=True)
            journal.symlink_to(victim)

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.snapshot()

            self.assertEqual(caught.exception.code, "transaction_recovery_required")
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertTrue(journal.is_symlink())

    def test_recovery_rejects_an_oversized_transaction_journal(self) -> None:
        with self.isolated():
            journal = MODULE.transaction_journal_path()
            journal.parent.mkdir(parents=True)
            journal.write_bytes(b"x" * (MODULE.MAX_TRANSACTION_JOURNAL_BYTES + 1))
            journal.chmod(0o600)

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.snapshot()

            self.assertEqual(caught.exception.code, "transaction_recovery_required")
            self.assertEqual(
                journal.stat().st_size,
                MODULE.MAX_TRANSACTION_JOURNAL_BYTES + 1,
            )

    def test_recovery_rejects_forged_logical_source_ids_without_using_paths(self) -> None:
        with self.isolated() as (root, _config):
            victim = root / "outside-managed-sources"
            victim.write_text("sentinel\n", encoding="utf-8")
            journal = MODULE.transaction_journal_path()
            journal.parent.mkdir(parents=True)
            journal.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "state": "prepared",
                        "writes": [
                            {
                                "source": "../../outside-managed-sources",
                                "previous": "sentinel\n",
                                "candidate": "attacker candidate\n",
                            }
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            journal.chmod(0o600)

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.snapshot()

            self.assertEqual(caught.exception.code, "transaction_recovery_required")
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertTrue(journal.exists())

    def test_transaction_journal_is_private_and_leaves_no_temporary_files(self) -> None:
        with self.isolated():
            journal = MODULE.transaction_journal_path()

            def crash_after_write(path, text, limit, label, expected):
                MODULE._write_checked(path, text, limit, label, expected)
                raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request({"indicator": {"preset": "halo"}}),
                    writer=crash_after_write,
                )

            self.assertEqual(stat.S_IMODE(journal.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(journal.parent.stat().st_mode), 0o700)
            self.assertEqual(list(journal.parent.glob(f".{journal.name}.tmp.*")), [])
            self.assertEqual(list(journal.parent.glob(f".{journal.name}.cas.*")), [])

            MODULE.snapshot()

            self.assertFalse(journal.exists())
            self.assertEqual(list(journal.parent.glob(f".{journal.name}.tmp.*")), [])
            self.assertEqual(list(journal.parent.glob(f".{journal.name}.cas.*")), [])

    def test_committed_recovery_requires_exact_candidates_and_never_overwrites(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()

            with patch.object(
                MODULE,
                "_remove_transaction_journal",
                side_effect=SimulatedCrash("injected post-commit crash"),
            ):
                with self.assertRaises(SimulatedCrash):
                    MODULE.apply_request(
                        self.request({"refine": {"prompt": "committed prompt\n"}})
                    )
            prompt.write_text("concurrent owner\n", encoding="utf-8")

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.snapshot()

            self.assertEqual(caught.exception.code, "transaction_recovery_required")
            self.assertEqual(caught.exception.details["journalState"], "committed")
            self.assertEqual(prompt.read_text(encoding="utf-8"), "concurrent owner\n")
            self.assertTrue(MODULE.transaction_journal_path().exists())

    def test_apply_recovers_a_prepared_transaction_before_revision_check(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()

            def crash_after_write(path, text, limit, label, expected):
                MODULE._write_checked(path, text, limit, label, expected)
                raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        },
                        before["revision"],
                    ),
                    writer=crash_after_write,
                )

            result = MODULE.apply_request(
                self.request(
                    {"indicator": {"preset": "halo"}},
                    before["revision"],
                )
            )

            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertEqual(result["snapshot"]["settings"]["indicator"]["preset"], "halo")
            self.assertFalse(MODULE.transaction_journal_path().exists())

    def test_refine_test_recovers_a_prepared_transaction_before_dispatch(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            before = MODULE.snapshot()

            def crash_after_write(path, text, limit, label, expected):
                MODULE._write_checked(path, text, limit, label, expected)
                raise SimulatedCrash("injected crash")

            with self.assertRaises(SimulatedCrash):
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        },
                        before["revision"],
                    ),
                    writer=crash_after_write,
                )

            with patch.object(MODULE.REFINE, "complete", return_value="Refined.") as complete:
                result = MODULE.test_refine_request(
                    {
                        "protocol": 1,
                        "expectedRevision": before["revision"],
                        "sample": "um hello",
                        "candidate": {"provider": "local"},
                    }
                )

            self.assertEqual(result["output"], "Refined.")
            complete.assert_called_once()
            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())
            self.assertFalse(MODULE.transaction_journal_path().exists())

    def test_post_replace_failure_still_rolls_back_that_write(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            calls = 0

            def commit_then_fail_second(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                MODULE._write_checked(path, text, limit, label, expected)
                if calls == 2:
                    raise OSError("injected directory-fsync-style failure")

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        }
                    ),
                    writer=commit_then_fail_second,
                )
            self.assertEqual(caught.exception.code, "commit_failed_rolled_back")
            self.assertEqual(prompt.read_text(encoding="utf-8"), "original prompt\n")
            self.assertFalse(MODULE.REFINE.dictionary_path().exists())

    def test_rollback_refuses_to_overwrite_a_concurrent_replacement(self) -> None:
        with self.isolated():
            prompt = MODULE.REFINE.prompt_path()
            prompt.write_text("original prompt\n", encoding="utf-8")
            calls = 0

            def race_then_fail(path, text, limit, label, expected):
                nonlocal calls
                calls += 1
                if calls == 2:
                    prompt.write_text("concurrent owner\n", encoding="utf-8")
                    raise OSError("injected failure after concurrent replacement")
                MODULE._write_checked(path, text, limit, label, expected)

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "prompt": "replacement prompt\n",
                                "dictionary": "Voxtype\n",
                            }
                        }
                    ),
                    writer=race_then_fail,
                )
            self.assertEqual(caught.exception.code, "commit_failed_recovery_required")
            self.assertTrue(caught.exception.committed)
            self.assertEqual(prompt.read_text(encoding="utf-8"), "concurrent owner\n")
            self.assertTrue(MODULE.transaction_journal_path().exists())

    def test_snapshot_rejects_symlinked_settings_sources(self) -> None:
        with self.isolated() as (root, _config):
            victim = root / "victim"
            victim.write_text("{}\n", encoding="utf-8")
            for path in (
                MODULE.REFINE.refine_config_path(),
                MODULE.REFINE.prompt_path(),
                MODULE.REFINE.dictionary_path(),
                MODULE.indicator_path(),
                MODULE.hook_state_path(),
            ):
                with self.subTest(path=path):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.symlink_to(victim)
                    with self.assertRaisesRegex(RuntimeError, "unsafe"):
                        MODULE.snapshot()
                    path.unlink()

    def test_apply_skips_preplanted_random_temp_symlink(self) -> None:
        with self.isolated() as (root, _config):
            indicator = MODULE.indicator_path()
            indicator.parent.mkdir(parents=True)
            victim = root / "victim"
            victim.write_text("sentinel\n", encoding="utf-8")
            planted = indicator.parent / f".{indicator.name}.tmp.deadbeef"
            planted.symlink_to(victim)
            with patch.object(
                MODULE.REFINE.secrets,
                "token_hex",
                side_effect=(
                    "journalprep",
                    "deadbeef",
                    "cafebabe",
                    "journalcommit",
                    "journalcas",
                ),
            ):
                MODULE.apply_request(self.request({"indicator": {"preset": "halo"}}))
            self.assertEqual(victim.read_text(encoding="utf-8"), "sentinel\n")
            self.assertTrue(planted.is_symlink())
            self.assertEqual(json.loads(indicator.read_text(encoding="utf-8"))["preset"], "halo")

    def test_foreign_hook_is_refused_without_restart_or_overwrite(self) -> None:
        with self.isolated() as (_root, config):
            original = '[output.post_process]\ncommand = "/bin/cat"\ntimeout_ms = 1000\n'
            config.write_text(original, encoding="utf-8")
            runner = RecordingRunner()
            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(self.request({"refine": {"enabled": True}}), runner)
            self.assertEqual(caught.exception.code, "post_process_conflict")
            self.assertEqual(config.read_text(encoding="utf-8"), original)
            self.assertEqual(runner.commands, [])

    def test_enable_disable_restores_absent_hook_and_restarts_only_for_hook(self) -> None:
        with self.isolated() as (_root, config):
            runner = RecordingRunner()
            enabled = MODULE.apply_request(self.request({"refine": {"enabled": True}}), runner)
            self.assertTrue(enabled["snapshot"]["settings"]["refine"]["enabled"])
            self.assertIn(MODULE.refine_command(), config.read_text(encoding="utf-8"))
            self.assertEqual(len(runner.commands), 2)
            state = json.loads(MODULE.hook_state_path().read_text(encoding="utf-8"))
            self.assertEqual(state["prior"], {"assignment": None, "kind": "none"})

            disabled = MODULE.apply_request(
                self.request(
                    {"refine": {"enabled": False}},
                    enabled["snapshot"]["revision"],
                ),
                runner,
            )
            self.assertFalse(disabled["snapshot"]["settings"]["refine"]["enabled"])
            self.assertNotIn("command =", config.read_text(encoding="utf-8"))
            self.assertEqual(len(runner.commands), 4)

            no_restart = MODULE.apply_request(
                self.request(
                    {"refine": {"prompt": "Next dictation only.\n"}},
                    disabled["snapshot"]["revision"],
                ),
                runner,
            )
            self.assertFalse(no_restart["restart"]["required"])
            self.assertEqual(len(runner.commands), 4)

    def test_restart_failure_reports_committed_without_rolling_back_files(self) -> None:
        with self.isolated() as (_root, config):
            def failed_restart(_command):
                raise subprocess.CalledProcessError(1, ["systemctl"])

            with self.assertRaises(MODULE.SettingsError) as caught:
                MODULE.apply_request(
                    self.request(
                        {
                            "refine": {
                                "enabled": True,
                                "prompt": "Saved before restart.\n",
                            }
                        }
                    ),
                    failed_restart,
                )
            self.assertEqual(caught.exception.code, "restart_failed")
            self.assertTrue(caught.exception.committed)
            self.assertIn(MODULE.refine_command(), config.read_text(encoding="utf-8"))
            self.assertEqual(
                MODULE.REFINE.prompt_path().read_text(encoding="utf-8"),
                "Saved before restart.\n",
            )
            self.assertFalse(MODULE.transaction_journal_path().exists())
            self.assertTrue(MODULE.snapshot()["settings"]["refine"]["enabled"])

    def test_disable_restores_recorded_foreign_hook_exactly(self) -> None:
        with self.isolated() as (_root, config):
            canonical = f'[output.post_process]\ncommand = {json.dumps(MODULE.refine_command())}\n'
            config.write_text(canonical, encoding="utf-8")
            foreign = '  command = "/opt/custom filter"  # preserve exactly\n'
            state = {
                "version": 1,
                "config": str(config),
                "managedCommand": MODULE.refine_command(),
                "active": True,
                "prior": {"kind": "foreign", "assignment": foreign},
            }
            MODULE.REFINE.atomic_write_text(
                MODULE.hook_state_path(),
                json.dumps(state) + "\n",
                MODULE.MAX_HOOK_STATE_BYTES,
                "refine hook state",
                expected=None,
            )
            result = MODULE.apply_request(
                self.request({"refine": {"enabled": False}}),
                RecordingRunner(),
            )
            self.assertIn(foreign, config.read_text(encoding="utf-8"))
            self.assertEqual(result["snapshot"]["settings"]["refine"]["hook"], "foreign")
            self.assertFalse(result["snapshot"]["settings"]["refine"]["enabled"])

    def test_exact_legacy_prism_trampoline_is_migrated_without_shadow_table(self) -> None:
        with self.isolated() as (_root, config):
            wrapper = MODULE.legacy_trampoline_path()
            wrapper.write_text(
                '#!/usr/bin/python3\n'
                '"""Voxtype post-process trampoline into Voxtype Prism.\n"""\n'
                'from pathlib import Path\n'
                'import runpy\n\n'
                'runpy.run_path(\n'
                f'    str(Path({json.dumps(MODULE.refine_command())})),\n'
                '    run_name="__main__",\n'
                ')\n',
                encoding="utf-8",
            )
            legacy_line = f'command = {json.dumps(str(wrapper))}\n'
            config.write_text(
                f'[output.post_process]\n{legacy_line}timeout_ms = 30000\n',
                encoding="utf-8",
            )
            before = MODULE.snapshot()
            self.assertTrue(before["settings"]["refine"]["enabled"])
            self.assertEqual(before["settings"]["refine"]["hook"], "legacy-prism")
            result = MODULE.apply_request(
                self.request({"refine": {"enabled": True}}, before["revision"]),
                RecordingRunner(),
            )
            text = config.read_text(encoding="utf-8")
            self.assertIn(f'command = {json.dumps(MODULE.refine_command())}', text)
            self.assertNotIn("\n[post_process]\n", text)
            state = json.loads(MODULE.hook_state_path().read_text(encoding="utf-8"))
            self.assertTrue(state["migration"])
            self.assertEqual(state["prior"]["assignment"], legacy_line)
            self.assertEqual(result["snapshot"]["settings"]["refine"]["hook"], "prism")

    def test_exact_legacy_trampoline_to_identical_helper_copy_is_migrated(self) -> None:
        with self.isolated() as (root, config):
            old_helper = root / "old-checkout" / "scripts" / "voxtype-refine"
            old_helper.parent.mkdir(parents=True)
            old_helper.write_bytes(Path(MODULE.refine_command()).read_bytes())
            wrapper = MODULE.legacy_trampoline_path()
            wrapper.write_text(
                '#!/usr/bin/python3\n'
                '"""Voxtype post-process trampoline into Voxtype Prism.\n"""\n'
                'from pathlib import Path\n'
                'import runpy\n\n'
                'runpy.run_path(\n'
                f'    str(Path({json.dumps(str(old_helper))})),\n'
                '    run_name="__main__",\n'
                ')\n',
                encoding="utf-8",
            )
            legacy_line = f'command = {json.dumps(str(wrapper))}\n'
            config.write_text(
                f'[output.post_process]\n{legacy_line}timeout_ms = 30000\n',
                encoding="utf-8",
            )

            before = MODULE.snapshot()
            self.assertTrue(before["settings"]["refine"]["enabled"])
            self.assertEqual(before["settings"]["refine"]["hook"], "legacy-prism")
            result = MODULE.apply_request(
                self.request({"refine": {"enabled": True}}, before["revision"]),
                RecordingRunner(),
            )

            self.assertIn(
                f'command = {json.dumps(MODULE.refine_command())}',
                config.read_text(encoding="utf-8"),
            )
            self.assertEqual(result["snapshot"]["settings"]["refine"]["hook"], "prism")

    def test_exact_legacy_trampoline_to_modified_helper_remains_foreign(self) -> None:
        with self.isolated() as (root, config):
            old_helper = root / "old-checkout" / "scripts" / "voxtype-refine"
            old_helper.parent.mkdir(parents=True)
            old_helper.write_text("#!/usr/bin/python3\nprint('not Prism')\n", encoding="utf-8")
            wrapper = MODULE.legacy_trampoline_path()
            wrapper.write_text(
                'from pathlib import Path\n'
                'import runpy\n'
                'runpy.run_path(\n'
                f'    str(Path({json.dumps(str(old_helper))})),\n'
                '    run_name="__main__",\n'
                ')\n',
                encoding="utf-8",
            )
            config.write_text(
                f'[output.post_process]\ncommand = {json.dumps(str(wrapper))}\n',
                encoding="utf-8",
            )

            self.assertEqual(MODULE.snapshot()["settings"]["refine"]["hook"], "foreign")

    def test_unknown_wrapper_remains_foreign(self) -> None:
        with self.isolated() as (_root, config):
            wrapper = MODULE.legacy_trampoline_path()
            wrapper.write_text(
                f'import runpy\nrunpy.run_path({json.dumps(MODULE.refine_command())}, run_name="__main__")\n',
                encoding="utf-8",
            )
            config.write_text(
                f'[output.post_process]\ncommand = {json.dumps(str(wrapper))}\n',
                encoding="utf-8",
            )
            self.assertEqual(MODULE.snapshot()["settings"]["refine"]["hook"], "foreign")

    def test_errors_never_echo_provider_secrets_or_sample(self) -> None:
        with self.isolated():
            current = MODULE.snapshot()
            sample = "private dictated sentence"
            secret = "Bearer secret-access-token"
            with patch.object(MODULE.REFINE, "complete", side_effect=RuntimeError(secret)):
                with self.assertRaises(MODULE.SettingsError) as caught:
                    MODULE.test_refine_request(
                        {
                            "protocol": 1,
                            "expectedRevision": current["revision"],
                            "sample": sample,
                            "candidate": {"provider": "local"},
                        }
                    )
            serialized = json.dumps(MODULE.failure_payload(caught.exception))
            self.assertNotIn(secret, serialized)
            self.assertNotIn(sample, serialized)

    def test_stale_test_revision_never_calls_provider(self) -> None:
        with self.isolated():
            stale = MODULE.snapshot()["revision"]
            MODULE.REFINE.prompt_path().write_text("changed\n", encoding="utf-8")
            with patch.object(MODULE.REFINE, "complete") as complete:
                with self.assertRaises(MODULE.SettingsError) as caught:
                    MODULE.test_refine_request(
                        {
                            "protocol": 1,
                            "expectedRevision": stale,
                            "sample": "um hello",
                            "candidate": {"provider": "local"},
                        }
                    )
            self.assertEqual(caught.exception.code, "revision_conflict")
            complete.assert_not_called()

    def test_test_refine_rechecks_revision_immediately_before_dispatch(self) -> None:
        with self.isolated():
            current = MODULE.snapshot()
            original_candidate = MODULE._candidate_refine

            def candidate_then_concurrent_change(saved, candidate):
                result = original_candidate(saved, candidate)
                MODULE.REFINE.prompt_path().write_text("changed during request\n", encoding="utf-8")
                return result

            with patch.object(MODULE, "_candidate_refine", side_effect=candidate_then_concurrent_change):
                with patch.object(MODULE.REFINE, "complete") as complete:
                    with self.assertRaises(MODULE.SettingsError) as caught:
                        MODULE.test_refine_request(
                            {
                                "protocol": 1,
                                "expectedRevision": current["revision"],
                                "sample": "um hello",
                                "candidate": {"provider": "local"},
                            }
                        )
            self.assertEqual(caught.exception.code, "revision_conflict")
            complete.assert_not_called()

    def test_fake_provider_end_to_end_uses_unsaved_candidate_without_persisting(self) -> None:
        requests: list[dict] = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
                length = int(self.headers["Content-Length"])
                requests.append(json.loads(self.rfile.read(length)))
                body = json.dumps(
                    {"choices": [{"message": {"content": "Ship the Voxtype indicator."}}]}
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, _format: str, *_args) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.isolated():
                os.environ["VOXTYPE_LOCAL_BASE_URL"] = f"http://127.0.0.1:{server.server_port}/v1"
                before = MODULE.snapshot()
                result = MODULE.test_refine_request(
                    {
                        "protocol": 1,
                        "expectedRevision": before["revision"],
                        "sample": "um ship the vox type indicator",
                        "candidate": {
                            "provider": "local",
                            "model": "fake-model",
                            "prompt": "Fix it.",
                            "dictionary": "vox type → Voxtype\n",
                        },
                    }
                )
                after = MODULE.snapshot()
                self.assertEqual(result["output"], "Ship the Voxtype indicator.")
                self.assertEqual(result["provider"], "local")
                self.assertEqual(before["revision"], after["revision"])
                self.assertFalse(MODULE.REFINE.refine_config_path().exists())
                sent = requests[0]
                self.assertEqual(sent["model"], "fake-model")
                self.assertIn("Fix it.", sent["messages"][0]["content"])
                self.assertIn(MODULE.REFINE.FINAL_CONTRACT, sent["messages"][0]["content"])
                self.assertNotIn("vox type → Voxtype", sent["messages"][0]["content"])
                self.assertEqual(
                    json.loads(sent["messages"][1]["content"]),
                    {
                        "preferred_spellings": ["vox type → Voxtype"],
                        "transcript": "um ship the vox type indicator",
                    },
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_cli_returns_one_structured_json_error(self) -> None:
        with self.isolated():
            process = subprocess.run(
                [sys.executable, str(SCRIPT), "apply"],
                input=b"not-json",
                capture_output=True,
                env=os.environ.copy(),
            )
            payload = json.loads(process.stdout)
            self.assertEqual(process.returncode, 2)
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["error"]["code"], "invalid_request")
            self.assertIn("message", payload["error"])
            self.assertEqual(process.stdout.count(b"\n"), 1)


if __name__ == "__main__":
    unittest.main()
