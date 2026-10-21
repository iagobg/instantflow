"""Exercise deployment ordering and failure handling without touching Docker."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("redeploy.sh").resolve()
IMAGE = "ghcr.io/iagobg/instantflow:" + "a" * 40


class RedeployTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "projects").mkdir()
        for name in ("instantflow.env", "instantflow.operator.env", "instantflow.db.env",
                     "projects/instantflow.compose.yml"):
            (self.root / name).write_text("placeholder\n")
        (self.root / ".env").write_text("OTHER_PROJECT=untouched\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        sudo = self.bin / "sudo"
        sudo.write_text("""#!/usr/bin/env python3
import os, sys
command = sys.argv[1:]
if command[0] == "-n":
    command.pop(0)
# Emulate sudo's env_reset: the image exported by the SSH shell is removed.
clean = {key: os.environ[key] for key in
         ("PATH", "COMMAND_LOG", "EXPECTED_IMAGE", "FAIL_AT") if key in os.environ}
os.execvpe(command[0], command, clean)
""")
        docker = self.bin / "docker"
        docker.write_text("""#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
# Docker must not consume the remaining deployment script streamed over SSH.
sys.stdin.buffer.read()
if os.environ.get("INSTANTFLOW_IMAGE") != os.environ["EXPECTED_IMAGE"]:
    sys.exit("Compose did not receive the selected image after sudo")
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(" ".join(args) + "\\n")
if (os.environ.get("FAIL_AT") in args or
    (os.environ.get("FAIL_AT") == "__health__" and "up" in args and "--no-deps" in args)):
    sys.exit(1)
if "pg_dump" in " ".join(args):
    sys.stdout.buffer.write(b"PGDMP-test-snapshot")
""")
        docker.chmod(0o755)
        sudo.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        COMMAND_LOG=str(self.root / "commands"), EXPECTED_IMAGE=IMAGE)

    def run_deploy(self, image=IMAGE):
        return subprocess.run(["bash", "-s", "--", str(self.root), image],
                              input=SCRIPT.read_text(), env=self.env,
                              capture_output=True, text=True)

    def commands(self):
        return (self.root / "commands").read_text().splitlines()

    def test_success_backs_up_before_stop_and_records_healthy_image(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        backup = next(i for i, cmd in enumerate(commands) if "pg_dump" in cmd)
        stop = next(i for i, cmd in enumerate(commands) if "stop instantflow" in cmd)
        migrate = next(i for i, cmd in enumerate(commands) if "run --rm" in cmd)
        start = next(i for i, cmd in enumerate(commands) if "up -d --no-deps" in cmd)
        self.assertLess(backup, stop)
        self.assertLess(stop, migrate)
        self.assertLess(migrate, start)
        self.assertEqual((self.root / "instantflow.image.env").read_text(),
                         "INSTANTFLOW_IMAGE=" + IMAGE + "\n")
        self.assertEqual((self.root / ".env").read_text(), "OTHER_PROJECT=untouched\n")
        backups = list((self.root / "backups/instantflow").glob("*.dump"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_pull_or_backup_failure_does_not_stop_the_app(self):
        for failure in ("pull", "exec"):
            with self.subTest(failure=failure):
                self.env["FAIL_AT"] = failure
                result = self.run_deploy()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any("stop instantflow" in c for c in self.commands()))
                self.assertFalse((self.root / "instantflow.image.env").exists())

    def test_migration_or_health_failure_preserves_previous_image_record(self):
        record = self.root / "instantflow.image.env"
        record.write_text("previous-image\n")
        for failure in ("run", "__health__"):
            with self.subTest(failure=failure):
                self.env["FAIL_AT"] = failure
                (self.root / "commands").write_text("")
                result = self.run_deploy()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(record.read_text(), "previous-image\n")
                if failure == "run":
                    self.assertFalse(any("up -d --no-deps" in c for c in self.commands()))

    def test_rejects_mutable_or_injected_image_before_docker(self):
        for image in ("ghcr.io/iagobg/instantflow:latest", IMAGE + ";echo bad"):
            with self.subTest(image=image):
                self.assertNotEqual(self.run_deploy(image).returncode, 0)
                self.assertFalse((self.root / "commands").exists())


if __name__ == "__main__":
    unittest.main()
