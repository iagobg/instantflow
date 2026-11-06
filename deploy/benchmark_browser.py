"""Local Playwright functional driver with recorded runtime bytes and bounded cleanup."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess

import benchmark_host as host


def tree_digest(folder):
    digest = hashlib.sha256()
    for path in sorted(folder.rglob("*")):
        host.require(not path.is_symlink(), "Browser runtime contains an unsupported symlink")
        if path.is_file():
            digest.update(path.relative_to(folder).as_posix().encode() + b"\0")
            digest.update(host.digest(path).encode() + b"\n")
    return digest.hexdigest()


def execute(command, *, timeout, log=None):
    process = subprocess.Popen(command, stdout=subprocess.PIPE if log is None else log,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(command, process.returncode, output)
    finally:
        # This controller process group belongs to this invocation only.
        # Playwright's SIGTERM/exit handlers close its detached browser groups.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)


def identity(node, package):
    host.require(node is not None and package is not None, "Contention requires --node and --playwright-package")
    node, package = node.resolve(), package.resolve()
    host.require(node.is_file() and package.is_dir(), "Local browser runtime is missing")
    host.require(json.loads((package / "package.json").read_text())["version"] == "1.64.1",
                 "Expected the existing Playwright 1.64.1 runtime")
    program = """
      const {chromium}=require(process.argv[1]);
      (async()=>{const executable=chromium.executablePath();
        const browser=await chromium.launch({executablePath:executable,headless:true});
        try {console.log(JSON.stringify({node:process.version,chromium:browser.version(),executable}));}
        finally {await browser.close();}
      })().catch(()=>{console.error('Browser runtime preflight failed');process.exitCode=1;});
    """
    result = execute([str(node), "-e", program, str(package)], timeout=60)
    host.require(result.returncode == 0, "Local Playwright preflight failed; Node 20+ and installed Chromium are required")
    observed = json.loads(result.stdout)
    executable = Path(observed["executable"]).resolve()
    host.require(executable.is_file(), "Browser executable is missing")
    return {"driver": "playwright", "playwright_version": "1.64.1",
            "node_version": observed["node"], "chromium_version": observed["chromium"],
            "node_sha256": host.digest(node), "package_sha256": tree_digest(package),
            "chromium_distribution_sha256": tree_digest(executable.parent),
            "driver_source_sha256": host.digest(Path(__file__)),
            "_node": str(node), "_package": str(package), "_executable": str(executable)}


def run(args, output, runtime):
    command = [runtime["_node"], str(args.workload), str(args.fixture), str(output), str(args.users),
               runtime["_package"], runtime["_executable"]]
    with (output / "browser.log").open("wb") as log:
        return execute(command, timeout=180, log=log)
