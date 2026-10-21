"""Host acceptance harness. Requires real runsc; never falls back to a host interpreter/runc.
Run on an isolated synthetic deployment before enabling application execution.
"""
import datetime
import json
import os
import pathlib
import platform
import subprocess
import time
import uuid
import broker


def main():
    image = os.environ["PYTHON_IMAGE"]
    marker = os.environ.get("PYTHON_ENABLED_FILE", "/etc/instantflow-python/ENABLED")
    info = subprocess.run([broker.DOCKER, "info", "--format", "{{json .Runtimes}}"],
                          check=True, capture_output=True, timeout=5)
    if "runsc" not in broker.decode(info.stdout):
        raise SystemExit("Refused: real runsc runtime is not registered")
    if not pathlib.Path(marker).is_file():
        raise SystemExit("Refused: operator ENABLED marker is absent")
    report = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "architecture": platform.machine(), "kernel": platform.release(), "image": image,
              "limits": {"wall_seconds": 5, "cpu": 1, "memory_mib": 128, "pids": 16,
                         "scratch_mib": 8, "stdout_bytes": 16384, "combined_output_bytes": 20480},
              "tests": []}

    def run(name, source, expected=None, failures=False, org=1):
        request = {"organization_id": org, "run_id": "fixture:" + str(uuid.uuid4()),
                   "fence": str(uuid.uuid4()), "runtime": image.rsplit(":", 1)[1],
                   "source": source, "input": {"synthetic": 1}}
        started = time.monotonic()
        result = broker.execute(request, image, marker)
        elapsed = round(time.monotonic() - started, 3)
        identity = all(result.get(k) == request[k] for k in ("organization_id", "run_id", "fence"))
        passed = identity and (result["status"] in ("failed", "timed_out") if failures else
                               result["status"] == "succeeded" and result.get("output") == expected)
        report["tests"].append({"name": name, "passed": passed, "status": result["status"], "seconds": elapsed})
        if not passed:
            raise RuntimeError("Acceptance failed: " + name)

    run("valid_calculation", "def calculate(x): return {'total': x['synthetic'] * 402000}", {"total": 402000})
    run("host_files_credentials_denied", """def calculate(x):
 import os
 return {'denied': int(not os.path.exists('/var/run/docker.sock') and not os.path.exists('/etc/instantflow-python/ENABLED') and not os.path.exists('/etc/instantflow-python/broker.env') and 'PYTHON_BROKER_TOKEN' not in os.environ and 'DATABASE_URL' not in os.environ)}
""", {"denied": 1})
    run("ipv4_ipv6_dns_denied", """def calculate(x):
 import socket
 denied = 0
 for family, address in [(socket.AF_INET, ('169.254.169.254', 80)), (socket.AF_INET, ('127.0.0.1', 55432)), (socket.AF_INET6, ('::1', 55432))]:
  try:
   with socket.socket(family, socket.SOCK_STREAM) as s:
    s.settimeout(.2)
    s.connect(address)
  except OSError: denied += 1
 try: socket.getaddrinfo('example.com', 443)
 except OSError: denied += 1
 return {'denied': denied}
""", {"denied": 4})
    run("readonly_root", """def calculate(x):
 try:
  open('/escape', 'w').write('synthetic')
  return {'denied': 0}
 except OSError: return {'denied': 1}
""", {"denied": 1})
    run("scratch_first_tenant", """def calculate(x):
 open('/tmp/cross-tenant', 'w').write('synthetic')
 return {'written': 1}
""", {"written": 1}, org=1)
    run("fresh_scratch_other_tenant", """def calculate(x):
 import os
 return {'clean': int(not os.path.exists('/tmp/cross-tenant'))}
""", {"clean": 1}, org=2)
    run("cpu_timeout", "def calculate(x):\n while True: pass", failures=True)
    run("memory_exhaustion", "def calculate(x):\n return {'bad': len(bytearray(512 * 1024 * 1024))}", failures=True)
    run("stdout_exhaustion", "def calculate(x):\n print('x' * 1000000)\n return {'total': 1}", failures=True)
    run("scratch_exhaustion", "def calculate(x):\n open('/tmp/full', 'wb').write(b'x' * (16 * 1024 * 1024))\n return {'total': 1}", failures=True)
    run("process_limit", """def calculate(x):
 import subprocess
 children = []
 try:
  for _ in range(100): children.append(subprocess.Popen(['sleep', '10']))
 except OSError: return {'bounded': 1}
 return {'bounded': 0}
""", {"bounded": 1})
    run("healthy_after_exhaustion", "def calculate(x): return {'healthy': 1}", {"healthy": 1}, org=2)
    leftovers = subprocess.run([broker.DOCKER, "ps", "-aq", "--filter", "label=instantflow.python=true"],
                              check=True, capture_output=True, timeout=5)
    if leftovers.stdout.strip():
        raise RuntimeError("Acceptance failed: leftover labelled workloads")
    report["cleanup"] = "no labelled containers remain"
    report["limitations"] = "Targeted tests do not prove absence of escapes, side channels or host-wide DoS. Concurrency and application recovery must also pass."
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
