import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

import benchmark_host as host
import benchmark_provenance as provenance
import test_benchmark_rollout as fixtures


class ProvenanceTest(unittest.TestCase):
    def test_candidate_identity_is_separate_from_frozen_fixture_identity(self):
        application = fixtures.candidate()
        fixture = {"archive_sha256": host.BASE_HASH, "source_commit": host.BASE_COMMIT}
        ready = {"status": "ready", "application": application, "frozen_fixture_restored": True,
                 "operation_id": "operation-" + "1" * 12, "recovery_snapshot": "snapshot-example",
                 "inventory": {"schema_versions": ["20261106165113"],
                               "table_counts": {"organizations": 1, "workflows": 1, "tickets": 12}},
                 "identity": {"image": application["image"], "application_commit": application["application_commit"],
                              "fixture_sha256": host.BASE_HASH, "database": host.DATABASE, "project": host.PROJECT,
                              "postgres_image": host.POSTGRES_IMAGE, "pool_size": 10, "endpoint_host": host.DOMAIN},
                 "controller_sha256": {"script": "synthetic"}, "metrics_settings": {},
                 "statement_statistics_available": False}
        result = provenance.manifest(application, ready, fixture, {"sha256": provenance.WORKLOAD_SHA256})
        self.assertEqual(result["application"]["application_commit"], "a" * 40)
        self.assertEqual(result["fixture"]["source_commit"], host.BASE_COMMIT)
        for field, value in [("image", host.BASE_IMAGE), ("application_commit", host.BASE_COMMIT),
                             ("fixture_sha256", "changed"), ("database", "serving"), ("pool_size", 20)]:
            changed = copy.deepcopy(ready)
            changed["identity"][field] = value
            with self.assertRaises(host.GuardError):
                provenance.manifest(application, changed, fixture, {})

    def test_private_accounts_never_enter_public_fixture_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "manifest.json"
            fixture = {"fixture": "school-v1", "application_commit": host.BASE_COMMIT,
                "expected": {"organizations": 1, "workflows": 1, "cases": 12, "load_actors": 10},
                "actors": [{"user_id": i, "ticket_id": i, "email": f"actor-{i}@example.test",
                            "password": "private-value"} for i in range(10)]}
            host.write_json(path, fixture)
            result = provenance.fixture_identity(path)
            self.assertNotIn("private-value", json.dumps(result))
            self.assertNotIn("@example.test", json.dumps(result))
            fixture["application_commit"] = "a" * 40
            path.write_text(json.dumps(fixture))
            with self.assertRaises(host.GuardError):
                provenance.fixture_identity(path)

    def test_changed_workload_is_rejected_before_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "workload.js"
            path.write_text("changed browser script")
            with self.assertRaises(host.GuardError):
                provenance.workload_identity(path)

    def test_checked_in_contention_script_matches_reviewed_digest(self):
        path = Path(__file__).parent / "workloads" / "contention.cjs"
        self.assertEqual(provenance.workload_identity(path)["sha256"], provenance.CONTENTION_SHA256)

    def test_contention_requires_fixed_parameters_distinct_editors_and_shared_fixture(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.json"
            fixture = {"contention_ticket_id": 99,
                "teacher": {"user_id": 100, "email": "teacher@example.test", "password": "secret"},
                "actors": [{"user_id": n, "ticket_id": n} for n in range(1, 11)]}
            host.write_json(path, fixture)
            args = SimpleNamespace(fixture=path, mode="contention", users=5, warmup=0, seconds=10)
            workload = {"sha256": provenance.CONTENTION_SHA256}
            contract = provenance.campaign_contract(args, workload)
            self.assertEqual(contract["editor_contexts"], 5)
            self.assertNotIn("secret", json.dumps(contract))
            self.assertNotIn("teacher@", json.dumps(contract))
            for key, value in [("users", 3), ("mode", "mixed"), ("warmup", 1), ("seconds", 180)]:
                with self.subTest(key=key), self.assertRaises(host.GuardError):
                    provenance.campaign_contract(SimpleNamespace(**{**vars(args), key: value}), workload)
            for key, value in [("contention_ticket_id", 1), ("teacher", fixture["actors"][0]),
                               ("contention_ticket_id", None)]:
                path.write_text(json.dumps({**fixture, key: value}))
                with self.subTest(key=key), self.assertRaises(host.GuardError):
                    provenance.campaign_contract(args, workload)

    def test_load_workload_cannot_claim_contention_scenarios(self):
        args = SimpleNamespace(mode="contention")
        with self.assertRaises(host.GuardError):
            provenance.campaign_contract(args, {"sha256": provenance.WORKLOAD_SHA256})
