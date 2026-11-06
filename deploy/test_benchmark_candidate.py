import copy
import unittest
from benchmark_candidate import manifest, verify


class CandidateTest(unittest.TestCase):
    def setUp(self):
        self.revision = "a" * 40
        self.repository = "iagobg/instantflow"
        self.run = {
            "id": 123, "head_sha": self.revision, "status": "completed",
            "conclusion": "success", "event": "push",
            "path": ".github/workflows/checks.yml",
            "repository": {"full_name": self.repository},
            "head_repository": {"full_name": self.repository},
        }

    def test_accepts_exact_successful_revision_and_records_immutable_digest(self):
        result = manifest(self.run, self.revision, self.repository, "sha256:" + "b" * 64, 456, 1)
        self.assertEqual(result["application_commit"], self.revision)
        self.assertEqual(result["image"], "ghcr.io/iagobg/instantflow@sha256:" + "b" * 64)
        self.assertEqual(result["checks_run_id"], 123)
        self.assertEqual(result["publication_run_id"], 456)
        self.assertEqual(result["publication_attempt"], 1)
        self.run.update(path=".github/workflows/checks.yml@main", event="workflow_dispatch")
        verify(self.run, self.revision, self.repository)

    def test_rejects_failed_pending_other_revision_workflow_and_fork_runs(self):
        for field, value in [
            ("head_sha", "c" * 40), ("status", "in_progress"),
            ("conclusion", "failure"), ("event", "pull_request"),
            ("path", ".github/workflows/deploy.yml"),
            ("repository", {"full_name": "elsewhere/project"}),
            ("head_repository", {"full_name": "elsewhere/instantflow"}),
            ("id", -1), ("id", True),
        ]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                run = copy.deepcopy(self.run)
                run[field] = value
                verify(run, self.revision, self.repository)

    def test_rejects_tags_partial_commits_and_invalid_repository(self):
        for digest in ["latest", "sha256:abc", "sha256:" + "g" * 64]:
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                manifest(self.run, self.revision, self.repository, digest, 456, 1)
        with self.assertRaises(ValueError):
            verify(self.run, "abc123", self.repository)
        with self.assertRaises(ValueError):
            verify(self.run, self.revision, "owner/repo;cmd")
