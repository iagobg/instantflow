import datetime
import json
import subprocess
import unittest
from unittest.mock import patch
import reap


class ReaperTest(unittest.TestCase):
    def result(self, text="", code=0, error=""):
        return subprocess.CompletedProcess([], code, text, error)

    def test_nanosecond_timestamps_and_labelled_orphans(self):
        inspected = json.dumps([{"Config": {"Labels": {"instantflow.python": "true"}},
                                 "Created": "2026-10-21T00:00:00.123456789Z"}])
        with patch("reap.docker", side_effect=[self.result("orphan"), self.result(inspected),
                                               self.result()]) as docker:
            reap.reap(datetime.datetime(2026, 10, 21, 0, 0, 20, tzinfo=datetime.timezone.utc))
            self.assertEqual(docker.call_args.args, ("rm", "-f", "orphan"))

    def test_broker_removal_race_is_safe(self):
        with patch("reap.docker", side_effect=[self.result("gone"),
                                               self.result(code=1, error="Error: No such object: gone")]) as docker:
            reap.reap()
            self.assertEqual(docker.call_count, 2)

    def test_daemon_failure_is_reported(self):
        with patch("reap.docker", return_value=self.result(code=1, error="daemon unavailable")):
            with self.assertRaises(subprocess.CalledProcessError):
                reap.reap()
