import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest

import benchmark_browser as browser
import benchmark_host as host


class BrowserDriverTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def assert_exited(self, pid):
        try:
            descriptor = os.pidfd_open(pid)
        except ProcessLookupError:
            return
        try:
            poller = select.poll()
            poller.register(descriptor, select.POLLIN)
            self.assertTrue(poller.poll(5000), "Task-owned browser descendant survived cleanup")
        finally:
            os.close(descriptor)

    def child_program(self, *, hang):
        return ("import subprocess,sys,signal\n"
                "child=subprocess.Popen([sys.executable,'-c',"
                "'import signal; signal.signal(signal.SIGTERM, signal.SIG_IGN); signal.pause()'],"
                "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
                "print(child.pid,flush=True)\n" + ("signal.pause()\n" if hang else ""))

    def test_timeout_terminates_controller_and_its_descendants(self):
        path = self.root / "output"
        with path.open("wb") as log, self.assertRaises(subprocess.TimeoutExpired):
            browser.execute([sys.executable, "-c", self.child_program(hang=True)], timeout=2, log=log)
        self.assert_exited(int(path.read_text()))

    def test_success_also_cleans_up_orphaned_descendants(self):
        result = browser.execute([sys.executable, "-c", self.child_program(hang=False)], timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assert_exited(int(result.stdout))

    def test_runtime_digest_covers_bytes_and_relative_names(self):
        path = self.root / "file"
        path.write_text("first")
        first = browser.tree_digest(self.root)
        path.write_text("second")
        second = browser.tree_digest(self.root)
        self.assertNotEqual(first, second)
        path.rename(self.root / "renamed")
        self.assertNotEqual(second, browser.tree_digest(self.root))

    def test_runtime_digest_refuses_unrecorded_external_files(self):
        (self.root / "link").symlink_to("/etc/hosts")
        with self.assertRaisesRegex(host.GuardError, "symlink"):
            browser.tree_digest(self.root)

    def test_runtime_must_be_explicit_before_any_browser_launch(self):
        with self.assertRaisesRegex(host.GuardError, "--node"):
            browser.identity(None, None)
