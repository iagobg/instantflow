"""One bounded campaign session: prepare, hold the host lock, then restore.

The controller uses newline-delimited JSON on stdin/stdout. Disconnect, timeout,
abort or failure all enter recovery. SIGKILL/power loss leave its durable journal.
"""
import json
import os
import select
import signal
import sys
import time

import benchmark_host as host
import benchmark_metrics as metrics
from benchmark_provenance import controller_hashes
from benchmark_rollout import Rollout, replace_json


class Channel:
    def __init__(self, fd, emit):
        self.fd, self.emit = fd, emit
        self.buffer = b""

    def receive(self, seconds, sample=None):
        deadline = time.monotonic() + seconds
        next_sample = time.monotonic() + 5
        while True:
            host.require(len(self.buffer) <= 16384, "Campaign control message too large")
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                return json.loads(line)
            now = time.monotonic()
            if now >= deadline:
                return {"action": "expired"}
            if sample and now >= next_sample:
                self.emit({"event": "sample", "sample": sample()})
                next_sample = time.monotonic() + 5
            wait = min(deadline, next_sample) - time.monotonic() if sample else deadline - now
            if select.select([self.fd], [], [], max(0, wait))[0]:
                data = os.read(self.fd, 16385)
                if not data:
                    return {"action": "disconnected"}
                self.buffer += data


class Session:
    def __init__(self, controller, channel):
        self.controller, self.channel = controller, channel
        self.sample_count = 0

    def sample(self):
        self.sample_count += 1
        data = self.controller.docker("stats", "--no-stream", "--format", "{{json .}}",
            host.PROJECT + "-web", host.PROJECT + "-db", label="benchmark resource sample", timeout=10)
        return {"unix_time": time.time(), "containers": [json.loads(line) for line in data.decode().splitlines()],
                "postgres": metrics.capture(self.controller, activity_only=True)}

    def run(self):
        request = self.channel.receive(15)
        host.require(set(request) == {"action", "application", "hold_seconds"} and request["action"] == "start"
                     and type(request["hold_seconds"]) is int and 30 <= request["hold_seconds"] <= 600,
                     "Invalid bounded campaign request")
        application = host.validate_application(request["application"])
        self.controller.guard()
        ready = self.controller.switch(application, fixture=True, hold=True)
        journal = self.controller.journal()
        report = {"operation_id": journal["id"], "application": application, "status": "interrupted"}
        try:
            report["statement_preparation"] = metrics.prune_obsolete_statements(self.controller)
            before = metrics.capture(self.controller)
            report["metrics_before"] = before
            ready["metrics_settings"] = before["settings"]
            ready["statement_statistics_available"] = before["statements_available"]
            ready["controller_sha256"] = controller_hashes()
            self.channel.emit({"event": "ready", "ready": ready})
            command = self.channel.receive(request["hold_seconds"], self.sample)
            host.require(command["action"] in {"finish", "abort", "expired", "disconnected"},
                         "Unknown campaign completion request")
            if command["action"] in {"finish", "abort"}:
                host.require(set(command) == {"action", "operation_id"} and command["operation_id"] == journal["id"],
                             "Campaign completion identifier mismatch")
            report["status"] = command["action"]
            report["final_identity"] = self.controller.guard(transition=self.controller.context(journal), ready=True)
            self.controller.runtime_guard()
            report["final_inventory"] = self.controller.inventory(host.DATABASE)
            after = metrics.capture(self.controller)
            report["metrics_after"] = after
            report["metrics_delta"] = metrics.difference(before, after)
            report["activity_samples"] = self.sample_count
        except Exception:
            report["status"] = "failed"
        finally:
            # Persist recovery before emitting the final message. A broken SSH pipe
            # cannot prevent restoration or erase its host-side evidence.
            report["restoration"] = self.controller.recover()
            replace_json(self.controller.operation_folder(journal) / "campaign.json", report)
        self.channel.emit({"event": "restored", "report": report})
        return 0 if report["status"] == "finish" else 1


def main():
    os.umask(0o077)
    def interrupted(signum, frame):
        raise InterruptedError("Campaign signal interruption")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    with host.host_lock():
        channel = Channel(sys.stdin.fileno(), lambda event: print(json.dumps(event), flush=True))
        return Session(Rollout(), channel).run()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit("Campaign failed; verify host recovery journal before further work") from None
