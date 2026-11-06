"""Verify candidate provenance; never selects a host or deploys an image."""
import json
import re
import sys
from pathlib import Path


def verify(run, revision, repository):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected a full source commit")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository")
    if (run.get("head_sha") != revision
            or run.get("status") != "completed"
            or run.get("conclusion") != "success"
            or run.get("event") not in {"push", "workflow_dispatch"}
            or run.get("path", "").split("@", 1)[0] != ".github/workflows/checks.yml"
            or run.get("repository", {}).get("full_name") != repository
            or run.get("head_repository", {}).get("full_name") != repository
            or type(run.get("id")) is not int or run["id"] <= 0):
        raise ValueError("A successful same-repository Checks run for this exact commit is required")


def manifest(run, revision, repository, digest, publication_run_id, publication_attempt):
    verify(run, revision, repository)
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Expected an immutable SHA-256 image digest")
    if not all(re.fullmatch(r"[1-9][0-9]*", str(value)) for value in [publication_run_id, publication_attempt]):
        raise ValueError("Expected positive publication run and attempt identifiers")
    return {
        "schema": 2,
        "application_commit": revision,
        "image": f"ghcr.io/{repository.lower()}@{digest}",
        "platform": "linux/arm64",
        "checks_run_id": run["id"],
        "checks_url": f"https://github.com/{repository}/actions/runs/{run['id']}",
        "publication_run_id": int(publication_run_id),
        "publication_attempt": int(publication_attempt),
    }


if __name__ == "__main__":
    action, filename, revision, repository, *extra = sys.argv[1:]
    run = json.loads(Path(filename).read_text())
    if action == "verify" and not extra:
        verify(run, revision, repository)
    elif action == "manifest" and len(extra) == 3:
        print(json.dumps(manifest(run, revision, repository, *extra), indent=2))
    else:
        raise SystemExit("Expected verify RUN_JSON COMMIT REPOSITORY or manifest RUN_JSON COMMIT REPOSITORY DIGEST PUBLICATION_RUN_ID ATTEMPT")
