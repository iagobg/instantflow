"""Trusted image entrypoint. Python itself is not the isolation boundary."""
import contextlib
import json
import sys

request = json.load(sys.stdin)
namespace = {"__name__": "__calculation__"}
# All user code, including imports/module initialization, runs inside gVisor.
with contextlib.redirect_stdout(sys.stderr):
    exec(compile(request["source"], "<uploaded-calculation>", "exec"), namespace)
    output = namespace["calculate"](request["input"])
sys.stdout.write(json.dumps(output, allow_nan=False, separators=(",", ":")))
