import copy
import json
from pathlib import Path
import tempfile
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
