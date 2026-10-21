"""Run the release against a fresh disposable database; preserve the live dataset.
Requires root on the VPS, a deployed immutable release and the accepted broker.
Usage: sudo python3 rehearse_host.py /home/ubuntu/apps/oracle-caddy /reviewed/rehearse.exs
"""
import json
import os
import pathlib
import re
import secrets
import subprocess
import sys
import tempfile
import urllib.parse


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=180).stdout


def envfile(path):
    return dict(line.strip().split("=", 1) for line in path.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#"))


def database_command(operation, database):
    if not re.fullmatch(r"instantflow_s08_[a-f0-9]{12}", database):
        raise ValueError("refusing non-rehearsal database")
    return command("docker", "exec", "oracle-caddy-instantflow-db-1", "sh", "-c",
                   'export PGPASSWORD="$POSTGRES_PASSWORD"; exec "$1" -U "$POSTGRES_USER" "$2"',
                   "sh", operation, database)


def main(root, source):
    if os.getuid() != 0:
        raise SystemExit("Requires root")
    image = envfile(root / "instantflow.image.env")["INSTANTFLOW_IMAGE"]
    if not re.fullmatch(r"ghcr.io/iagobg/instantflow:[a-f0-9]{40}", image):
        raise ValueError("immutable release required")
    values = envfile(root / "instantflow.operator.env")
    broker = envfile(pathlib.Path("/etc/instantflow-python/broker.env"))
    database = "instantflow_s08_" + secrets.token_hex(6)
    for key in ("OPERATOR_DATABASE_URL", "DATABASE_URL"):
        url = urllib.parse.urlsplit(values[key])
        values[key] = url._replace(path="/" + database).geturl()
    values.update({key: broker[key] for key in ("PYTHON_BROKER_TOKEN", "PYTHON_IMAGE", "PYTHON_BROKER_SOCKET")})
    values.update(PYTHON_EXECUTION="true", PYTHON_REHEARSAL_DATABASE=database, PHX_SERVER="",
                  ERL_FLAGS="+S 2:2")
    networks = json.loads(command("docker", "inspect", "--format", "{{json .NetworkSettings.Networks}}", "oracle-caddy-instantflow-1"))
    network = next(name for name in networks if name.endswith("_instantflow-db"))
    database_command("createdb", database)
    try:
        with tempfile.TemporaryDirectory(prefix="instantflow-s08-") as temporary:
            env = pathlib.Path(temporary) / "rehearsal.env"
            env.write_text("".join(key + "=" + value + "\n" for key, value in values.items()))
            env.chmod(0o600)
            output = command("docker", "run", "--rm", "--name", database, "--network", network, "--cpus", "1",
                             "--memory", "512m", "--pids-limit", "128", "--cap-drop", "ALL",
                             "--security-opt", "no-new-privileges", "--env-file", str(env),
                             "--mount", "type=bind,src=/run/instantflow-python,dst=/run/instantflow-python,readonly",
                             "--mount", "type=bind,src=" + str(source) + ",dst=/rehearse.exs,readonly",
                             image, "/app/bin/instantflow", "eval", 'Code.eval_file("/rehearse.exs")')
            # Emit only the JSON acceptance report, never raw process logs or environment.
            prefix = "INSTANTFLOW_PYTHON_REHEARSAL="
            report = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
            report["release_image"] = image
            report["cleanup"] = "one-off container and disposable database removed"
    except subprocess.CalledProcessError as error:
        diagnostic = pathlib.Path("/var/lib/instantflow-python")
        diagnostic.mkdir(mode=0o700, exist_ok=True)
        log = diagnostic / "rehearsal-diagnostic.log"
        log.write_text((error.stdout + "\n" + error.stderr)[-65536:])
        log.chmod(0o600)
        # Fixed message avoids dumping credentials, invitation tokens or arbitrary logs.
        raise RuntimeError("release rehearsal failed; inspect the protected operator diagnostic") from None
    finally:
        removed = subprocess.run(["docker", "rm", "-f", database], capture_output=True, text=True, timeout=10)
        if removed.returncode and "No such" not in removed.stderr:
            raise RuntimeError("rehearsal container cleanup failed")
        database_command("dropdb", database)
    pathlib.Path("/var/lib/instantflow-python/rehearsal-diagnostic.log").unlink(missing_ok=True)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve())
