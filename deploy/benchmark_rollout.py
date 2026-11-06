"""Guarded benchmark-only image/schema changes and recoverable snapshot restoration.

All entry points hold the same host lock. A write-ahead journal blocks ordinary
operations until success or recovery. No shared Compose stack is ever invoked.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import urllib.request

import benchmark_host as host
from benchmark_candidate import verify
import benchmark_smoke


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def replace_json(path, value):
    if path.exists():
        host.private_path(path)
    temporary = path.with_name(path.name + "." + secrets.token_hex(6))
    host.write_json(temporary, value)
    os.replace(temporary, path)
    sync_directory(path.parent)


def github_run(run_id, attempt=None):
    url = "https://api.github.com/repos/iagobg/instantflow/actions/runs/" + str(run_id)
    if attempt is not None:
        url += "/attempts/" + str(attempt)
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                                  "User-Agent": "instantflow-benchmark-controller"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def verify_publication(application):
    host.validate_application(application)
    if application == host.baseline_application():
        return
    try:
        checks = github_run(application["checks_run_id"])
        verify(checks, application["application_commit"], "iagobg/instantflow")
        host.require(checks["id"] == application["checks_run_id"], "Checks run identity mismatch")
        run = github_run(application["publication_run_id"], application["publication_attempt"])
        host.require(run["id"] == application["publication_run_id"]
                     and run["run_attempt"] == application["publication_attempt"]
                     and run["head_sha"] == application["application_commit"]
                     and run["status"] == "completed" and run["conclusion"] == "success"
                     and run["event"] == "workflow_dispatch"
                     and run["path"].split("@", 1)[0] == ".github/workflows/benchmark-candidate.yml"
                     and run["repository"]["full_name"] == "iagobg/instantflow"
                     and run["head_repository"]["full_name"] == "iagobg/instantflow",
                     "Candidate publication did not pass for this exact revision/attempt")
    except Exception:
        raise host.GuardError("Candidate Checks/publication provenance could not be verified") from None


class Rollout(host.Host):
    def compose(self, *args):
        return self.docker("compose", "--project-name", host.PROJECT, "--project-directory", str(host.ROOT),
                           "-f", str(host.ROOT / "compose.json"), *args, label="benchmark web lifecycle")

    def smoke(self):
        return benchmark_smoke.smoke()

    def select(self, application, *, online=True):
        host.validate_application(application)
        if online:
            verify_publication(application)
            self.docker("pull", application["image"], label="immutable application pull")
        self.image_identity(application)
        if application != host.baseline_application():
            folder = host.ROOT / "candidates"
            folder.mkdir(mode=0o700, exist_ok=True)
            host.private_path(folder, directory=True)
            path = folder / (application["image"].split(":")[-1] + ".json")
            if path.exists():
                host.require(host.read_json(path) == application, "Conflicting candidate provenance")
            else:
                host.write_json(path, application)
                sync_directory(folder)

    def journal(self, value=None):
        path = host.ROOT / "pending-operation.json"
        if value is not None:
            replace_json(path, value)
        return host.read_json(path)

    def context(self, journal):
        host.require(journal["schema"] == 1 and re.fullmatch(r"operation-[0-9a-f]{12}", journal["id"]),
                     "Invalid operation journal")
        applications = [host.validate_application(journal[k]) for k in ["source", "target"]]
        config = host.read_json(host.ROOT / "compose.json")
        host.require(config["services"]["web"]["image"] in [a["image"] for a in applications],
                     "Unexpected configuration during recovery")
        # Only the image may change; credentials, topology and frozen fixture must stay identical.
        config["services"]["web"]["image"] = journal["source"]["image"]
        host.require(config == journal["config"], "Configuration drift during recovery")
        host.require(all(host.digest(host.private_path(host.ROOT / name)) == value
                         for name, value in journal["fixed_files"].items())
                     and set(journal["fixed_files"]) == set(host.CONFIG_FILES) - {"compose.json"},
                     "Private configuration drift during recovery")
        return {"images": [a["image"] for a in applications], "applications": applications}

    def operation_folder(self, journal):
        return host.private_path(host.private_path(host.ROOT / "operations", directory=True) / journal["id"],
                                 directory=True)

    def cleanup_migrator(self, journal):
        name = host.PROJECT + "-" + journal["id"]
        # A deterministic unique name permits cleanup after a killed Docker client.
        found = self.docker("ps", "-aq", "--filter", "name=^/" + name + "$", label="migration cleanup inspection").decode().splitlines()
        if found:
            host.require(len(found) == 1, "Unexpected migration containers")
            container = json.loads(self.docker("inspect", found[0], label="migration cleanup identity"))[0]
            host.require(container["Name"] == "/" + name
                         and container["Config"]["Labels"].get("instantflow.benchmark.operation") == journal["id"]
                         and container["Config"]["Image"] == journal["target"]["image"]
                         and set(container["NetworkSettings"]["Networks"]) <= {host.PROJECT + "_database"},
                         "Unexpected migration container owner")
            self.docker("rm", "-f", container["Id"], label="migration cleanup")
        env = self.operation_folder(journal) / "migration.env"
        if env.exists():
            host.private_path(env).unlink()
            sync_directory(env.parent)

    def migrate(self, journal):
        db, web = host.validate_credentials(host.ROOT)
        env = self.operation_folder(journal) / "migration.env"
        values = {**web, "PHX_SERVER": "", "PYTHON_EXECUTION": "false",
                  "OPERATOR_DATABASE_URL": "ecto://postgres:" + db["POSTGRES_PASSWORD"] + "@db/" + host.DATABASE,
                  "RUNTIME_DB_PASSWORD": host.read_json(host.ROOT / "operator-private.json")["runtime_password"]}
        with open(env, "x", opener=lambda p, flags: os.open(p, flags, 0o600)) as stream:
            stream.write("".join(k + "=" + v + "\n" for k, v in values.items()))
        try:
            self.docker("create", "--name", host.PROJECT + "-" + journal["id"],
                        "--label", "instantflow.benchmark.operation=" + journal["id"],
                        "--network", host.PROJECT + "_database", "--cpus", "2", "--memory", "2g",
                        "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
                        "--user", "nobody:nogroup", "--env-file", str(env),
                        "--entrypoint", "/app/bin/instantflow", journal["target"]["image"],
                        "eval", "Instantflow.Release.migrate()", label="operator-only migration container")
            self.docker("start", "-a", host.PROJECT + "-" + journal["id"], label="candidate migration")
            state = json.loads(self.docker("inspect", host.PROJECT + "-" + journal["id"],
                                          label="migration exit status"))[0]["State"]
            host.require(not state["Running"] and state["ExitCode"] == 0, "Candidate migration failed")
        finally:
            self.cleanup_migrator(journal)

    def replace_database(self, archive, inventory):
        # Caller holds the host lock, has guarded the exact cluster, stopped web,
        # and durably recorded a freshly verified recovery archive.
        self.sql("postgres", 'DROP DATABASE IF EXISTS "' + host.DATABASE + '" WITH (FORCE);')
        self.sql("postgres", 'CREATE DATABASE "' + host.DATABASE + '" TEMPLATE template0;')
        with archive.open("rb") as stream:
            self.docker("exec", "-i", host.PROJECT + "-db", "pg_restore", "--exit-on-error",
                        "--single-transaction", "--no-owner", "-U", "postgres", "-d", host.DATABASE,
                        stdin=stream, label="benchmark database restoration")
        host.require(self.inventory(host.DATABASE) == inventory, "Restored benchmark inventory mismatch")
        self.runtime_guard()
        host.require(self.sql(host.DATABASE, "BEGIN; SET LOCAL ROLE instantflow_runtime; SELECT count(*) FROM public.tickets; ROLLBACK;") == "0",
                     "Restored runtime RLS does not fail closed")

    def start(self):
        self.compose("up", "-d", "--no-deps", "--pull", "never", "--wait", "--wait-timeout", "90", "web")

    def complete(self, journal, result):
        replace_json(self.operation_folder(journal) / "result.json", result)
        (host.ROOT / "pending-operation.json").unlink()
        sync_directory(host.ROOT)
        return result

    def recover(self):
        journal = self.journal()
        context = self.context(journal)
        self.guard(transition=context)
        self.cleanup_migrator(journal)
        self.compose("stop", "web")
        self.guard(stopped=True, transition=context)
        if journal["recovery_snapshot"]:
            snapshot, folder = self.load_snapshot(journal["recovery_snapshot"])
            host.require(host.digest(folder / "snapshot.json") == journal["recovery_manifest_sha256"],
                         "Recovery manifest changed")
            host.require(snapshot.get("application", host.baseline_application()) == journal["source"],
                         "Recovery snapshot/image mismatch")
            host.require(self.rehearse(folder / "database.dump") == snapshot["inventory"], "Recovery rehearsal mismatch")
            self.replace_database(folder / "database.dump", snapshot["inventory"])
        # With no recovery snapshot, the write-ahead protocol has not authorized a DB change.
        replace_json(host.ROOT / "compose.json", journal["config"])
        self.start()
        identity = self.guard(transition=context, ready=True)
        self.runtime_guard()
        smoke = self.smoke()
        return self.complete(journal, {"operation_id": journal["id"], "status": "recovered",
                                      "identity": identity, "smoke": smoke,
                                      "recovery_snapshot": journal["recovery_snapshot"]})

    def switch(self, application, *, restore_id=None, fixture=False):
        host.require(not (restore_id and fixture), "Select snapshot or frozen fixture, not both")
        self.guard()
        application = host.validate_application(application)
        source = host.application_for(host.read_json(host.ROOT / "compose.json"))
        host.require(source in [host.baseline_application(), application] or restore_id or fixture,
                     "Changing an existing candidate requires a matching snapshot or frozen fixture")
        desired = None
        if restore_id:
            desired, folder = self.load_snapshot(restore_id)
            host.require(desired.get("application", host.baseline_application()) == application,
                         "Snapshot must be paired with its recorded application image")
            host.require(all(host.digest(host.ROOT / name) == desired["files"][name]
                             for name in host.CONFIG_FILES if name != "compose.json"),
                         "Restoration requires the preserved private configuration")
            self.verify_snapshot(restore_id)
        # Published candidates require current successful GitHub checks on first selection.
        # Recovery uses the already guarded locally retained image, even during a GitHub outage.
        self.select(application, online=not restore_id)
        self.smoke()
        archive_inventory = self.rehearse(host.ROOT / "baseline.dump") if fixture else None
        if fixture:
            host.require(all(archive_inventory["table_counts"].get(k) == v for k, v in
                             {"organizations": 1, "workflows": 1, "tickets": 12}.items()), "Wrong frozen fixture counts")
        config = host.read_json(host.ROOT / "compose.json")
        journal = {"schema": 1, "id": "operation-" + secrets.token_hex(6), "started_at": host.utc_now(),
                   "source": host.application_for(config), "target": application, "config": config,
                   "fixed_files": {name: host.digest(host.ROOT / name) for name in host.CONFIG_FILES if name != "compose.json"},
                   "recovery_snapshot": None, "recovery_manifest_sha256": None}
        operations = host.ROOT / "operations"
        operations.mkdir(mode=0o700, exist_ok=True)
        host.private_path(operations, directory=True)
        (operations / journal["id"]).mkdir(mode=0o700)
        self.journal(journal)
        context = self.context(journal)
        try:
            self.compose("stop", "web")
            backup = self.snapshot(stopped=True, transition=context)
            journal["recovery_snapshot"] = backup["snapshot_id"]
            journal["recovery_manifest_sha256"] = host.digest(host.ROOT / "snapshots" / backup["snapshot_id"] / "snapshot.json")
            self.journal(journal)
            if desired:
                self.replace_database(folder / "database.dump", desired["inventory"])
            elif fixture:
                self.replace_database(host.ROOT / "baseline.dump", archive_inventory)
            if application != host.baseline_application() and not desired:
                self.migrate(journal)
            self.runtime_guard()
            host.require(self.sql(host.DATABASE, "BEGIN; SET LOCAL ROLE instantflow_runtime; SELECT count(*) FROM public.tickets; ROLLBACK;") == "0",
                         "Candidate runtime RLS does not fail closed")
            config = host.read_json(host.ROOT / "compose.json")
            config["services"]["web"]["image"] = application["image"]
            replace_json(host.ROOT / "compose.json", config)
            self.start()
            identity = self.guard(transition=context, ready=True)
            smoke = self.smoke()
            return self.complete(journal, {"operation_id": journal["id"], "status": "ready", "identity": identity,
                "application": application, "recovery_snapshot": backup["snapshot_id"], "restored_snapshot": restore_id,
                "frozen_fixture_restored": fixture, "inventory": self.inventory(host.DATABASE), "smoke": smoke})
        except BaseException:
            try:
                self.recover()
            except BaseException:
                raise host.GuardError("Rollout failed; recovery incomplete. Keep journal and run recover before further work") from None
            raise host.GuardError("Rollout failed; previous database and application recovered") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["deploy", "restore", "recover", "smoke"])
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--snapshot")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--fixture", action="store_true")
    args = parser.parse_args()
    host.require((args.action == "deploy") == bool(args.candidate or args.baseline)
                 and not (args.candidate and args.baseline)
                 and (args.action == "restore") == bool(args.snapshot)
                 and (not args.fixture or args.action == "deploy"), "Invalid rollout arguments")
    os.umask(0o077)
    with host.host_lock():
        controller = Rollout()
        if args.action == "recover":
            result = controller.recover()
        elif args.action == "smoke":
            controller.guard()
            result = controller.smoke()
        elif args.action == "restore":
            snapshot, _ = controller.load_snapshot(args.snapshot)
            result = controller.switch(snapshot.get("application", host.baseline_application()), restore_id=args.snapshot)
        else:
            application = host.read_json(args.candidate) if args.candidate else host.baseline_application()
            result = controller.switch(application, fixture=args.fixture)
        print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit("Benchmark operation failed; inspect pending-operation.json and recover if present") from None
