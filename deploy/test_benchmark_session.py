import json
import os
import unittest
from unittest.mock import patch

import benchmark_host as host
import benchmark_legacy as legacy
import benchmark_rollout as rollout
import benchmark_session as session
import test_benchmark_host as fixture
import test_benchmark_rollout as rollout_fixture


class FakeChannel:
    def __init__(self, controller, completion="finish", disconnect_output=False):
        self.controller = controller
        self.completion = completion
        self.disconnect_output = disconnect_output
        self.events = []
        self.requests = 0

    def receive(self, seconds, sample=None):
        self.requests += 1
        if self.requests == 1:
            return {"action": "start", "application": host.baseline_application(), "hold_seconds": 60}
        if self.completion in {"expired", "disconnected", "unknown"}:
            return {"action": self.completion}
        return {"action": self.completion, "operation_id": self.controller.journal()["id"]}

    def emit(self, event):
        self.events.append(event)
        if event["event"] == "ready":
            with unittest.TestCase().assertRaisesRegex(host.GuardError, "host lock"):
                with host.host_lock():
                    raise AssertionError("Concurrent controller entered a live campaign")
            with unittest.TestCase().assertRaisesRegex(host.GuardError, "Interrupted operation"):
                self.controller.guard()
            if self.disconnect_output:
                raise BrokenPipeError("injected broken SSH output")


class SessionTest(unittest.TestCase):
    write = fixture.BenchmarkHostTest.write

    def setUp(self):
        fixture.BenchmarkHostTest.setUp(self)
        for name, value in [("capture", {"settings": {}, "statements_available": False}),
                            ("difference", {}), ("prune_obsolete_statements", {"available": False})]:
            patcher = patch.object(session.metrics, name, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_completion_abort_timeout_and_disconnect_restore_original_state_under_one_lock(self):
        for completion in ["finish", "abort", "expired", "disconnected", "unknown"]:
            with self.subTest(completion=completion):
                controller = rollout_fixture.RolloutHost(self.root)
                channel = FakeChannel(controller, completion)
                with host.host_lock():
                    code = session.Session(controller, channel).run()
                self.assertEqual(code, 0 if completion == "finish" else 1)
                self.assertEqual(controller.live_counts["tickets"], 15)
                self.assertEqual(controller.guard()["image"], host.BASE_IMAGE)
                self.assertEqual(channel.events[0]["ready"]["inventory"]["table_counts"]["tickets"], 12)
                self.assertEqual(channel.events[-1]["event"], "restored")
                self.assertFalse((self.root / "pending-operation.json").exists())

    def test_broken_output_pipe_does_not_prevent_recovery_and_host_report(self):
        controller = rollout_fixture.RolloutHost(self.root)
        channel = FakeChannel(controller, disconnect_output=True)
        with host.host_lock():
            self.assertEqual(session.Session(controller, channel).run(), 1)
        self.assertEqual(controller.live_counts["tickets"], 15)
        self.assertTrue(list((self.root / "operations").glob("*/campaign.json")))
        controller.guard()

    def test_statement_cleanup_precedes_counter_capture_and_failed_cleanup_restores(self):
        for fail in [False, True]:
            with self.subTest(fail=fail):
                controller = rollout_fixture.RolloutHost(self.root)
                channel = FakeChannel(controller)
                calls = []
                def prune(_):
                    calls.append("prune")
                    if fail:
                        raise host.GuardError("incomplete cleanup")
                    return {"available": True, "pruned_databases": 4}
                def capture(_):
                    calls.append("capture")
                    return {"settings": {}, "statements_available": False}
                with host.host_lock(), patch.object(session.metrics, "prune_obsolete_statements", prune), \
                        patch.object(session.metrics, "capture", capture):
                    self.assertEqual(session.Session(controller, channel).run(), 1 if fail else 0)
                self.assertEqual(calls, ["prune"] if fail else ["prune", "capture", "capture"])
                self.assertEqual(controller.live_counts["tickets"], 15)
                self.assertEqual(channel.events[-1]["report"]["restoration"]["status"], "recovered")
                self.assertFalse((self.root / "pending-operation.json").exists())

    def test_recovery_failure_retains_journal_and_cannot_emit_restored(self):
        controller = rollout_fixture.RolloutHost(self.root)
        channel = FakeChannel(controller)
        with host.host_lock(), patch.object(controller, "recover", side_effect=host.GuardError("failed")):
            with self.assertRaises(host.GuardError):
                session.Session(controller, channel).run()
        self.assertFalse(any(e["event"] == "restored" for e in channel.events))
        self.assertTrue((self.root / "pending-operation.json").exists())
        controller.recover()

    def test_wrong_completion_identifier_still_recovers_and_is_not_a_success(self):
        controller = rollout_fixture.RolloutHost(self.root)
        channel = FakeChannel(controller)
        channel.receive = lambda seconds, sample=None: (
            {"action": "finish", "operation_id": "operation-wrong"} if sample else
            {"action": "start", "application": host.baseline_application(), "hold_seconds": 60})
        with host.host_lock():
            self.assertEqual(session.Session(controller, channel).run(), 1)
        self.assertEqual(controller.live_counts["tickets"], 15)

    def test_candidate_ready_and_final_identity_are_candidate_but_recovery_is_original(self):
        controller = rollout_fixture.RolloutHost(self.root)
        channel = FakeChannel(controller)
        channel.receive = lambda seconds, sample=None: (
            {"action": "finish", "operation_id": controller.journal()["id"]} if sample else
            {"action": "start", "application": rollout_fixture.candidate(), "hold_seconds": 60})
        with host.host_lock(), patch.object(rollout, "verify_publication"):
            self.assertEqual(session.Session(controller, channel).run(), 0)
        report = channel.events[-1]["report"]
        self.assertEqual(report["final_identity"]["image"], rollout_fixture.candidate()["image"])
        self.assertEqual(report["restoration"]["identity"]["image"], host.BASE_IMAGE)
        self.assertNotIn("new_candidate_table", controller.live_counts)


class ChannelTest(unittest.TestCase):
    def setUp(self):
        self.read_fd, self.write_fd = os.pipe()
        self.addCleanup(os.close, self.read_fd)
        self.addCleanup(os.close, self.write_fd)

    def test_pipelined_messages_preserve_boundaries(self):
        os.write(self.write_fd, b'{"action":"one"}\n{"action":"two"}\n')
        channel = session.Channel(self.read_fd, lambda event: None)
        self.assertEqual(channel.receive(1), {"action": "one"})
        self.assertEqual(channel.receive(1), {"action": "two"})

    def test_partial_input_cannot_hold_lock_past_deadline(self):
        os.write(self.write_fd, b'{"action":')
        channel = session.Channel(self.read_fd, lambda event: None)
        with patch.object(session.time, "monotonic", side_effect=[0, 0, 0, 2]):
            self.assertEqual(channel.receive(1), {"action": "expired"})

    def test_oversized_or_malformed_requests_are_refused(self):
        channel = session.Channel(self.read_fd, lambda event: None)
        channel.buffer = b"x" * 16385
        with self.assertRaises(host.GuardError):
            channel.receive(1)
        channel.buffer = b"not-json\n"
        with self.assertRaises(json.JSONDecodeError):
            channel.receive(1)

    def test_legacy_reset_and_host_changes_refuse_without_accessing_docker(self):
        with patch.object(host.Host, "docker") as docker:
            for action in ["reset", "private-validation", "public-host", "sample"]:
                with self.assertRaisesRegex(host.GuardError, "Legacy"):
                    legacy.legacy_action(action)
            docker.assert_not_called()
