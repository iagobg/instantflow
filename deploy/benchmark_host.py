"""Guard and preserve the dedicated benchmark; never reset or deploy an app.

Install this file in ROOT and run it as the directory owner. Only a randomly
named verification database is created/dropped. Restoring the benchmark itself
and selecting a candidate image are deliberately separate future commands.
"""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess

ROOT = Path("/home/ubuntu/apps/instantflow-benchmark")
PROJECT = "instantflow-benchmark"
DATABASE = "instantflow_benchmark"
DOMAIN = "instantflow-benchmark.iagobussoletti.com.br"
REPOSITORY = "ghcr.io/iagobg/instantflow"
BASE_COMMIT = "10cb39783293765a858b6f342cf4803773048423"
BASE_IMAGE = REPOSITORY + "@sha256:5acd3a923620cba8756cc37a4ff0db45a909adf3225c3a346083bf623d7f4628"
POSTGRES_IMAGE = "postgres@sha256:d81f7b51697014367236d07ec58b54153fc28f828b72bf247fe5c7487520bcb0"
BASE_HASH = "ca9165d79ef6dffa5dec258b9d2010156110027bdd2f8c2173dcfde2f09b442c"
CONFIG_FILES = ("compose.json", "fixture.json", "db.env", "web.env", "operator-private.json")
SNAPSHOT_PATTERN = r"snapshot-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}"
VERIFY_PREFIX = "instantflow_benchmark_verify_"


class GuardError(RuntimeError):
    """A safe, fixed diagnostic that never contains a credential or SQL value."""


def require(condition, message):
    if not condition:
        raise GuardError(message)


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def private_path(path, directory=False):
    info = path.lstat()
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    require(expected(info.st_mode) and not path.is_symlink(), "Unsafe private file type")
    require(info.st_uid == os.getuid() and info.st_mode & 0o077 == 0,
            "Private files must belong to the operator and deny group/other access")
    return path


def read_json(path):
    private_path(path)
    return json.loads(path.read_text())


def write_json(path, data):
    # Exclusive creation also refuses symlinks and accidental snapshot replacement.
    with open(path, "x", opener=lambda p, flags: os.open(p, flags, 0o600)) as stream:
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def read_env(path):
    result = {}
    for line in private_path(path).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        require(sep and re.fullmatch(r"[A-Z_]+", key) and key not in result,
                "Unsupported private environment format")
        result[key] = value
    return result


def validate_config(config, marker):
    require(marker == {
        "fixture": "school-v1", "database": DATABASE, "application_commit": BASE_COMMIT,
        "image": BASE_IMAGE, "postgres_image": POSTGRES_IMAGE, "baseline_sha256": BASE_HASH,
    }, "Unexpected frozen fixture identity")
    require(set(config) == {"services", "networks", "volumes"}, "Unexpected Compose root fields")
    require(config["networks"] == {
        "database": {"internal": True}, "web": {"external": True, "name": "oracle-caddy-web"},
    } and config["volumes"] == {"data": {}}, "Unexpected benchmark network or volume")
    require(set(config["services"]) == {"web", "db"}, "Unexpected Compose services")
    web, db = config["services"]["web"], config["services"]["db"]
    common = {"image", "container_name", "env_file", "restart", "cpus", "mem_limit",
              "networks", "healthcheck", "logging"}
    require(set(web) == common | {"init", "environment", "ports", "cap_drop", "security_opt"}
            and set(db) == common | {"volumes"}, "Unexpected service options")
    require(web["image"] == BASE_IMAGE and db["image"] == POSTGRES_IMAGE,
            "Only the recorded historical image is supported by this preservation version")
    require(web["container_name"] == PROJECT + "-web" and db["container_name"] == PROJECT + "-db",
            "Unexpected benchmark container names")
    require(web["env_file"] == ["web.env"] and db["env_file"] == ["db.env"],
            "Unexpected private environment paths")
    require(web["ports"] == ["127.0.0.1:4400:4000"]
            and web["networks"] == ["database", "web"] and db["networks"] == ["database"]
            and db["volumes"] == ["data:/var/lib/postgresql/data"], "Unexpected service topology")
    require(web["environment"] == {"PHX_SERVER": "true", "PORT": "4000", "PYTHON_EXECUTION": "false"}
            and web["cap_drop"] == ["ALL"] and web["security_opt"] == ["no-new-privileges:true"]
            and web["init"] is True, "Unexpected runtime restrictions")
    for service, cpus, memory in [(web, 2, "2g"), (db, 1, "1g")]:
        require(service["cpus"] == cpus and service["mem_limit"] == memory
                and service["restart"] == "unless-stopped", "Unexpected resource limits")
        require(service["logging"] == {
            "driver": "json-file", "options": {"max-size": "10m", "max-file": "3"},
        }, "Unexpected logging configuration")
    require(web["healthcheck"] == {
        "test": ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://127.0.0.1:4000/entrar"],
        "interval": "5s", "timeout": "6s", "retries": 20, "start_period": "30s",
    } and db["healthcheck"] == {
        "test": ["CMD", "pg_isready", "-U", "postgres", "-d", DATABASE],
        "interval": "5s", "timeout": "5s", "retries": 20,
    }, "Unexpected health checks")


def validate_credentials(root):
    from urllib.parse import urlsplit

    db, web = read_env(root / "db.env"), read_env(root / "web.env")
    operator = read_json(root / "operator-private.json")
    require(set(db) == {"POSTGRES_DB", "POSTGRES_PASSWORD"} and db["POSTGRES_DB"] == DATABASE,
            "Unexpected database environment")
    require(set(web) == {"DATABASE_URL", "SECRET_KEY_BASE", "PHX_HOST", "POOL_SIZE"}
            and web["POOL_SIZE"] == "10" and web["PHX_HOST"] in {DOMAIN, "localhost"}
            and len(web["SECRET_KEY_BASE"]) >= 64, "Unexpected web environment")
    url = urlsplit(web["DATABASE_URL"])
    require(set(operator) == {"runtime_password"}
            and re.fullmatch(r"[a-zA-Z0-9]{32,128}", operator["runtime_password"])
            and re.fullmatch(r"[a-zA-Z0-9]{32,128}", db["POSTGRES_PASSWORD"]),
            "Unsupported generated credential format")
    require(url.scheme == "ecto" and url.hostname == "db" and url.port is None
            and url.path == "/" + DATABASE and not url.query and not url.fragment
            and url.username == "instantflow_runtime" and url.password == operator["runtime_password"]
            and url.password != db["POSTGRES_PASSWORD"], "Runtime database identity mismatch")
    return db, web


class Host:
    def command(self, args, *, label, input=None, stdin=None, stdout=None):
        options = {"stderr": subprocess.PIPE, "timeout": 180, "check": False}
        options["stdout"] = stdout if stdout is not None else subprocess.PIPE
        if input is not None:
            options["input"] = input
        else:
            options["stdin"] = stdin if stdin is not None else subprocess.DEVNULL
        try:
            result = subprocess.run(args, **options)
        except (OSError, subprocess.TimeoutExpired):
            raise GuardError("Command could not complete: " + label) from None
        require(result.returncode == 0, "Command failed: " + label)
        return result.stdout

    def docker(self, *args, label, **kwargs):
        return self.command(["sudo", "-n", "docker", "--host", "unix:///var/run/docker.sock", *args],
                            label=label, **kwargs)

    def sql(self, database, statement):
        require(database in {DATABASE, "postgres"} or re.fullmatch(VERIFY_PREFIX + r"[0-9a-f]{12}", database),
                "SQL database outside benchmark boundary")
        return self.docker("exec", "-i", PROJECT + "-db", "psql", "-X", "-qAt",
                           "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database,
                           input=statement.encode(), label="database inspection").decode().strip()

    def guard(self):
        require(ROOT.resolve() == ROOT and Path(__file__).resolve().parent == ROOT,
                "Wrong benchmark management directory")
        private_path(ROOT, directory=True)
        marker = read_json(ROOT / "fixture.json")
        config = read_json(ROOT / "compose.json")
        validate_config(config, marker)
        db_env, web_env = validate_credentials(ROOT)
        require(digest(private_path(ROOT / "baseline.dump")) == BASE_HASH, "Frozen baseline checksum mismatch")

        containers = json.loads(self.docker("inspect", PROJECT + "-web", PROJECT + "-db",
                                           label="container identity"))
        require(len(containers) == 2, "Unexpected container inspection")
        for container, service, image, cpus, memory, env in [
            (containers[0], "web", BASE_IMAGE, 2_000_000_000, 2_147_483_648, web_env),
            (containers[1], "db", POSTGRES_IMAGE, 1_000_000_000, 1_073_741_824, db_env),
        ]:
            labels = container["Config"]["Labels"]
            require(container["Name"] == "/" + PROJECT + "-" + service
                    and container["Config"]["Image"] == image
                    and labels.get("com.docker.compose.project") == PROJECT
                    and labels.get("com.docker.compose.service") == service
                    and labels.get("com.docker.compose.project.working_dir") == str(ROOT)
                    and labels.get("com.docker.compose.project.config_files") == str(ROOT / "compose.json"),
                    "Running container identity differs from benchmark configuration")
            require(container["State"]["Running"] and container["State"]["Health"]["Status"] == "healthy",
                    "Benchmark containers must be running and healthy")
            require(container["HostConfig"]["NanoCpus"] == cpus
                    and container["HostConfig"]["Memory"] == memory
                    and not container["HostConfig"]["Privileged"], "Running container limits differ")
            actual_env = dict(item.split("=", 1) for item in container["Config"]["Env"])
            require(all(actual_env.get(k) == v for k, v in env.items()), "Running credentials/configuration differ")
            if service == "web":
                require(not container["Mounts"]
                        and container["Config"]["User"] == "nobody:nogroup"
                        and not ({"OPERATOR_DATABASE_URL", "RUNTIME_DB_PASSWORD", "MIGRATION_PGPASSWORD"} & actual_env.keys())
                        and container["HostConfig"]["CapDrop"] == ["ALL"]
                        and "no-new-privileges:true" in container["HostConfig"]["SecurityOpt"],
                        "Unsafe running web container")
                require(container["HostConfig"]["PortBindings"] == {
                    "4000/tcp": [{"HostIp": "127.0.0.1", "HostPort": "4400"}],
                } and set(container["NetworkSettings"]["Networks"]) == {
                    PROJECT + "_database", "oracle-caddy-web",
                }, "Unexpected running web topology")
            else:
                mounts = container["Mounts"]
                require(len(mounts) == 1 and mounts[0]["Type"] == "volume"
                        and mounts[0]["Name"] == PROJECT + "_data"
                        and mounts[0]["Destination"] == "/var/lib/postgresql/data"
                        and not container["HostConfig"]["PortBindings"]
                        and set(container["NetworkSettings"]["Networks"]) == {PROJECT + "_database"},
                        "Unexpected running database topology")

        image = json.loads(self.docker("image", "inspect", BASE_IMAGE, label="image identity"))[0]
        require(image["Architecture"] == "arm64" and image["Os"] == "linux"
                and containers[0]["Image"] == image["Id"]
                and BASE_IMAGE in image["RepoDigests"]
                and image["Config"]["Labels"].get("org.opencontainers.image.revision") == BASE_COMMIT
                and image["Config"]["Labels"].get("org.opencontainers.image.source") == "https://github.com/iagobg/instantflow",
                "Unexpected application image provenance")
        network = json.loads(self.docker("network", "inspect", PROJECT + "_database",
                                        label="database network identity"))[0]
        volume = json.loads(self.docker("volume", "inspect", PROJECT + "_data",
                                       label="database volume identity"))[0]
        require(network["Internal"] is True and network["Name"] == PROJECT + "_database"
                and network["Labels"].get("com.docker.compose.project") == PROJECT
                and volume["Name"] == PROJECT + "_data"
                and volume["Labels"].get("com.docker.compose.project") == PROJECT,
                "Database network or volume belongs to another stack")
        require(self.sql("postgres", "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY datname;").splitlines()
                == [DATABASE, "postgres"], "Database container is not exclusive to the benchmark")
        require(self.sql(DATABASE, "SELECT current_database();") == DATABASE, "Wrong connected database")
        require(self.sql(DATABASE, """
            SELECT rolcanlogin AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls)
            AND NOT pg_has_role('instantflow_runtime', 'postgres', 'MEMBER')
            AND NOT EXISTS (SELECT FROM pg_class c WHERE c.relnamespace='public'::regnamespace
                            AND c.relowner=pg_roles.oid)
            FROM pg_roles WHERE rolname='instantflow_runtime';
        """) == "t", "Unexpected runtime database privileges")
        return {"root": str(ROOT), "project": PROJECT, "database": DATABASE,
                "application_commit": BASE_COMMIT, "image": BASE_IMAGE, "postgres_image": POSTGRES_IMAGE,
                "fixture_sha256": BASE_HASH, "endpoint_host": web_env["PHX_HOST"], "pool_size": 10}

    def inventory(self, database):
        # Only identifiers/counts leave PostgreSQL; no rows, identities or field values.
        tables = self.sql(database, """
            SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;
        """).splitlines()
        require(tables and all(re.fullmatch(r"[a-z][a-z0-9_]*", name) for name in tables),
                "Unexpected table identifiers")
        statements = [f"SELECT '{name}', count(*) FROM public.\"{name}\";" for name in tables]
        counts = {}
        for line in self.sql(database, "\n".join(statements)).splitlines():
            name, count = line.split("|")
            counts[name] = int(count)
        require(set(counts) == set(tables), "Incomplete restored table inventory")
        versions = self.sql(database, "SELECT version FROM public.schema_migrations ORDER BY version;").splitlines()
        require(versions and all(v.isdigit() for v in versions), "Missing migration inventory")
        return {"table_counts": counts, "schema_versions": versions}

    def rehearse(self, archive):
        temporary = VERIFY_PREFIX + secrets.token_hex(6)
        created = False
        try:
            # No IF NOT EXISTS: never take ownership of a pre-existing database.
            self.sql("postgres", f'CREATE DATABASE "{temporary}" TEMPLATE template0;')
            created = True
            with archive.open("rb") as stream:
                self.docker("exec", "-i", PROJECT + "-db", "pg_restore", "--exit-on-error",
                            "--single-transaction", "--no-owner", "-U", "postgres", "-d", temporary,
                            stdin=stream, label="snapshot restore rehearsal")
            inventory = self.inventory(temporary)
            require(self.sql(temporary, """
                BEGIN; SET LOCAL ROLE instantflow_runtime;
                SELECT count(*) FROM public.tickets;
                ROLLBACK;
            """) == "0", "Restored runtime RLS does not fail closed without tenant context")
            return inventory
        finally:
            if created:
                self.sql("postgres", f'DROP DATABASE "{temporary}";')

    def snapshot(self):
        identity = self.guard()
        base = ROOT / "snapshots"
        base.mkdir(mode=0o700, exist_ok=True)
        private_path(base, directory=True)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        snapshot_id = "snapshot-" + stamp + "-" + secrets.token_hex(6)
        folder = base / snapshot_id
        folder.mkdir(mode=0o700)
        before = {name: digest(ROOT / name) for name in CONFIG_FILES}
        for name in CONFIG_FILES:
            with open(folder / name, "xb", opener=lambda p, flags: os.open(p, flags, 0o600)) as stream:
                stream.write(private_path(ROOT / name).read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
        archive = folder / "database.dump"
        started = utc_now()
        with open(archive, "xb", opener=lambda p, flags: os.open(p, flags, 0o600)) as stream:
            self.docker("exec", PROJECT + "-db", "pg_dump", "-U", "postgres", "-d", DATABASE,
                        "-Fc", "--no-owner", stdout=stream, label="consistent database backup")
            stream.flush()
            os.fsync(stream.fileno())
        require(archive.stat().st_size > 0, "Empty snapshot archive")
        inventory = self.rehearse(archive)
        require(identity == self.guard(), "Benchmark identity changed during preservation")
        require(before == {name: digest(ROOT / name) for name in CONFIG_FILES}
                == {name: digest(folder / name) for name in CONFIG_FILES},
                "Benchmark configuration changed during preservation")
        snapshot = {
            "schema": 1, "snapshot_id": snapshot_id, "identity": identity,
            "started_at": started, "verified_at": utc_now(), "inventory": inventory,
            "files": {name: digest(folder / name) for name in (*CONFIG_FILES, "database.dump")},
            "verification_database_removed": True,
            "consistency": "pg_dump transaction snapshot; inventory read from its restored archive, not a later live query",
        }
        # A partial directory never has a completion manifest and cannot verify.
        write_json(folder / "snapshot.json", snapshot)
        for directory in [folder, base]:
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        return snapshot

    def verify_snapshot(self, snapshot_id):
        require(re.fullmatch(SNAPSHOT_PATTERN, snapshot_id), "Invalid snapshot identifier")
        identity = self.guard()
        folder = private_path(private_path(ROOT / "snapshots", directory=True) / snapshot_id, directory=True)
        snapshot = read_json(folder / "snapshot.json")
        require(snapshot["schema"] == 1 and snapshot["snapshot_id"] == snapshot_id
                and snapshot["identity"] == identity and snapshot["verification_database_removed"] is True,
                "Snapshot belongs to a different benchmark identity")
        require(set(snapshot["files"]) == {*CONFIG_FILES, "database.dump"}, "Incomplete snapshot manifest")
        for name, expected in snapshot["files"].items():
            require(digest(private_path(folder / name)) == expected, "Snapshot checksum mismatch")
        validate_config(read_json(folder / "compose.json"), read_json(folder / "fixture.json"))
        validate_credentials(folder)
        require(self.rehearse(folder / "database.dump") == snapshot["inventory"],
                "Restored snapshot inventory mismatch")
        require(all(digest(folder / name) == expected for name, expected in snapshot["files"].items()),
                "Snapshot changed during verification")
        require(identity == self.guard(), "Benchmark identity changed during verification")
        return {"snapshot_id": snapshot_id, "verified": True, "verification_database_removed": True,
                "inventory": snapshot["inventory"]}


@contextlib.contextmanager
def host_lock():
    require(ROOT.resolve() == ROOT and Path(__file__).resolve().parent == ROOT,
            "Wrong benchmark management directory")
    private_path(ROOT, directory=True)
    fd = os.open(ROOT / ".benchmark-control.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+") as stream:
        private_path(ROOT / ".benchmark-control.lock")
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise GuardError("Another benchmark control operation holds the host lock") from None
        yield


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["inspect", "snapshot", "verify-snapshot"])
    parser.add_argument("--snapshot")
    args = parser.parse_args()
    require((args.action == "verify-snapshot") == (args.snapshot is not None),
            "Supply --snapshot only for verify-snapshot")
    os.umask(0o077)
    with host_lock():
        host = Host()
        if args.action == "inspect":
            result = {"identity": host.guard(), "live_inventory": host.inventory(DATABASE)}
        elif args.action == "snapshot":
            result = host.snapshot()
        else:
            result = host.verify_snapshot(args.snapshot)
        print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except GuardError as error:
        import sys
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from None
    except Exception:
        # Input/command exceptions can embed private values; never print their repr.
        import sys
        print("Benchmark operation refused or failed; no deployment/reset was performed.", file=sys.stderr)
        raise SystemExit(1) from None
