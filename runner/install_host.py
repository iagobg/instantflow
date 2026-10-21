"""Opt-in ARM64 Ubuntu installer. Run as root; leaves application execution disabled.
Adds runsc to Docker using a reload, never a restart. Existing daemon options survive.
Run: sudo python3 install_host.py --source /reviewed/runner
"""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = "release-20261012.0"
ARCHIVE = "gvisor-aarch64.tar.bz2"
SHA512 = "2fe7425abd16ad6ca649ab9bc3d7e8e76756834d86ffcc08dbe97c82c3b7262a7d6401f23632f2b296649cc1408b560416b2ab65a4043aa123fc7b90f3a1b2e2"


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def snapshot():
    ids = command("docker", "ps", "-q").split()
    return {row["Id"]: row["State"]["StartedAt"] for row in
            json.loads(command("docker", "inspect", *ids))} if ids else {}


def install(source):
    if os.getuid() != 0 or platform.machine() != "aarch64":
        raise SystemExit("Requires root on the reviewed ARM64 host")
    before = snapshot()
    root = pathlib.Path("/opt/instantflow/gvisor") / VERSION
    if not root.exists():
        with tempfile.TemporaryDirectory() as temporary:
            archive = pathlib.Path(temporary) / ARCHIVE
            url = "https://github.com/google/gvisor/releases/download/" + VERSION + "/" + ARCHIVE
            urllib.request.urlretrieve(url, archive)
            if hashlib.sha512(archive.read_bytes()).hexdigest() != SHA512:
                raise RuntimeError("gVisor checksum mismatch")
            unpacked = pathlib.Path(temporary) / "unpacked"
            unpacked.mkdir()
            with tarfile.open(archive) as bundle:
                # Reject links and special files before any privileged extraction.
                for member in bundle.getmembers():
                    path = pathlib.PurePosixPath(member.name)
                    if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                        raise RuntimeError("Unexpected runtime archive member")
                bundle.extractall(unpacked, filter="data")
            runscs = list(unpacked.rglob("runsc"))
            if len(runscs) != 1 or not (runscs[0].parent / "gvisor-bin").is_dir():
                raise RuntimeError("Expected one runsc with its gvisor-bin sidecars")
            root.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(runscs[0].parent, root)
    runtime = str(root / "runsc")
    version = command(runtime, "--version")
    daemon = pathlib.Path("/etc/docker/daemon.json")
    old = daemon.read_text() if daemon.exists() else None
    config = json.loads(old or "{}")
    runtimes = config.setdefault("runtimes", {})
    wanted = {"path": runtime}
    if "runsc" in runtimes and runtimes["runsc"] != wanted:
        raise RuntimeError("A different runsc registration exists; review it before replacing")
    runtimes["runsc"] = wanted
    candidate = daemon.with_suffix(".instantflow-candidate.json")
    candidate.write_text(json.dumps(config, indent=2) + "\n")
    try:
        command("dockerd", "--validate", "--config-file", str(candidate))
        if old is not None:
            backup = daemon.with_suffix(".before-instantflow.json")
            if not backup.exists():
                backup.write_text(old)
        os.replace(candidate, daemon)
        command("systemctl", "reload", "docker")
    finally:
        candidate.unlink(missing_ok=True)
    # Refuse to proceed if the reload restarted any pre-existing service.
    after = snapshot()
    if any(after.get(key) != value for key, value in before.items()):
        raise RuntimeError("A pre-existing container changed during runtime registration")
    if "runsc" not in json.loads(command("docker", "info", "--format", "{{json .Runtimes}}")):
        raise RuntimeError("Docker did not register runsc")
    try:
        command("id", "instantflow-runner")
    except subprocess.CalledProcessError:
        command("useradd", "--system", "--home-dir", "/var/empty", "--shell", "/usr/sbin/nologin", "instantflow-runner")
    target = pathlib.Path("/opt/instantflow/runner")
    target.mkdir(parents=True, exist_ok=True)
    for name in ("broker.py", "execute.py", "reap.py", "verify.py", "verify_service.py"):
        shutil.copy2(source / name, target / name)
    for name in ("instantflow-python.slice", "instantflow-python-broker.service",
                 "instantflow-python-reaper.service", "instantflow-python-reaper.timer"):
        shutil.copy2(source / name, pathlib.Path("/etc/systemd/system") / name)
    etc = pathlib.Path("/etc/instantflow-python")
    etc.mkdir(mode=0o750, exist_ok=True)
    shutil.chown(etc, user="root", group="instantflow-runner")
    env = etc / "broker.env"
    if not env.exists():
        env.write_text("PYTHON_BROKER_TOKEN=" + secrets.token_hex(32) +
                       "\nPYTHON_BROKER_SOCKET=/run/instantflow-python/broker.sock\n" +
                       "PYTHON_BROKER_SOCKET_GID=65534\n" +
                       "PYTHON_IMAGE=REPLACE_WITH_VERIFIED_IMAGE_DIGEST\n")
        env.chmod(0o640)
        shutil.chown(env, user="root", group="instantflow-runner")
    command("systemctl", "daemon-reload")
    print(json.dumps({"runtime": version, "preserved_containers": len(before),
                      "broker": "installed, not enabled; pin image and run acceptance first"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=pathlib.Path)
    install(parser.parse_args().source.resolve())
