"""Protocol/controller tests with trusted process stubs; these do NOT certify gVisor containment."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch
import broker


class BrokerTest(unittest.TestCase):
    def setUp(self):
        broker.HALTED.clear()
        self.image = "example.invalid/python@sha256:" + "a" * 64
        self.request = {"organization_id": 1, "run_id": 42, "fence": str(uuid.uuid4()),
                        "runtime": "a" * 64, "source": "def calculate(inputs): return {'total': 1}",
                        "input": {"participants": 81}}
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.enabled = str(pathlib.Path(self.temp.name) / "ENABLED")
        pathlib.Path(self.enabled).touch()

    def trusted_process(self, code):
        return patch("broker.docker_args", return_value=[sys.executable, "-c",
                     "import sys; sys.stdin.read(); " + code])

    def test_unix_socket_is_private_and_replaces_only_owned_socket(self):
        path = str(pathlib.Path(self.temp.name) / "broker.sock")
        with broker.make_server(path):
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o660)
        with broker.make_server(path):
            self.assertTrue(pathlib.Path(path).exists())
        os.unlink(path)
        pathlib.Path(path).write_text("do not replace")
        with self.assertRaises(ValueError):
            broker.make_server(path)
        self.assertEqual(pathlib.Path(path).read_text(), "do not replace")

    def test_duplicate_json_nonfinite_and_unpinned_runtime_are_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}'):
            with self.assertRaises(ValueError):
                broker.decode(raw)
        with self.assertRaises(ValueError):
            broker.validate(self.request, "python:latest")
        for key, value in (("runtime", "b" * 64), ("organization_id", True),
                           ("source", "x" * 32769), ("input", {"participants": True})):
            with self.subTest(key=key), self.assertRaises(ValueError):
                broker.validate({**self.request, key: value}, self.image)

    def test_gvisor_limits_network_denial_no_mounts_and_no_credentials(self):
        args = broker.docker_args(self.image, "test")
        for flag, value in (("--runtime", "runsc"), ("--network", "none"),
                            ("--memory", "128m"), ("--memory-swap", "128m"),
                            ("--pids-limit", "64"), ("--user", "65532:65532"),
                            ("--pull", "never"), ("--log-driver", "none")):
            self.assertEqual(args[args.index(flag) + 1], value)
        for prohibited in ("--privileged", "--volume", "-v", "--env", "-e", "--env-file"):
            self.assertNotIn(prohibited, args)
        self.assertIn("--read-only", args)

    def test_result_is_identity_bound_and_full_cleanup_is_requested(self):
        with self.trusted_process("print('{\"total\": 1}')"), patch("broker.subprocess.run") as cleanup:
            cleanup.return_value.returncode = 0
            response = broker.execute(self.request, self.image, self.enabled)
            self.assertEqual(response["status"], "succeeded")
            self.assertEqual(response["output"], {"total": 1})
            self.assertEqual(response["fence"], self.request["fence"])
            self.assertEqual(cleanup.call_args.args[0][1:3], ["rm", "-f"])
            self.assertNotIn("PYTHON_BROKER_TOKEN", cleanup.call_args.kwargs["env"])

    def test_output_flood_is_bounded_and_cleanup_still_runs(self):
        with self.trusted_process("sys.stdout.write('x' * 1000000)"), patch("broker.subprocess.run") as cleanup:
            cleanup.return_value.returncode = 0
            self.assertEqual(broker.execute(self.request, self.image, self.enabled)["status"], "failed")
            cleanup.assert_called_once()

    def test_wall_timeout_and_emergency_disable_fail_closed(self):
        with self.trusted_process("__import__('threading').Event().wait(20)"), patch("broker.WALL_SECONDS", 0.1), patch("broker.subprocess.run") as cleanup:
            cleanup.return_value.returncode = 0
            self.assertEqual(broker.execute(self.request, self.image, self.enabled)["status"], "timed_out")
        os.unlink(self.enabled)
        with patch("broker.subprocess.Popen") as launch:
            self.assertEqual(broker.execute(self.request, self.image, self.enabled)["status"], "failed")
            launch.assert_not_called()

    def test_cleanup_failure_never_returns_a_success(self):
        with self.trusted_process("print('{\"total\": 1}')"), patch("broker.subprocess.run") as cleanup:
            cleanup.return_value.returncode = 1
            with self.assertRaises(RuntimeError):
                broker.execute(self.request, self.image, self.enabled)


if __name__ == "__main__":
    unittest.main()
