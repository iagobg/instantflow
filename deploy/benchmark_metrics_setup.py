"""Enable statement/I/O statistics only on the guarded benchmark PostgreSQL stack."""
import argparse
import copy
import json
import os
import re
import secrets

import benchmark_host as host
import benchmark_metrics as metrics
from benchmark_rollout import Rollout, replace_json, sync_directory


class Setup(Rollout):
    def pending(self, journal=None):
        path = host.ROOT / "pending-metrics.json"
        if journal is not None:
            replace_json(path, journal)
        return host.read_json(path)

    def validate_pending(self, journal):
        host.require(journal["schema"] == 1 and re.fullmatch(r"metrics-[0-9a-f]{12}", journal["id"]),
                     "Invalid metrics recovery journal")
        marker = host.read_json(host.ROOT / "fixture.json")
        source = journal["source_config"]
        host.validate_config(source, marker, host.application_for(source))
        host.require("command" not in source["services"]["db"], "Unsupported metrics source configuration")
        target = copy.deepcopy(source)
        target["services"]["db"]["command"] = host.METRICS_COMMAND
        host.require(host.read_json(host.ROOT / "compose.json") in [source, target], "Metrics configuration drift")
        host.require(set(journal["fixed_files"]) == set(host.CONFIG_FILES) - {"compose.json"}
                     and all(host.digest(host.private_path(host.ROOT / k)) == v for k,v in journal["fixed_files"].items()),
                     "Private configuration drift during metrics recovery")

    def start_database(self):
        self.compose("up", "-d", "--no-deps", "--pull", "never", "--wait", "--wait-timeout", "90", "db")

    def finish(self, journal, result):
        folder = host.ROOT / "metrics-setups"
        folder.mkdir(mode=0o700, exist_ok=True)
        host.private_path(folder, directory=True)
        replace_json(folder / (journal["id"] + ".json"), result)
        (host.ROOT / "pending-metrics.json").unlink()
        sync_directory(host.ROOT)
        return result

    def recover_metrics(self):
        journal = self.pending()
        self.validate_pending(journal)
        # During recovery only known lifecycle/configuration changes are allowed
        # until PostgreSQL is healthy enough to check exclusive database ownership.
        self.guard(maintenance=True)
        self.compose("stop", "web")
        replace_json(host.ROOT / "compose.json", journal["source_config"])
        self.start_database()
        self.guard(stopped=True, maintenance=True)
        self.sql(host.DATABASE, "DROP EXTENSION IF EXISTS pg_stat_statements; DROP SCHEMA IF EXISTS instantflow_benchmark_metrics;")
        if journal["inventory"]:
            host.require(self.inventory(host.DATABASE) == journal["inventory"], "Application inventory changed during metrics recovery")
        self.start()
        identity = self.guard(maintenance=True, ready=True)
        smoke = self.smoke()
        return self.finish(journal, {"status":"recovered", "identity":identity, "smoke":smoke})

    def enable(self):
        self.guard()
        source = host.read_json(host.ROOT / "compose.json")
        if source["services"]["db"].get("command") == host.METRICS_COMMAND:
            metrics.ensure_extension(self)
            return {"status":"already_enabled", "metrics":metrics.capture(self)}
        host.require(self.sql(host.DATABASE,
            "SELECT count(*) FROM pg_extension WHERE extname='pg_stat_statements';") == "0",
            "An existing unmanaged statement extension requires explicit review")
        host.require(self.sql(host.DATABASE,
            "SELECT count(*) FROM pg_namespace WHERE nspname='instantflow_benchmark_metrics';") == "0",
            "An existing unmanaged statistics schema requires explicit review")
        self.smoke()
        backup = self.snapshot()
        journal = {"schema":1, "id":"metrics-" + secrets.token_hex(6), "source_config":source,
                   "snapshot":backup["snapshot_id"], "inventory":None,
                   "fixed_files":{k:host.digest(host.ROOT / k) for k in host.CONFIG_FILES if k != "compose.json"}}
        self.pending(journal)
        try:
            self.compose("stop", "web")
            self.guard(stopped=True, maintenance=True)
            journal["inventory"] = self.inventory(host.DATABASE)
            self.pending(journal)
            target = copy.deepcopy(source)
            target["services"]["db"]["command"] = host.METRICS_COMMAND
            replace_json(host.ROOT / "compose.json", target)
            self.start_database()
            self.guard(stopped=True, maintenance=True)
            metrics.ensure_extension(self)
            host.require(self.sql(host.DATABASE,
                "SELECT NOT has_schema_privilege('instantflow_runtime','instantflow_benchmark_metrics','USAGE');") == "t",
                "Runtime can access operator statement statistics")
            host.require(self.inventory(host.DATABASE) == journal["inventory"], "Application inventory changed during metrics setup")
            self.start()
            identity = self.guard(maintenance=True, ready=True)
            smoke = self.smoke()
            observed = metrics.capture(self)
            host.require(observed["statements_available"] and observed["settings"]["track_io_timing"] == "on"
                         and observed["settings"]["track_wal_io_timing"] == "on", "Metrics settings did not take effect")
            return self.finish(journal, {"status":"enabled", "identity":identity, "smoke":smoke,
                "snapshot":backup["snapshot_id"], "application_inventory_preserved":True,
                "settings":observed["settings"], "runtime_statistics_access_denied":True})
        except BaseException:
            try:
                self.recover_metrics()
            except BaseException:
                raise host.GuardError("Metrics setup failed; recovery incomplete. Run benchmark_metrics_setup.py recover") from None
            raise host.GuardError("Metrics setup failed; previous configuration and application recovered") from None


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["enable","recover"])
    args=parser.parse_args()
    os.umask(0o077)
    with host.host_lock():
        controller=Setup()
        result=controller.enable() if args.action=="enable" else controller.recover_metrics()
        print(json.dumps(result,indent=2,sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit("Metrics setup failed; inspect the private recovery journal before further operations") from None
