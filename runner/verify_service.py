"""Destructive broker recovery rehearsal, with synthetic work only and the app gate off.
Run as operator with broker.env exported; requires no legitimate calculations in flight.
"""
import concurrent.futures
import datetime
import http.client
import json
import os
import pathlib
import socket
import subprocess
import threading
import time
import uuid

DOCKER = "/usr/bin/docker"
SERVICE = "instantflow-python-broker.service"


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=10).stdout.strip()


def workloads():
    return command(DOCKER, "ps", "-aq", "--filter", "label=instantflow.python=true").split()


def wait_for(predicate, seconds):
    deadline = time.monotonic() + seconds
    while not predicate():
        if time.monotonic() >= deadline:
            raise RuntimeError("Acceptance deadline exceeded")
        threading.Event().wait(.1)


class Connection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(os.environ["PYTHON_BROKER_SOCKET"])


def call(org, source="def calculate(x): return {'total': 1}", token=True):
    payload = {"organization_id": org, "run_id": "fixture:" + str(uuid.uuid4()),
               "fence": str(uuid.uuid4()), "runtime": os.environ["PYTHON_IMAGE"].split(":")[-1],
               "source": source, "input": {"synthetic": 1}}
    connection = Connection("localhost", timeout=12)
    try:
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + os.environ["PYTHON_BROKER_TOKEN"]
        connection.request("POST", "/run", json.dumps(payload), headers)
        response = connection.getresponse()
        body = json.loads(response.read(32769))
        if response.status == 200:
            assert all(body[key] == payload[key] for key in ("organization_id", "run_id", "fence"))
        return response.status, body
    except http.client.RemoteDisconnected:
        return None, {}
    finally:
        connection.close()


def main():
    marker = pathlib.Path("/etc/instantflow-python/ENABLED")
    sockdir = pathlib.Path(os.environ["PYTHON_BROKER_SOCKET"]).parent
    assert marker.is_file() and not workloads()
    def ready():
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
                probe.settimeout(.2)
                probe.connect(os.environ["PYTHON_BROKER_SOCKET"])
            return True
        except OSError:
            return False
    wait_for(ready, 10)
    before = sockdir.stat().st_ino
    report = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(), "tests": []}

    def passed(name, **metrics):
        report["tests"].append({"name": name, "passed": True, **metrics})

    assert call(9001, token=False)[0] == 403
    passed("unix_socket_authentication_required")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        try:
            first = executor.submit(call, 9001, "def calculate(x):\n while True: pass")
            wait_for(lambda: len(workloads()) == 1, 3)
            assert call(9001)[0] == 429
            passed("one_slot_per_tenant")
            started = time.monotonic()
            status, body = call(9002)
            assert status == 200 and body["output"] == {"total": 1}
            passed("other_tenant_progress_during_cpu_loop", seconds=round(time.monotonic() - started, 3))
            second = executor.submit(call, 9002, "def calculate(x):\n while True: pass")
            wait_for(lambda: len(workloads()) == 2, 3)
            assert call(9003)[0] == 429
            data = json.loads(command(DOCKER, "inspect", *workloads()))
            for container in data:
                limits = container["HostConfig"]
                assert limits["Runtime"] == "runsc" and limits["NetworkMode"] == "none"
                assert limits["Memory"] == limits["MemorySwap"] == 128 * 1024 * 1024
                assert limits["PidsLimit"] == 64 and limits["NanoCpus"] == 1000000000
                assert limits["CgroupParent"] == "instantflow-python.slice"
                assert not container["Mounts"] or all(mount["Type"] == "tmpfs" for mount in container["Mounts"])
            assert command("systemctl", "show", "instantflow-python.slice", "-p", "TasksMax", "--value") == "128"
            assert command("systemctl", "show", "instantflow-python.slice", "-p", "MemoryMax", "--value") == "536870912"
            passed("two_global_slots_and_measured_docker_limits")
            started = time.monotonic()
            marker.unlink()
            for future in (first, second):
                status, body = future.result(timeout=4)
                assert status == 200 and body["status"] == "failed"
            assert not workloads()
            passed("emergency_disable_removes_both_workloads", seconds=round(time.monotonic() - started, 3))
        finally:
            marker.touch(mode=0o644, exist_ok=True)

        orphan = executor.submit(call, 9001, "def calculate(x):\n while True: pass")
        wait_for(lambda: len(workloads()) == 1, 3)
        started = time.monotonic()
        command("systemctl", "kill", "--kill-who=main", "--signal=SIGKILL", SERVICE)
        orphan.result(timeout=12)
        # Hold the broker stopped to measure the independent watchdog, not startup cleanup.
        command("systemctl", "stop", SERVICE)
        wait_for(lambda: not workloads(), 30)
        command("systemctl", "start", SERVICE)
        wait_for(ready, 10)
        assert sockdir.stat().st_ino == before
        assert call(9002)[1].get("output") == {"total": 1}
        passed("broker_death_watchdog_reaps_orphan_and_recovers",
               seconds=round(time.monotonic() - started, 3), socket_directory_preserved=True)
        restarting = executor.submit(call, 9001, "def calculate(x):\n while True: pass")
        wait_for(lambda: len(workloads()) == 1, 3)
        started = time.monotonic()
        command("systemctl", "kill", "--kill-who=main", "--signal=SIGKILL", SERVICE)
        restarting.result(timeout=12)
        wait_for(ready, 12)
        assert not workloads()
        assert call(9002)[1].get("output") == {"total": 1}
        passed("restart_reconciles_orphans_before_admission", seconds=round(time.monotonic() - started, 3))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
