"""Local authenticated gVisor broker, via Unix socket or loopback. Separate from Phoenix."""
import hmac
import http.server
import json
import os
import re
import selectors
import socketserver
import stat
import signal
import subprocess
import threading
import time
import uuid

MAX_REQUEST = 65536
MAX_OUTPUT = 16384
MAX_TOTAL_OUTPUT = 20480
WALL_SECONDS = 5
DOCKER = os.environ.get("PYTHON_DOCKER_BINARY", "/usr/bin/docker")
SLOTS = threading.BoundedSemaphore(2)
TENANTS = set()
TENANT_LOCK = threading.Lock()
HALTED = threading.Event()


def decode(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite")))


def validate(request, image):
    if not isinstance(request, dict) or set(request) != {
        "organization_id", "run_id", "fence", "runtime", "source", "input"
    }:
        raise ValueError("request shape")
    if type(request["organization_id"]) is not int or request["organization_id"] <= 0:
        raise ValueError("organization")
    if not (type(request["run_id"]) is int and request["run_id"] > 0 or
            isinstance(request["run_id"], str) and re.fullmatch(r"fixture:[0-9a-f-]{36}", request["run_id"])):
        raise ValueError("run")
    if not isinstance(request["fence"], str) or str(uuid.UUID(request["fence"])) != request["fence"]:
        raise ValueError("fence")
    if not re.fullmatch(r"(?:[a-zA-Z0-9./:_-]+@)?sha256:[0-9a-f]{64}", image):
        raise ValueError("image must be digest pinned")
    if request["runtime"] != image.rsplit(":", 1)[1]:
        raise ValueError("unapproved runtime")
    if not isinstance(request["source"], str) or not 1 <= len(request["source"].encode()) <= 32768:
        raise ValueError("source size")
    if not isinstance(request["input"], dict) or len(json.dumps(request["input"]).encode()) > 16384:
        raise ValueError("input size")
    if not 1 <= len(request["input"]) <= 16 or not all(
        re.fullmatch(r"[a-z][a-z0-9_]{0,63}", k) and type(v) is int and abs(v) <= 1000000000
        for k, v in request["input"].items()
    ):
        raise ValueError("input contract")


def docker_args(image, name):
    return [DOCKER, "run", "--name", name, "--label", "instantflow.python=true",
            "--pull", "never", "--runtime", "runsc", "--network", "none", "--ipc", "none",
            "--read-only", "--user", "65532:65532", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--cpus", "1",
            "--memory", "128m", "--memory-swap", "128m", "--pids-limit", "64",
            "--ulimit", "nproc=32:32", "--ulimit", "nofile=64:64", "--ulimit", "core=0:0",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=8m,mode=1777",
            "--cgroup-parent", "instantflow-python.slice", "--log-driver", "none",
            "-i", "--entrypoint", "/usr/local/bin/python3", image, "-I", "-B", "/opt/runner.py"]


def execute(request, image, enabled_file):
    validate(request, image)
    identity = {k: request[k] for k in ("organization_id", "run_id", "fence")}
    if HALTED.is_set() or not os.path.isfile(enabled_file):
        return {**identity, "status": "failed"}
    name = "instantflow-python-" + uuid.uuid4().hex
    # No identity or broker token enters the workload. Fresh unnamed tmpfs; no host mounts.
    payload = json.dumps({k: request[k] for k in ("source", "input")}, ensure_ascii=True).encode()
    env = {"PATH": "/usr/bin:/bin", "HOME": "/var/empty", "DOCKER_HOST": "unix:///var/run/docker.sock"}
    proc = None
    selector = None
    result = {**identity, "status": "failed"}
    try:
        proc = subprocess.Popen(docker_args(image, name), stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=env, start_new_session=True)
        selector = selectors.DefaultSelector()
        for pipe in (proc.stdin, proc.stdout, proc.stderr):
            os.set_blocking(pipe.fileno(), False)
        selector.register(proc.stdin, selectors.EVENT_WRITE, "in")
        selector.register(proc.stdout, selectors.EVENT_READ, "out")
        selector.register(proc.stderr, selectors.EVENT_READ, "err")
        sent, total, output = 0, 0, bytearray()
        deadline = time.monotonic() + WALL_SECONDS
        while selector.get_map():
            if time.monotonic() >= deadline:
                result = {**identity, "status": "timed_out"}
                break
            if HALTED.is_set() or not os.path.isfile(enabled_file):
                break
            exceeded = False
            for key, _ in selector.select(timeout=0.05):
                pipe = key.fileobj
                if key.data == "in":
                    try:
                        sent += os.write(pipe.fileno(), payload[sent:sent + 4096])
                    except BrokenPipeError:
                        sent = len(payload)
                    if sent == len(payload):
                        selector.unregister(pipe)
                        pipe.close()
                else:
                    chunk = os.read(pipe.fileno(), 4096)
                    if not chunk:
                        selector.unregister(pipe)
                        pipe.close()
                        continue
                    total += len(chunk)
                    if key.data == "out":
                        output.extend(chunk)
                    if total > MAX_TOTAL_OUTPUT or len(output) > MAX_OUTPUT:
                        exceeded = True
                        break
            if exceeded:
                break
        completed = not selector.get_map()
        selector.close()
        if completed and proc.wait(timeout=max(0.1, deadline - time.monotonic())) == 0 and total <= MAX_TOTAL_OUTPUT and len(output) <= MAX_OUTPUT:
            value = decode(output)
            if isinstance(value, dict):
                result = {**identity, "status": "succeeded", "output": value}
    except (OSError, ValueError, RecursionError, subprocess.SubprocessError):
        pass
    finally:
        # Removing the container kills its complete cgroup, including detached descendants.
        try:
            cleanup = subprocess.run([DOCKER, "rm", "-f", name], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            if cleanup.returncode != 0:
                raise RuntimeError("cleanup failed")
        except Exception:
            HALTED.set()  # Require operator reconciliation before this broker accepts more work.
            raise
        finally:
            if selector is not None:
                selector.close()
            if proc is not None:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=2)
                for pipe in (proc.stdin, proc.stdout, proc.stderr):
                    if not pipe.closed:
                        pipe.close()
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Source, inputs, tokens, stdout and request URLs are never ordinary logs.

    def setup(self):
        super().setup()
        self.connection.settimeout(2)

    def reply(self, code, data):
        raw = json.dumps(data, allow_nan=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        acquired = False
        organization_id = None
        try:
            token = self.headers.get("Authorization", "")
            if not hmac.compare_digest(token, "Bearer " + self.server.token):
                self.reply(403, {})
                return
            if self.path != "/run" or self.headers.get("Transfer-Encoding"):
                self.reply(400, {})
                return
            size = int(self.headers.get("Content-Length", "0"))
            if not 1 <= size <= MAX_REQUEST:
                self.reply(413, {})
                return
            raw = self.rfile.read(size)
            if len(raw) != size:
                raise ValueError("incomplete request")
            request = decode(raw)
            validate(request, self.server.image)
            if not SLOTS.acquire(blocking=False):
                self.reply(429, {})
                return
            acquired = True
            with TENANT_LOCK:
                if request["organization_id"] in TENANTS:
                    self.reply(429, {})
                    return
                organization_id = request["organization_id"]
                TENANTS.add(organization_id)
            self.reply(200, execute(request, self.server.image, self.server.enabled_file))
        except (ValueError, TypeError, KeyError, RecursionError):
            self.reply(400, {})
        except Exception:
            self.reply(503, {})
        finally:
            if organization_id is not None:
                with TENANT_LOCK:
                    TENANTS.discard(organization_id)
            if acquired:
                SLOTS.release()


class UnixHTTPServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def make_server(socket_path=None):
    if not socket_path:
        return http.server.ThreadingHTTPServer(("127.0.0.1", 4010), Handler)
    if not os.path.isabs(socket_path):
        raise ValueError("broker socket path must be absolute")
    if os.path.lexists(socket_path):
        info = os.lstat(socket_path)
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("refusing to replace a foreign socket or regular file")
        os.unlink(socket_path)
    server = UnixHTTPServer(socket_path, Handler)
    group = int(os.environ.get("PYTHON_BROKER_SOCKET_GID", str(os.getgid())))
    os.chown(socket_path, -1, group)
    os.chmod(socket_path, 0o660)
    return server


def reconcile_startup():
    """Do not reset admission counters while earlier broker workloads survive."""
    listed = subprocess.run([DOCKER, "ps", "-aq", "--filter", "label=instantflow.python=true"],
                            check=True, capture_output=True, text=True, timeout=5)
    for container in listed.stdout.split():
        if not re.fullmatch(r"[0-9a-f]{12,64}", container):
            raise RuntimeError("unexpected orphan identity")
        removed = subprocess.run([DOCKER, "rm", "-f", container],
                                 capture_output=True, text=True, timeout=5)
        if removed.returncode and "No such" not in removed.stderr:
            raise RuntimeError("orphan cleanup failed")
    remaining = subprocess.run([DOCKER, "ps", "-aq", "--filter", "label=instantflow.python=true"],
                               check=True, capture_output=True, text=True, timeout=5)
    if remaining.stdout.strip():
        raise RuntimeError("orphan reconciliation incomplete")


def serve():
    token = os.environ["PYTHON_BROKER_TOKEN"]
    image = os.environ["PYTHON_IMAGE"]
    if len(token.encode()) < 32:
        raise ValueError("token requires at least 32 bytes")
    # Fail closed if the required runtime is absent; never fall back to ordinary runc.
    info = subprocess.run([DOCKER, "info", "--format", "{{json .Runtimes}}"],
                          check=True, capture_output=True, timeout=5)
    if "runsc" not in decode(info.stdout):
        raise RuntimeError("runsc required")
    reconcile_startup()
    server = make_server(os.environ.get("PYTHON_BROKER_SOCKET"))
    server.token = token
    server.image = image
    server.enabled_file = os.environ.get("PYTHON_ENABLED_FILE", "/etc/instantflow-python/ENABLED")
    server.serve_forever()


if __name__ == "__main__":
    serve()
