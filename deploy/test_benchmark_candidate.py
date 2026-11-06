import copy
import unittest
from benchmark_candidate import manifest, verify, tag_checks_run_id, verify_publication_run


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

    def test_publication_tag_binds_exact_commit_and_checks_run(self):
        self.assertEqual(tag_checks_run_id("refs/tags/benchmark-candidate-" + self.revision + "-123", self.revision), 123)
        for ref in ["refs/heads/main", "refs/tags/benchmark-candidate-latest-123",
                    "refs/tags/benchmark-candidate-" + "b" * 40 + "-123",
                    "refs/tags/benchmark-candidate-" + self.revision + "-0",
                    "refs/tags/benchmark-candidate-" + self.revision + "-123;command"]:
            with self.assertRaises(ValueError):
                tag_checks_run_id(ref, self.revision)

    def test_publication_accepts_only_matching_successful_manual_or_explicit_tag_run(self):
        application = manifest(self.run, self.revision, self.repository, "sha256:" + "b" * 64, 456, 1)
        run = {**self.run, "id": 456, "run_attempt": 1, "event": "workflow_dispatch",
               "path": ".github/workflows/benchmark-candidate.yml"}
        verify_publication_run(run, application)
        run.update(event="push", head_branch="benchmark-candidate-" + self.revision + "-123")
        verify_publication_run(run, application)
        for field, value in [("head_branch", "main"), ("head_branch", "benchmark-candidate-" + self.revision + "-999"),
                             ("event", "pull_request"), ("conclusion", "failure"), ("run_attempt", 2)]:
            with self.assertRaises(ValueError):
                verify_publication_run({**run, field: value}, application)

    def test_manifest_rejects_invalid_publication_identifiers(self):
        for value in [0, -1, True, "1;command"]:
            with self.assertRaises(ValueError):
                manifest(self.run, self.revision, self.repository, "sha256:" + "b" * 64, value, 1)
