import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import benchmark_host as host
import benchmark_rollout as rollout
import test_benchmark_host as fixture


def candidate():
    return {"schema": 2, "application_commit": "a" * 40,
            "image": host.REPOSITORY + "@sha256:" + "b" * 64, "platform": "linux/arm64",
            "checks_run_id": 123, "checks_url": "https://github.com/iagobg/instantflow/actions/runs/123",
            "publication_run_id": 456, "publication_attempt": 1}


class SimulatedCrash(BaseException):
    pass


class RolloutHost(rollout.Rollout, fixture.FakeHost):
    def __init__(self, root):
        super().__init__(root)
        self.archives = {}
        self.failure = None
        self.migrator = None
        self.restore_failures = 0
        self.smokes = 0
        self.migration_env = None
        self.web_missing = False

    def smoke(self):
        self.smokes += 1
        if self.failure == "smoke" and self.smokes == 2:
            raise host.GuardError("Injected smoke failure")
        self.events.append(("smoke",))
        return {"authenticated_record_read": True}

    def docker(self, *args, label, **kwargs):
        self.events.append(("rollout-docker", args))
        if args[0] == "compose":
            if "stop" in args:
                self.containers[0]["State"]["Running"] = False
            elif "up" in args:
                if self.failure == "start":
                    self.failure = None
                    raise host.GuardError("Injected startup failure")
                config = host.read_json(host.ROOT / "compose.json")
                self.containers[0]["Config"]["Image"] = config["services"]["web"]["image"]
                self.containers[0]["State"]["Running"] = True
                self.web_missing = False
            else:
                raise AssertionError(args)
            return b""
        if args[:2] == ("image", "inspect"):
            result = copy.deepcopy(self.image)
            result["RepoDigests"] = [args[2]]
            if args[2] != host.BASE_IMAGE:
                result["Config"]["Labels"]["org.opencontainers.image.revision"] = candidate()["application_commit"]
            return json.dumps([result]).encode()
        if args[0] == "pull":
            if self.failure == "pull":
                raise host.GuardError("Injected pull failure")
            return b""
        if args[0] == "create":
            name = args[args.index("--name") + 1]
            label_arg = args[args.index("--label") + 1]
            self.migration_env = host.read_env(Path(args[args.index("--env-file") + 1]))
            self.migrator = {"Id": "owned-migrator", "Name": "/" + name,
                "Config": {"Image": candidate()["image"], "Labels": dict([label_arg.split("=", 1)])},
                "NetworkSettings": {"Networks": {host.PROJECT + "_database": {}}},
                "State": {"Running": False, "ExitCode": 0}}
            return b"owned-migrator"
        if args[0] == "start":
            self.live_counts["new_candidate_table"] = 0
            if self.failure == "migration":
                self.migrator["State"]["ExitCode"] = 1
            return b""
        if args[:2] == ("ps", "-aq"):
            if args[-1] == "name=^/" + host.PROJECT + "-web$":
                return b"" if self.web_missing else b"benchmark-web"
            return b"owned-migrator" if self.migrator else b""
        if args[0] == "inspect" and len(args) == 2:
            if args[1] == host.PROJECT + "-db":
                return json.dumps([self.containers[1]]).encode()
            return json.dumps([self.migrator]).encode()
        if args[0] == "inspect" and self.web_missing:
            raise host.GuardError("Web missing during interrupted recreation")
        if args[0] == "rm":
            self.migrator = None
            return b""
        if "pg_dump" in args:
            data = json.dumps(self.live_counts).encode()
            kwargs["stdout"].write(data)
            return None
        if "pg_restore" in args:
            if self.restore_failures:
                self.restore_failures -= 1
                raise host.GuardError("Injected restore failure")
            data = kwargs["stdin"].read()
            counts = {"organizations": 1, "workflows": 1, "tickets": 12, "schema_migrations": 2} if data == b"frozen-baseline" else json.loads(data)
            if args[-1] == host.DATABASE:
                self.live_counts = copy.deepcopy(counts)
            else:
                self.restore_counts = copy.deepcopy(counts)
            return b""
        return super().docker(*args, label=label, **kwargs)

    def sql(self, database, statement):
        if statement.startswith(('DROP DATABASE IF EXISTS "' + host.DATABASE, 'CREATE DATABASE "' + host.DATABASE + '"')):
            self.events.append(("database-mutation", database, statement))
            if statement.startswith("DROP"):
                self.databases.discard(host.DATABASE)
                self.live_counts = {}
            else:
                self.databases.add(host.DATABASE)
            return ""
        return super().sql(database, statement)


class RolloutTest(unittest.TestCase):
    # Reuse the target fixture setup without inheriting/rerunning preservation tests.
    setUp = fixture.BenchmarkHostTest.setUp
    write = fixture.BenchmarkHostTest.write

    def controller(self):
        return RolloutHost(self.root)

    def test_candidate_migrates_with_separate_credentials_then_restores_image_and_data(self):
        controller = self.controller()
        original = copy.deepcopy(controller.live_counts)
        with patch.object(rollout, "verify_publication") as verify:
            result = controller.switch(candidate())
            verify.assert_called_once_with(candidate())
        self.assertEqual(result["status"], "ready")
        self.assertEqual(controller.guard()["image"], candidate()["image"])
        self.assertIn("new_candidate_table", controller.live_counts)
        self.assertEqual(controller.migration_env["RUNTIME_DB_PASSWORD"], "r" * 48)
        self.assertIn("postgres:" + "p" * 48, controller.migration_env["OPERATOR_DATABASE_URL"])
        self.assertNotIn("OPERATOR_DATABASE_URL", host.read_env(self.root / "web.env"))
        self.assertFalse(list((self.root / "operations").glob("*/migration.env")))
        self.assertIsNone(controller.migrator)
        self.assertFalse((self.root / "pending-operation.json").exists())
        controller.switch(host.baseline_application(), restore_id=result["recovery_snapshot"])
        self.assertEqual(controller.live_counts, original)
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)
        self.assertEqual(controller.databases, {host.DATABASE, "postgres"})
        mutations = [e for e in controller.events if e[0] == "database-mutation"]
        self.assertTrue(mutations)
        self.assertTrue(all(e[1] == "postgres" and host.DATABASE in e[2] for e in mutations))

    def test_frozen_fixture_migrates_after_reset_without_losing_live_recovery_snapshot(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"):
            result = controller.switch(candidate(), fixture=True)
        self.assertEqual(controller.live_counts["tickets"], 12)
        self.assertIn("new_candidate_table", controller.live_counts)
        snapshot, _ = controller.load_snapshot(result["recovery_snapshot"])
        self.assertEqual(snapshot["inventory"]["table_counts"]["tickets"], 15)

    def test_migration_start_or_smoke_failure_recovers_database_and_image(self):
        for failure in ["migration", "start", "smoke"]:
            with self.subTest(failure=failure):
                controller = self.controller()
                controller.failure = failure
                with patch.object(rollout, "verify_publication"), self.assertRaisesRegex(host.GuardError, "previous database and application recovered"):
                    controller.switch(candidate())
                self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)
                self.assertEqual(controller.live_counts["tickets"], 15)
                self.assertNotIn("new_candidate_table", controller.live_counts)
                self.assertIsNone(controller.migrator)
                self.assertFalse((self.root / "pending-operation.json").exists())

    def test_pull_provenance_or_source_smoke_failure_does_not_stop_or_change_database(self):
        for failure in ["pull", "provenance", "source-smoke"]:
            controller = self.controller()
            controller.failure = failure
            with patch.object(rollout, "verify_publication", side_effect=host.GuardError("refused") if failure == "provenance" else None):
                if failure == "source-smoke":
                    controller.smoke = lambda: host.require(False, "source smoke failure")
                with self.assertRaises(host.GuardError):
                    controller.switch(candidate())
            self.assertTrue(controller.containers[0]["State"]["Running"])
            self.assertFalse((self.root / "pending-operation.json").exists())
            self.assertFalse(any(e[0] == "database-mutation" for e in controller.events))

    def test_failed_recovery_retains_journal_blocks_normal_operations_and_can_retry(self):
        controller = self.controller()
        controller.failure = "migration"
        real_recover = controller.recover
        with patch.object(rollout, "verify_publication"), patch.object(controller, "recover", side_effect=host.GuardError("unavailable")):
            with self.assertRaisesRegex(host.GuardError, "recovery incomplete"):
                controller.switch(candidate())
        with self.assertRaisesRegex(host.GuardError, "Interrupted operation"):
            controller.guard()
        controller.failure = None
        result = real_recover()
        self.assertEqual(result["status"], "recovered")
        self.assertNotIn("new_candidate_table", controller.live_counts)
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)

    def test_restore_failure_midway_is_retryable_and_never_starts_app_on_incomplete_database(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"), patch.object(controller, "recover", side_effect=SimulatedCrash):
            with patch.object(controller, "migrate", side_effect=SimulatedCrash):
                with self.assertRaises(host.GuardError):
                    controller.switch(candidate())
        def fail_after_drop(archive, inventory):
            controller.sql("postgres", 'DROP DATABASE IF EXISTS "' + host.DATABASE + '" WITH (FORCE);')
            raise host.GuardError("restore failed")

        with patch.object(controller, "replace_database", side_effect=fail_after_drop), self.assertRaises(host.GuardError):
            controller.recover()
        self.assertFalse(controller.containers[0]["State"]["Running"])
        self.assertTrue((self.root / "pending-operation.json").exists())
        controller.recover()
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)

    def test_restore_rejects_tampering_and_schema_image_mismatch_before_stop(self):
        controller = self.controller()
        snapshot = controller.snapshot()
        with self.assertRaisesRegex(host.GuardError, "paired"):
            controller.switch(candidate(), restore_id=snapshot["snapshot_id"])
        archive = self.root / "snapshots" / snapshot["snapshot_id"] / "database.dump"
        archive.write_bytes(b"modified")
        with self.assertRaisesRegex(host.GuardError, "checksum"):
            controller.switch(host.baseline_application(), restore_id=snapshot["snapshot_id"])
        self.assertFalse(any(e[0] == "database-mutation" for e in controller.events))
        self.assertTrue(controller.containers[0]["State"]["Running"])

    def test_recovery_refuses_unrelated_database_and_config_drift(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"), patch.object(controller, "recover", side_effect=SimulatedCrash), patch.object(controller, "migrate", side_effect=SimulatedCrash):
            with self.assertRaises(host.GuardError):
                controller.switch(candidate())
        controller.databases.add("serving")
        with self.assertRaisesRegex(host.GuardError, "exclusive"):
            controller.recover()
        controller.databases.remove("serving")
        self.write("web.env", (self.root / "web.env").read_text().replace("POOL_SIZE=10", "POOL_SIZE=11"))
        with self.assertRaisesRegex(host.GuardError, "drift"):
            controller.recover()
        self.assertFalse(any(e[0] == "database-mutation" for e in controller.events))

    def test_no_downgrade_of_candidate_schema_without_matching_archive(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"):
            controller.switch(candidate())
        with self.assertRaisesRegex(host.GuardError, "matching snapshot"):
            controller.switch(host.baseline_application())
        self.assertEqual(controller.guard()["image"], candidate()["image"])
        self.assertIn("new_candidate_table", controller.live_counts)

    def test_recovery_can_recreate_web_after_interrupted_compose_recreation(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"), patch.object(controller, "recover", side_effect=SimulatedCrash), patch.object(controller, "start", side_effect=SimulatedCrash):
            with self.assertRaises(host.GuardError):
                controller.switch(candidate())
        controller.web_missing = True
        controller.recover()
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)
        self.assertEqual(controller.live_counts["tickets"], 15)

    def test_interruption_before_verified_backup_only_restarts_original_application(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"), patch.object(controller, "snapshot", side_effect=SimulatedCrash), patch.object(controller, "recover", side_effect=SimulatedCrash):
            with self.assertRaises(host.GuardError):
                controller.switch(candidate())
        self.assertIsNone(controller.journal()["recovery_snapshot"])
        controller.recover()
        self.assertFalse(any(e[0] == "database-mutation" for e in controller.events))
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)

    def test_recorded_recovery_manifest_cannot_be_substituted(self):
        controller = self.controller()
        with patch.object(rollout, "verify_publication"), patch.object(controller, "migrate", side_effect=SimulatedCrash), patch.object(controller, "recover", side_effect=SimulatedCrash):
            with self.assertRaises(host.GuardError):
                controller.switch(candidate())
        snapshot_id = controller.journal()["recovery_snapshot"]
        path = self.root / "snapshots" / snapshot_id / "snapshot.json"
        snapshot = host.read_json(path)
        snapshot["inventory"]["table_counts"]["tickets"] += 1
        path.write_text(json.dumps(snapshot))
        with self.assertRaisesRegex(host.GuardError, "manifest changed"):
            controller.recover()
        self.assertFalse(any(e[0] == "database-mutation" for e in controller.events))

    def test_success_cannot_claim_candidate_while_old_image_is_still_running(self):
        controller = self.controller()
        real_start = controller.start
        first = True

        def stale_start():
            nonlocal first
            if first:
                first = False
                controller.containers[0]["State"]["Running"] = True
            else:
                real_start()

        with patch.object(rollout, "verify_publication"), patch.object(controller, "start", side_effect=stale_start):
            with self.assertRaisesRegex(host.GuardError, "previous database and application recovered"):
                controller.switch(candidate())
        self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)


class ProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.checks = {"id": 123, "head_sha": candidate()["application_commit"], "status": "completed",
                       "conclusion": "success", "event": "push", "path": ".github/workflows/checks.yml",
                       "repository": {"full_name": "iagobg/instantflow"},
                       "head_repository": {"full_name": "iagobg/instantflow"}}
        self.publication = {**self.checks, "id": 456, "run_attempt": 1, "event": "workflow_dispatch",
                            "path": ".github/workflows/benchmark-candidate.yml"}

    def test_exact_completed_checks_and_publication_required(self):
        with patch.object(rollout, "github_run", side_effect=[self.checks, self.publication]):
            rollout.verify_publication(candidate())
        for field, value in [("head_sha", "c" * 40), ("conclusion", "failure"), ("run_attempt", 2),
                             ("path", ".github/workflows/deploy.yml"), ("status", "in_progress")]:
            with patch.object(rollout, "github_run", side_effect=[self.checks, {**self.publication, field: value}]), self.assertRaises(host.GuardError):
                rollout.verify_publication(candidate())
        with patch.object(rollout, "github_run", side_effect=RuntimeError("secret")), self.assertRaisesRegex(host.GuardError, "could not be verified"):
            rollout.verify_publication(candidate())

    def test_old_or_mutable_manifests_refused(self):
        for field, value in [("schema", 1), ("image", "ghcr.io/iagobg/instantflow:latest"),
                             ("platform", "linux/amd64"), ("publication_run_id", True)]:
            with self.assertRaises(host.GuardError):
                host.validate_application({**candidate(), field: value})
