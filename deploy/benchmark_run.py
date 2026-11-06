"""Run the reviewed school workload against an explicit immutable campaign arm.

The workload and private fixture are external inputs verified by hash/identity;
the historical untracked runner is not imported or modified.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import queue
import re
import secrets
import shlex
import subprocess
import threading
import time

import benchmark_host as host
import benchmark_provenance as provenance
from benchmark_rollout import replace_json


def direct_preflight(output):
    headers = output / "origin-headers.txt"
    command = ["curl", "--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "15",
               "--resolve", host.DOMAIN + ":443:" + provenance.ORIGIN_IP,
               "--dump-header", str(headers), "--output", "/dev/null", "--write-out", "%{json}",
               "https://" + host.DOMAIN + "/entrar"]
    result = subprocess.run(command, capture_output=True, timeout=20)
    host.require(result.returncode == 0, "Direct-origin HTTPS preflight failed")
    data = json.loads(result.stdout)
    host.require(data["http_code"] == 200 and data["remote_ip"] == provenance.ORIGIN_IP
                 and data["ssl_verify_result"] == 0
                 and not any(line.lower().startswith("cf-ray:") for line in headers.read_text().splitlines()),
                 "Direct-origin route or TLS mismatch")
    return {"remote_ip": data["remote_ip"], "status": data["http_code"], "tls_verified": True}


def k6_command(args, output, container):
    return ["docker", "run", "--rm", "--name", container, "--cidfile", str(output / "container.id"),
            "--label", "instantflow.benchmark.run=" + output.name, "--shm-size=1g",
            "--user", str(os.getuid()) + ":" + str(os.getgid()), "-e", "HOME=/tmp",
            "--mount", "type=bind,src=" + str(args.workload) + ",dst=/scripts/workload.js,readonly",
            "--mount", "type=bind,src=" + str(args.fixture) + ",dst=/fixture/manifest.json,readonly",
            "--mount", "type=bind,src=" + str(output) + ",dst=/results",
            "-e", "BASE_URL=https://" + host.DOMAIN, "-e", "MODE=" + args.mode,
            "-e", "USERS=" + str(args.users), "-e", "WARMUP_SECONDS=" + str(args.warmup),
            "-e", "MEASURE_SECONDS=" + str(args.seconds), "-e", "K6_WEB_DASHBOARD=true",
            "-e", "K6_WEB_DASHBOARD_PORT=-1", "-e", "K6_WEB_DASHBOARD_PERIOD=1s",
            "-e", "K6_WEB_DASHBOARD_EXPORT=/results/report.html", provenance.K6,
            "run", "--out", "json=/results/samples.json.gz", "/scripts/workload.js"]


class Remote:
    def __init__(self, output):
        self.output = output
        self.events = queue.Queue()
        self.stderr = (output / "host-control.log").open("wb")
        self.process = subprocess.Popen(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            provenance.SSH_HOST, shlex.join(["python3", str(host.ROOT / "benchmark_session.py")])],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr)
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        try:
            with (self.output / "host-events.jsonl").open("wb") as stream:
                for line in iter(lambda: self.process.stdout.readline(1_000_001), b""):
                    host.require(len(line) < 1_000_000, "Oversized host event")
                    event = json.loads(line)
                    stream.write(line)
                    stream.flush()
                    self.events.put(event)
        except Exception:
            pass  # The fixed closed event reports failure without exposing response text.
        finally:
            self.events.put({"event": "closed"})

    def send(self, data):
        self.process.stdin.write((json.dumps(data) + "\n").encode())
        self.process.stdin.flush()

    def wait(self, event_name, timeout):
        deadline = time.monotonic() + timeout
        while True:
            try:
                event = self.events.get(timeout=max(0, deadline - time.monotonic()))
            except queue.Empty:
                raise host.GuardError("Timed out waiting for host " + event_name) from None
            if event["event"] == event_name:
                return event
            if event_name == "restored" and event["event"] == "ready":
                continue  # Preparation completed after the caller had already disconnected.
            host.require(event["event"] == "sample", "Host campaign closed before " + event_name)

    def close(self):
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self.process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            # Host has its own bounded deadline and durable recovery journal.
            # Do not send a remote kill while it may be restoring PostgreSQL.
            self.process.terminate()
            self.process.wait(timeout=10)
        self.reader.join(timeout=2)
        self.stderr.close()


def cleanup_container(output):
    path = output / "container.id"
    if path.exists():
        identifier = path.read_text().strip()
        host.require(re.fullmatch(r"[0-9a-f]{64}", identifier), "Invalid task-owned container ID")
        subprocess.run(["docker", "rm", "-f", identifier], capture_output=True, timeout=20)


def runner_samples(container, output, stop):
    with (output / "runner-resources.jsonl").open("w") as stream:
        while not stop.is_set():
            try:
                result = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{json .}}", container],
                                        capture_output=True, timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                stream.write(json.dumps({"unix_time": time.time(), "sample_failed": True}) + "\n")
                stream.flush()
                stop.wait(3)
                continue
            if result.returncode == 0 and result.stdout.strip():
                stream.write(json.dumps({"unix_time": time.time(), "load_average": os.getloadavg(),
                                         "container": json.loads(result.stdout)}) + "\n")
                stream.flush()
            stop.wait(3)


def run(args):
    os.umask(0o077)
    application = host.validate_application(host.read_json(args.candidate) if args.candidate else host.baseline_application())
    fixture, workload = provenance.fixture_identity(args.fixture), provenance.workload_identity(args.workload)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
    host.private_path(args.output, directory=True)
    output = args.output / ("campaign-" + secrets.token_hex(6))
    output.mkdir(mode=0o700)
    metadata = {"status": "preparing", "started_at": host.utc_now(), "application": application,
                "fixture": fixture, "workload": workload, "users": args.users, "mode": args.mode,
                "warmup_seconds": args.warmup, "measurement_seconds": args.seconds,
                "runner": {"platform": platform.platform(), "cpus": os.cpu_count(),
                           "source_sha256": host.digest(Path(__file__))},
                "interpretation": "Closed browser workload; pilots do not establish capacity"}
    replace_json(output / "metadata.json", metadata)
    remote, ready, exit_code = None, None, None
    workload_passed = False
    stop = threading.Event()
    observer = None
    try:
        metadata["route_verification"] = direct_preflight(output)
        remote = Remote(output)
        remote.send({"action": "start", "application": application,
                     "hold_seconds": args.seconds + args.warmup + 240})
        ready = remote.wait("ready", 600)["ready"]
        metadata["provenance"] = provenance.manifest(application, ready, fixture, workload)
        metadata["status"] = "running"
        replace_json(output / "metadata.json", metadata)
        container = "instantflow-k6-" + output.name
        observer = threading.Thread(target=runner_samples, args=(container, output, stop), daemon=True)
        observer.start()
        with (output / "k6.log").open("wb") as log:
            result = subprocess.run(k6_command(args, output, container), stdout=log, stderr=subprocess.STDOUT,
                                    timeout=args.seconds + args.warmup + 180)
        exit_code = result.returncode
        if exit_code == 0:
            metrics = json.loads((output / "summary.json").read_text())["metrics"]
            host.require(metrics["business_saves"]["values"]["count"] > 0
                         and metrics["business_failure"]["values"]["rate"] == 0
                         and metrics["checks"]["values"]["passes"] > 0
                         and metrics["checks"]["values"]["fails"] == 0,
                         "Browser run lacks successful checked business operations")
            workload_passed = True
    finally:
        stop.set()
        if observer:
            observer.join(timeout=15)
        try:
            cleanup_container(output)
        finally:
            metadata["k6_exit_code"] = exit_code
            metadata["status"] = "failed"
            if remote:
                try:
                    if ready:
                        remote.send({"action": "finish" if workload_passed else "abort",
                                     "operation_id": ready["operation_id"]})
                    else:
                        remote.process.stdin.close()
                    restored = remote.wait("restored", 600)["report"]
                    metadata["restoration"] = restored
                    host.require(restored["restoration"]["status"] == "recovered", "Host restoration did not pass")
                    if workload_passed:
                        host.require(restored["status"] == "finish" and restored["operation_id"] == ready["operation_id"]
                                     and restored["final_identity"] == ready["identity"],
                                     "Campaign identity changed before completion")
                        metadata["status"] = "passed"
                finally:
                    try:
                        remote.close()
                    finally:
                        metadata["ended_at"] = host.utc_now()
                        replace_json(output / "metadata.json", metadata)
            else:
                metadata["ended_at"] = host.utc_now()
                replace_json(output / "metadata.json", metadata)
    host.require(metadata["status"] == "passed", "Benchmark failed; private evidence retained")
    print("Benchmark and restoration passed. Private evidence:", output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    arm = parser.add_mutually_exclusive_group(required=True)
    arm.add_argument("--baseline", action="store_true")
    arm.add_argument("--candidate", type=Path)
    parser.add_argument("--workload", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--users", type=int, choices=range(1, 11), default=1)
    parser.add_argument("--mode", choices=["pilot", "mixed"], default="pilot")
    parser.add_argument("--seconds", type=int, default=10)
    parser.add_argument("--warmup", type=int, default=0)
    args = parser.parse_args()
    host.require(1 <= args.seconds <= 180 and 0 <= args.warmup <= 60, "Invalid bounded workload duration")
    for name in ["workload", "fixture", "output"]:
        setattr(args, name, getattr(args, name).resolve())
        host.require("," not in str(getattr(args, name)), "Docker mount paths cannot contain commas")
    run(args)


if __name__ == "__main__":
    try:
        main()
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit("Benchmark failed; inspect private evidence and confirm host restoration before retrying") from None
