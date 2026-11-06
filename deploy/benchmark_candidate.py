"""Verify candidate provenance; never selects a host or deploys an image."""
import json
import re
import sys
from pathlib import Path


def tag_checks_run_id(ref, revision):
    match = re.fullmatch(r"refs/tags/benchmark-candidate-([0-9a-f]{40})-([1-9][0-9]*)", ref)
    if not match or match[1] != revision:
        raise ValueError("Publication tag must identify this exact commit and successful Checks run")
    return int(match[2])


def verify_publication_run(run, application):
    event = run.get("event")
    if event == "push":
        checks_id = tag_checks_run_id("refs/tags/" + run.get("head_branch", ""), application["application_commit"])
        if checks_id != application["checks_run_id"]:
            raise ValueError("Publication tag identifies a different Checks run")
    elif event != "workflow_dispatch":
        raise ValueError("Publication requires an explicit benchmark tag or manual dispatch")
    if (run.get("id") != application["publication_run_id"]
            or run.get("run_attempt") != application["publication_attempt"]
            or run.get("head_sha") != application["application_commit"]
            or run.get("status") != "completed" or run.get("conclusion") != "success"
            or run.get("path", "").split("@", 1)[0] != ".github/workflows/benchmark-candidate.yml"
            or run.get("repository", {}).get("full_name") != "iagobg/instantflow"
            or run.get("head_repository", {}).get("full_name") != "iagobg/instantflow"):
        raise ValueError("Publication did not succeed for this exact revision and attempt")


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
    if len(sys.argv) == 4 and sys.argv[1] == "tag-checks":
        print(tag_checks_run_id(sys.argv[2], sys.argv[3]))
        raise SystemExit(0)
    action, filename, revision, repository, *extra = sys.argv[1:]
    run = json.loads(Path(filename).read_text())
    if action == "verify" and not extra:
        verify(run, revision, repository)
    elif action == "manifest" and len(extra) == 3:
        print(json.dumps(manifest(run, revision, repository, *extra), indent=2))
    else:
        raise SystemExit("Expected verify RUN_JSON COMMIT REPOSITORY or manifest RUN_JSON COMMIT REPOSITORY DIGEST PUBLICATION_RUN_ID ATTEMPT")
