"""Operator-only build from a resolved official base; prints only public image identities."""
import json
import os
import pathlib
import subprocess
import sys


def docker(*args):
    return subprocess.run(["docker", *args], check=True, capture_output=True, text=True).stdout.strip()


if __name__ == "__main__":
    if os.getuid() != 0:
        raise SystemExit("Requires root")
    source = pathlib.Path(sys.argv[1]).resolve()
    docker("pull", "python:3.12-slim-bookworm")
    base = json.loads(docker("image", "inspect", "python:3.12-slim-bookworm"))[0]["RepoDigests"][0]
    docker("build", "--build-arg", "PYTHON_BASE=" + base, "-t", "instantflow-python:reviewed", str(source))
    image = json.loads(docker("image", "inspect", "instantflow-python:reviewed"))[0]["Id"]
    env = pathlib.Path("/etc/instantflow-python/broker.env")
    values = dict(line.split("=", 1) for line in env.read_text().splitlines() if line)
    values["PYTHON_IMAGE"] = image
    env.write_text("".join(key + "=" + value + "\n" for key, value in values.items()))
    print(json.dumps({"python_base": base, "image": image}))
