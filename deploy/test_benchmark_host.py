"""Exercise target isolation, backup completion and restore failures without Docker."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import benchmark_host as host


def fixture_config():
    logging = {"driver": "json-file", "options": {"max-size": "10m", "max-file": "3"}}
    return {
        "services": {
            "web": {
                "image": host.BASE_IMAGE, "container_name": host.PROJECT + "-web", "env_file": ["web.env"],
                "restart": "unless-stopped", "cpus": 2, "mem_limit": "2g", "init": True,
                "ports": ["127.0.0.1:4400:4000"], "networks": ["database", "web"],
                "environment": {"PHX_SERVER": "true", "PORT": "4000", "PYTHON_EXECUTION": "false"},
                "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"], "logging": logging,
                "healthcheck": {
                    "test": ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://127.0.0.1:4000/entrar"],
                    "interval": "5s", "timeout": "6s", "retries": 20, "start_period": "30s",
                },
            },
            "db": {
                "image": host.POSTGRES_IMAGE, "container_name": host.PROJECT + "-db", "env_file": ["db.env"],
                "restart": "unless-stopped", "cpus": 1, "mem_limit": "1g", "networks": ["database"],
                "volumes": ["data:/var/lib/postgresql/data"], "logging": logging,
                "healthcheck": {
                    "test": ["CMD", "pg_isready", "-U", "postgres", "-d", host.DATABASE],
                    "interval": "5s", "timeout": "5s", "retries": 20,
                },
            },
        },
        "networks": {"database": {"internal": True}, "web": {"external": True, "name": "oracle-caddy-web"}},
        "volumes": {"data": {}},
    }


class FakeHost(host.Host):
    def __init__(self, root):
        self.events = []
        self.fail_at = None
        self.change_source = False
        self.privileges = "t"
        self.rls_count = "0"
        self.databases = {host.DATABASE, "postgres"}
        self.live_counts = {"organizations": 1, "schema_migrations": 2, "tickets": 15}
        self.dump_counts = None
        self.restore_counts = None
        self.containers = []
        for service, image, cpus, memory in [
            ("web", host.BASE_IMAGE, 2_000_000_000, 2_147_483_648),
            ("db", host.POSTGRES_IMAGE, 1_000_000_000, 1_073_741_824),
        ]:
            self.containers.append({
                "Name": "/" + host.PROJECT + "-" + service, "Image": "sha256:application-bytes",
                "Config": {
                    "Image": image, "User": "nobody:nogroup" if service == "web" else "",
                    "Env": [k + "=" + v for k, v in host.read_env(root / (service + ".env")).items()],
                    "Labels": {
                        "com.docker.compose.project": host.PROJECT, "com.docker.compose.service": service,
                        "com.docker.compose.project.working_dir": str(root),
                        "com.docker.compose.project.config_files": str(root / "compose.json"),
                    },
                },
                "State": {"Running": True, "Health": {"Status": "healthy"}},
                "HostConfig": {
                    "NanoCpus": cpus, "Memory": memory, "Privileged": False,
                    "CapDrop": ["ALL"], "SecurityOpt": ["no-new-privileges:true"],
                    "PortBindings": {"4000/tcp": [{"HostIp": "127.0.0.1", "HostPort": "4400"}]} if service == "web" else {},
                },
                "Mounts": [] if service == "web" else [{
                    "Type": "volume", "Name": host.PROJECT + "_data", "Destination": "/var/lib/postgresql/data",
                }],
                "NetworkSettings": {"Networks": dict.fromkeys(
                    [host.PROJECT + "_database", "oracle-caddy-web"] if service == "web" else [host.PROJECT + "_database"]
                )},
            })
        self.image = {"Id": "sha256:application-bytes", "Architecture": "arm64", "Os": "linux",
                      "RepoDigests": [host.BASE_IMAGE], "Config": {"Labels": {
                          "org.opencontainers.image.revision": host.BASE_COMMIT,
                          "org.opencontainers.image.source": "https://github.com/iagobg/instantflow",
                      }}}
        self.network = {"Name": host.PROJECT + "_database", "Internal": True,
                        "Labels": {"com.docker.compose.project": host.PROJECT}}
        self.volume = {"Name": host.PROJECT + "_data", "Labels": {"com.docker.compose.project": host.PROJECT}}

    def docker(self, *args, label, **kwargs):
        self.events.append(("docker", args))
        if "pg_dump" in args:
            if self.fail_at == "dump":
                raise host.GuardError("Injected dump failure")
            self.dump_counts = copy.deepcopy(self.live_counts)
            if self.change_source:
                self.live_counts["tickets"] += 1
            kwargs["stdout"].write(b"PGDMP-synthetic-archive")
            return None
        if "pg_restore" in args:
            if self.fail_at == "restore":
                raise host.GuardError("Injected restore failure")
            assert kwargs["stdin"].read() == b"PGDMP-synthetic-archive"
            assert "--single-transaction" in args and "--exit-on-error" in args
            self.restore_counts = copy.deepcopy(self.dump_counts)
            return b""
        if args[0] == "inspect":
            return json.dumps(self.containers).encode()
        if args[:2] == ("image", "inspect"):
            return json.dumps([self.image]).encode()
        if args[:2] == ("network", "inspect"):
            return json.dumps([self.network]).encode()
        if args[:2] == ("volume", "inspect"):
            return json.dumps([self.volume]).encode()
        raise AssertionError("Unexpected Docker operation")

    def sql(self, database, statement):
        self.events.append(("sql", database, statement))
        if statement.startswith("CREATE DATABASE"):
            name = re.fullmatch(r'CREATE DATABASE "(' + host.VERIFY_PREFIX + r'[0-9a-f]{12})" TEMPLATE template0;', statement)[1]
            if self.fail_at == "create" or name in self.databases:
                raise host.GuardError("Injected create failure")
            self.databases.add(name)
            return ""
        if statement.startswith("DROP DATABASE"):
            name = re.fullmatch(r'DROP DATABASE "(' + host.VERIFY_PREFIX + r'[0-9a-f]{12})";', statement)[1]
            if self.fail_at == "drop":
                raise host.GuardError("Injected cleanup failure")
            self.databases.remove(name)
            return ""
        if "FROM pg_database" in statement:
            return "\n".join(sorted(self.databases))
        if "current_database()" in statement:
            return host.DATABASE
        if "FROM pg_roles" in statement:
            return self.privileges
        if "SET LOCAL ROLE" in statement:
            return self.rls_count
        counts = self.live_counts if database == host.DATABASE else self.restore_counts
        if "FROM pg_tables" in statement:
            return "\n".join(sorted(counts))
        if "SELECT version" in statement:
            return "20261001\n20261002"
        if "count(*)" in statement:
            return "\n".join(k + "|" + str(v) for k, v in sorted(counts.items()))
        raise AssertionError("Unexpected SQL operation")


class BenchmarkHostTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.root.chmod(0o700)
        for name, value in [("ROOT", self.root), ("__file__", str(self.root / "benchmark_host.py")),
                            ("BASE_HASH", hashlib.sha256(b"frozen-baseline").hexdigest())]:
            patcher = patch.object(host, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.config = fixture_config()
        host.write_json(self.root / "compose.json", self.config)
        host.write_json(self.root / "fixture.json", {
            "fixture": "school-v1", "database": host.DATABASE, "application_commit": host.BASE_COMMIT,
            "image": host.BASE_IMAGE, "postgres_image": host.POSTGRES_IMAGE, "baseline_sha256": host.BASE_HASH,
        })
        host.write_json(self.root / "operator-private.json", {"runtime_password": "r" * 48})
        self.write("baseline.dump", b"frozen-baseline")
        self.write("db.env", "POSTGRES_DB=" + host.DATABASE + "\nPOSTGRES_PASSWORD=" + "p" * 48 + "\n")
        self.write("web.env", "DATABASE_URL=ecto://instantflow_runtime:" + "r" * 48
                   + "@db/" + host.DATABASE + "\nSECRET_KEY_BASE=" + "s" * 86
                   + "\nPHX_HOST=" + host.DOMAIN + "\nPOOL_SIZE=10\n")
        self.host = FakeHost(self.root)

    def write(self, name, value):
        path = self.root / name
        path.write_bytes(value if isinstance(value, bytes) else value.encode())
        path.chmod(0o600)

    def manifests(self):
        return list(self.root.glob("snapshots/*/snapshot.json"))

    def mutations(self):
        return [e for e in self.host.events if e[0] == "sql" and e[2].startswith(("CREATE", "DROP"))]

    def test_snapshot_roundtrip_preserves_config_and_uses_archive_inventory(self):
        self.host.change_source = True
        snapshot = self.host.snapshot()
        self.assertEqual(snapshot["inventory"]["table_counts"]["tickets"], 15)
        self.assertEqual(self.host.live_counts["tickets"], 16)
        self.assertEqual(self.host.databases, {host.DATABASE, "postgres"})
        folder = self.manifests()[0].parent
        for name in host.CONFIG_FILES:
            self.assertEqual((folder / name).read_bytes(), (self.root / name).read_bytes())
        for path in folder.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.host.verify_snapshot(snapshot["snapshot_id"])["verified"])
        self.assertFalse(any(e[0] == "docker" and set(e[1]) & {"stop", "up", "compose", "restart"}
                             for e in self.host.events))

    def test_wrong_root_refuses_before_docker(self):
        with patch.object(host, "__file__", "/elsewhere/benchmark_host.py"):
            with self.assertRaisesRegex(host.GuardError, "directory"):
                self.host.snapshot()
        self.assertEqual(self.host.events, [])

    def test_altered_compose_target_and_privileges_refuse_before_docker(self):
        for target, key, value in [
            ("web", "image", "ghcr.io/iagobg/instantflow:latest"),
            ("db", "container_name", "oracle-caddy-instantflow-db-1"),
            ("db", "volumes", ["serving-data:/var/lib/postgresql/data"]),
            ("web", "env_file", ["operator.env"]),
            ("web", "ports", ["4400:4000"]),
            ("web", "privileged", True),
            ("web", "volumes", ["/var/run/docker.sock:/var/run/docker.sock"]),
            ("web", "cpus", 4),
        ]:
            with self.subTest(target=target, key=key):
                changed = copy.deepcopy(self.config)
                changed["services"][target][key] = value
                self.write("compose.json", json.dumps(changed))
                with self.assertRaises(host.GuardError):
                    self.host.snapshot()
                self.assertEqual(self.host.events, [])

    def test_actual_container_mismatch_refuses_before_database_changes(self):
        original = copy.deepcopy(self.host.containers)
        for target, section, key, value in [
            (0, "Config", "Image", "unexpected-image"),
            (0, "Config", "User", "root"),
            (0, "HostConfig", "Privileged", True),
            (0, "HostConfig", "PortBindings", {"4000/tcp": [{"HostIp": "0.0.0.0", "HostPort": "4400"}]}),
            (1, "Config", "Labels", {"com.docker.compose.project": "serving"}),
            (1, "HostConfig", "Memory", 99),
            (1, "State", "Health", {"Status": "unhealthy"}),
        ]:
            with self.subTest(section=section, key=key):
                self.host.containers = copy.deepcopy(original)
                self.host.containers[target][section][key] = value
                with self.assertRaises(host.GuardError):
                    self.host.snapshot()
                self.assertEqual(self.mutations(), [])
        self.assertEqual(self.manifests(), [])

    def test_wrong_image_architecture_revision_or_bytes_refuses(self):
        for field, value in [("Architecture", "amd64"), ("Id", "wrong-bytes"), ("RepoDigests", [])]:
            with self.subTest(field=field):
                original = self.host.image[field]
                self.host.image[field] = value
                with self.assertRaises(host.GuardError):
                    self.host.snapshot()
                self.host.image[field] = original
        self.host.image["Config"]["Labels"]["org.opencontainers.image.revision"] = "f" * 40
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        self.assertEqual(self.mutations(), [])

    def test_shared_database_container_and_privileged_runtime_refuse(self):
        self.host.databases.add("serving_database")
        with self.assertRaisesRegex(host.GuardError, "exclusive"):
            self.host.snapshot()
        self.host.databases.remove("serving_database")
        self.host.privileges = "f"
        with self.assertRaisesRegex(host.GuardError, "privileges"):
            self.host.snapshot()
        self.assertEqual(self.mutations(), [])

    def test_private_permissions_symlinks_and_baseline_tampering_refuse(self):
        env = self.root / "web.env"
        env.chmod(0o644)
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        env.chmod(0o600)
        baseline = self.root / "baseline.dump"
        baseline.rename(self.root / "original.dump")
        baseline.symlink_to(self.root / "original.dump")
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        baseline.unlink()
        self.write("baseline.dump", b"modified")
        with self.assertRaisesRegex(host.GuardError, "checksum"):
            self.host.snapshot()
        self.assertEqual(self.host.events, [])

    def test_runtime_credentials_cannot_point_at_owner_or_another_database(self):
        original = (self.root / "web.env").read_text()
        for changed in [original.replace("instantflow_runtime:", "postgres:"),
                        original.replace("@db/", "@serving-db/"), original + "OPERATOR_DATABASE_URL=secret\n"]:
            self.write("web.env", changed)
            with self.assertRaises(host.GuardError):
                self.host.snapshot()
            self.assertEqual(self.host.events, [])

    def test_backup_failure_has_no_complete_snapshot_or_database_changes(self):
        self.host.fail_at = "dump"
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        self.assertEqual(self.manifests(), [])
        self.assertEqual(self.mutations(), [])

    def test_restore_or_rls_failure_removes_only_the_created_temporary_database(self):
        for failure in ["restore", "rls"]:
            with self.subTest(failure=failure):
                self.host.fail_at = failure
                self.host.rls_count = "15" if failure == "rls" else "0"
                with self.assertRaises(host.GuardError):
                    self.host.snapshot()
                self.assertEqual(self.host.databases, {host.DATABASE, "postgres"})
                self.assertEqual(self.manifests(), [])

    def test_failed_create_never_drops_a_database_it_did_not_create(self):
        self.host.fail_at = "create"
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        self.assertFalse(any(e[2].startswith("DROP") for e in self.mutations()))
        self.assertEqual(self.manifests(), [])

    def test_cleanup_failure_cannot_mark_snapshot_verified(self):
        self.host.fail_at = "drop"
        with self.assertRaises(host.GuardError):
            self.host.snapshot()
        self.assertEqual(self.manifests(), [])

    def test_configuration_drift_cannot_mark_snapshot_verified(self):
        rehearse = self.host.rehearse

        def drift(archive):
            result = rehearse(archive)
            self.write("web.env", (self.root / "web.env").read_text().replace("POOL_SIZE=10", "POOL_SIZE=11"))
            return result

        with patch.object(self.host, "rehearse", side_effect=drift), self.assertRaises(host.GuardError):
            self.host.snapshot()
        self.assertEqual(self.manifests(), [])

    def test_snapshot_tampering_refuses_before_restore(self):
        snapshot = self.host.snapshot()
        folder = self.manifests()[0].parent
        (folder / "database.dump").write_bytes(b"tampered")
        self.host.events = []
        with self.assertRaisesRegex(host.GuardError, "checksum"):
            self.host.verify_snapshot(snapshot["snapshot_id"])
        self.assertEqual(self.mutations(), [])

    def test_snapshot_inventory_mismatch_fails_and_removes_verification_database(self):
        snapshot = self.host.snapshot()
        path = self.manifests()[0]
        snapshot["inventory"]["table_counts"]["tickets"] = 0
        path.write_text(json.dumps(snapshot))
        with self.assertRaisesRegex(host.GuardError, "inventory mismatch"):
            self.host.verify_snapshot(snapshot["snapshot_id"])
        self.assertEqual(self.host.databases, {host.DATABASE, "postgres"})

    def test_snapshot_path_traversal_refuses_without_host_commands(self):
        for identifier in ["../snapshot", "/tmp/snapshot", "snapshot-latest", ""]:
            with self.assertRaises(host.GuardError):
                self.host.verify_snapshot(identifier)
        self.assertEqual(self.host.events, [])

    def test_host_lock_excludes_concurrent_operations_and_releases_after_failure(self):
        with self.assertRaisesRegex(RuntimeError, "injected"):
            with host.host_lock():
                with self.assertRaisesRegex(host.GuardError, "host lock"):
                    with host.host_lock():
                        self.fail("Second operation entered")
                raise RuntimeError("injected")
        with host.host_lock():
            pass

    def test_command_failures_do_not_disclose_stderr_or_inherit_stdin(self):
        result = subprocess.CompletedProcess([], 1, stdout=b"secret", stderr=b"password=secret")
        with patch.object(host.subprocess, "run", return_value=result) as run:
            with self.assertRaises(host.GuardError) as caught:
                host.Host().command(["example"], label="inspection")
            self.assertNotIn("secret", str(caught.exception))
            self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_sql_boundary_refuses_serving_database_before_docker(self):
        with patch.object(host.Host, "docker") as docker:
            for database in ["instantflow", host.VERIFY_PREFIX + "manual", 'postgres;DROP DATABASE x']:
                with self.assertRaises(host.GuardError):
                    host.Host().sql(database, "SELECT 1;")
            docker.assert_not_called()


if __name__ == "__main__":
    unittest.main()
