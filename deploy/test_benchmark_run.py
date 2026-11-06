import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import benchmark_host as host
import benchmark_provenance as provenance
import benchmark_run as runner


class FakeRemote:
    instances = []
    mismatch = False
    recovery_failure = False

    def __init__(self, output):
        self.instances.append(self)
        self.output = output
        self.commands = []
        self.closed = False
        self.process = SimpleNamespace(stdin=io.BytesIO())
        self.ready = {"status": "ready", "application": host.baseline_application(),
                      "frozen_fixture_restored": True, "operation_id": "operation-" + "1" * 12,
                      "recovery_snapshot": "snapshot-example", "controller_sha256": {"controller": "test"},
                      "inventory": {"table_counts": {"organizations": 1, "workflows": 1, "tickets": 12}},
                      "identity": {"image": host.BASE_IMAGE, "application_commit": host.BASE_COMMIT,
                                   "database": host.DATABASE, "project": host.PROJECT,
                                   "fixture_sha256": host.BASE_HASH, "postgres_image": host.POSTGRES_IMAGE,
                                   "pool_size": 20 if self.mismatch else 10, "endpoint_host": host.DOMAIN}}

    def send(self, value):
        self.commands.append(value)

    def wait(self, name, timeout):
        if name == "ready":
            return {"ready": self.ready}
        if self.recovery_failure:
            raise host.GuardError("Recovery could not be confirmed")
        return {"report": {"status": self.commands[-1]["action"], "operation_id": self.ready["operation_id"],
                           "final_identity": self.ready["identity"], "restoration": {"status": "recovered"}}}

    def close(self):
        self.closed = True


class RunnerTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.args = SimpleNamespace(candidate=None, workload=self.root / "school.js", fixture=self.root / "manifest.json",
                                    output=self.root / "results", users=1, mode="pilot", seconds=10, warmup=0)
        self.exit_code = 0
        self.summary_valid = True
        FakeRemote.instances = []
        FakeRemote.mismatch = False
        FakeRemote.recovery_failure = False
        for target, name, value in [
            (runner, "Remote", FakeRemote), (runner, "direct_preflight", lambda out: {"tls_verified": True}),
            (runner.platform, "platform", lambda: "test-runner"),
            (provenance, "fixture_identity", lambda path: {"archive_sha256": host.BASE_HASH, "source_commit": host.BASE_COMMIT}),
            (provenance, "workload_identity", lambda path: {"sha256": provenance.WORKLOAD_SHA256}),
        ]:
            patcher = patch.object(target, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for target, name in [(runner.threading, "Thread"), (runner, "print")]:
            patcher = patch.object(target, name)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(runner.subprocess, "run", side_effect=self.browser)
        patcher.start()
        self.addCleanup(patcher.stop)

    def browser(self, command, **kwargs):
        self.assertEqual(command[:2], ["docker", "run"])
        self.assertIn(provenance.K6, command)
        output = next(self.args.output.iterdir())
        metrics = {"business_saves": {"values": {"count": 2}}, "business_failure": {"values": {"rate": 0}},
                   "checks": {"values": {"passes": 2, "fails": 0}}} if self.summary_valid else {}
        (output / "summary.json").write_text(json.dumps({"metrics": metrics}))
        return subprocess.CompletedProcess(command, self.exit_code)

    def metadata(self):
        return json.loads(next(self.args.output.glob("*/metadata.json")).read_text())

    def test_success_requires_browser_checks_and_confirmed_host_restoration(self):
        runner.run(self.args)
        metadata = self.metadata()
        self.assertEqual(metadata["status"], "passed")
        self.assertEqual(metadata["provenance"]["fixture"]["source_commit"], host.BASE_COMMIT)
        self.assertEqual(FakeRemote.instances[0].commands[-1]["action"], "finish")
        self.assertTrue(FakeRemote.instances[0].closed)

    def test_browser_failure_aborts_and_preserves_recovery_evidence(self):
        self.exit_code = 99
        with self.assertRaises(host.GuardError):
            runner.run(self.args)
        self.assertEqual(self.metadata()["status"], "failed")
        self.assertEqual(self.metadata()["restoration"]["restoration"]["status"], "recovered")
        self.assertEqual(FakeRemote.instances[0].commands[-1]["action"], "abort")

    def test_zero_exit_without_checked_business_operations_cannot_claim_success(self):
        self.summary_valid = False
        with self.assertRaises(KeyError):
            runner.run(self.args)
        self.assertEqual(self.metadata()["status"], "failed")
        self.assertEqual(FakeRemote.instances[0].commands[-1]["action"], "abort")

    def test_provenance_mismatch_still_restores_without_starting_browser(self):
        FakeRemote.mismatch = True
        with patch.object(runner.subprocess, "run") as browser, self.assertRaises(host.GuardError):
            runner.run(self.args)
        browser.assert_not_called()
        self.assertEqual(self.metadata()["status"], "failed")
        self.assertEqual(FakeRemote.instances[0].commands[-1]["action"], "abort")

    def test_unconfirmed_restoration_cannot_become_success_and_metadata_is_persisted(self):
        FakeRemote.recovery_failure = True
        with self.assertRaises(host.GuardError):
            runner.run(self.args)
        self.assertEqual(self.metadata()["status"], "failed")
        self.assertIn("ended_at", self.metadata())
        self.assertTrue(FakeRemote.instances[0].closed)

    def test_browser_timeout_requests_abort_and_waits_for_restoration(self):
        with patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("browser", 190)):
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run(self.args)
        self.assertEqual(self.metadata()["restoration"]["restoration"]["status"], "recovered")
        self.assertEqual(FakeRemote.instances[0].commands[-1]["action"], "abort")
