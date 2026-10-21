"""Explicit operator opt-in after fresh target-host acceptance; never run from the web service.
Usage: sudo python3 enable_host.py STACK_ROOT REVIEWED_FRAGMENT EVIDENCE_DIRECTORY
"""
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys


def values(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines()
                if line and not line.startswith("#"))


def main(root, fragment, evidence):
    if os.getuid() != 0:
        raise SystemExit("Requires root")
    image = values(root / "instantflow.image.env")["INSTANTFLOW_IMAGE"]
    if not re.fullmatch(r"ghcr.io/iagobg/instantflow:[a-f0-9]{40}", image):
        raise ValueError("immutable app image required")
    broker = values(pathlib.Path("/etc/instantflow-python/broker.env"))
    reports = {}
    for name, count in (("isolation", 12), ("service", 7), ("application", 7)):
        report = json.loads((evidence / (name + ".json")).read_text())
        tests = report["tests"]
        stamp = datetime.datetime.fromisoformat(report["date"].replace("Z", "+00:00"))
        age = (datetime.datetime.now(datetime.timezone.utc) - stamp).total_seconds()
        if len(tests) < count or not all(test["passed"] is True for test in tests) or not 0 <= age < 86400:
            raise ValueError("fresh complete acceptance required: " + name)
        reports[name] = report
    if reports["application"]["release_image"] != image or reports["isolation"]["image"] != broker["PYTHON_IMAGE"]:
        raise ValueError("acceptance image mismatch")
    if broker["PYTHON_BROKER_SOCKET"] != "/run/instantflow-python/broker.sock" or len(broker["PYTHON_BROKER_TOKEN"]) < 64:
        raise ValueError("reviewed socket and private token required")
    if not pathlib.Path(broker["PYTHON_BROKER_SOCKET"]).is_socket():
        raise ValueError("broker socket absent")
    for unit in ("instantflow-python-broker.service", "instantflow-python-reaper.timer"):
        subprocess.run(["systemctl", "is-active", "--quiet", unit], check=True)
    env = dict(os.environ, INSTANTFLOW_IMAGE=image)
    compose = ["docker", "compose", "-f", "compose.yml", "-f", "projects/instantflow.compose.yml"]

    def run(*args):
        return subprocess.run([*compose, *args], cwd=root, env=env, check=True,
                              capture_output=True, text=True, timeout=180)

    def switch(enabled):
        run("--profile", "tools", "run", "--rm", "--no-deps", "-T", "instantflow-migrate",
            "/app/bin/instantflow", "eval", "Instantflow.Release.python_switch(" + str(enabled).lower() + ")")

    switch(False)
    secret = root / "instantflow.python.env"
    descriptor = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w") as output:
        output.write("PYTHON_BROKER_TOKEN=" + broker["PYTHON_BROKER_TOKEN"] + "\n")
    target = root / "projects/instantflow-python.compose.yml"
    target.write_text(fragment.read_text())
    target.chmod(0o644)
    compose += ["-f", "projects/instantflow-python.compose.yml"]
    try:
        run("config", "--quiet")
        run("up", "-d", "--no-deps", "--wait", "--wait-timeout", "120", "instantflow")
        inspected = subprocess.run(["docker", "inspect", "oracle-caddy-instantflow-1"],
                                   check=True, capture_output=True, text=True, timeout=10)
        container = json.loads(inspected.stdout)[0]
        names = {item.split("=", 1)[0] for item in container["Config"]["Env"]}
        if "OPERATOR_DATABASE_URL" in names or "RUNTIME_DB_PASSWORD" in names:
            raise RuntimeError("operator credentials must not enter serving container")
        if any(mount["Destination"] == "/var/run/docker.sock" for mount in container["Mounts"]):
            raise RuntimeError("serving container must not receive Docker")
        switch(True)
    except Exception:
        switch(False)
        raise
    print(json.dumps({"enabled": True, "release_image": image, "runtime_image": broker["PYTHON_IMAGE"],
                      "serving_user": container["Config"]["User"], "health": container["State"]["Health"]["Status"],
                      "broker_transport": "authenticated Unix socket, read-only directory mount",
                      "operator_credentials_in_web": False, "docker_socket_in_web": False}, indent=2))


if __name__ == "__main__":
    main(*(pathlib.Path(path).resolve() for path in sys.argv[1:]))
