"""Operator watchdog for labelled orphan workloads; never touches unrelated containers."""
import datetime
import json
import subprocess

DOCKER = "/usr/bin/docker"
ids = subprocess.run([DOCKER, "ps", "-aq", "--filter", "label=instantflow.python=true"],
                     check=True, capture_output=True, text=True, timeout=5).stdout.split()
for container in ids:
    data = json.loads(subprocess.run([DOCKER, "inspect", container], check=True,
                                    capture_output=True, text=True, timeout=5).stdout)[0]
    if data["Config"]["Labels"].get("instantflow.python") != "true":
        raise RuntimeError("watchdog label mismatch")
    created = datetime.datetime.fromisoformat(data["Created"].replace("Z", "+00:00"))
    age = (datetime.datetime.now(datetime.timezone.utc) - created).total_seconds()
    if age > 15:
        subprocess.run([DOCKER, "rm", "-f", container], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
