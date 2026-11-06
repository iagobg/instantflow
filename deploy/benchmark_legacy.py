"""Install as remote.py to disable the old runner's unguarded reset entry point."""
import argparse
import json

import benchmark_host as host


def legacy_action(action):
    host.require(action == "status", "Legacy benchmark mutations/sampling disabled; use benchmark_run.py or benchmark_rollout.py")
    with host.host_lock():
        controller = host.Host()
        return {"identity": controller.guard(), "inventory": controller.inventory(host.DATABASE)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action")
    parser.add_argument("--seconds")
    args = parser.parse_args()
    try:
        print(json.dumps(legacy_action(args.action), indent=2))
    except host.GuardError as error:
        raise SystemExit(str(error)) from None
