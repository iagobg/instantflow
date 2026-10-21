"""Operator watchdog for labelled orphan workloads; never touches unrelated containers."""
import datetime
import json
import re
import subprocess

DOCKER = "/usr/bin/docker"


def docker(*args):
    return subprocess.run([DOCKER, *args], capture_output=True, text=True, timeout=5)


def missing(result):
    return result.returncode != 0 and "No such" in result.stderr


def reap(now=None):
    listing = docker("ps", "-aq", "--filter", "label=instantflow.python=true")
    listing.check_returncode()
    for container in listing.stdout.split():
        inspected = docker("inspect", container)
        if missing(inspected):
            continue  # The broker can remove a container between list and inspect.
        inspected.check_returncode()
        data = json.loads(inspected.stdout)[0]
        if data["Config"]["Labels"].get("instantflow.python") != "true":
            raise RuntimeError("watchdog label mismatch")
        stamp = re.sub(r"(\.\d{6})\d+(?=Z|[+-])", r"\1", data["Created"])
        created = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        age = ((now or datetime.datetime.now(datetime.timezone.utc)) - created).total_seconds()
        if age > 15:
            removed = docker("rm", "-f", container)
            if not missing(removed):
                removed.check_returncode()


if __name__ == "__main__":
    reap()
