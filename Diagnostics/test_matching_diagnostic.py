import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import subprocess
from types import SimpleNamespace
from controlled_matching_run import valid_matching_report, experiment_completed, run_saved_with_response
from matching_face_stream import run_with_one_event


class MatchingTransportTests(unittest.TestCase):
    def invoke(self, payload, callback):
        marker = b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed'
        result, report = run_with_one_event(
            [sys.executable, '-c', 'import sys,time;sys.stdout.buffer.write('+repr(payload)+');sys.stdout.flush();time.sleep(0.25)'],
            env=os.environ.copy(), cwd=Path(__file__).parent, timeout=10,
            expected_line=marker, on_event=callback,
            partial=lambda *_: self.fail('Unexpected partial output'))
        self.assertEqual(result.returncode, 0)
        return result, report

    def test_exact_event_once_preserves_private_output(self):
        calls = []
        payload = b'PRIVATE-FIXTURE-NOT-EXPORTED\nNIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed\n'
        result, report = self.invoke(payload, calls.append)
        self.assertEqual(len(calls), 1)
        self.assertEqual(report['exactEventCount'], 1)
        self.assertFalse(report['callbackFailed'])
        self.assertNotIn('PRIVATE-FIXTURE', repr(report))
        self.assertIn('PRIVATE-FIXTURE', result.stdout)

    def test_duplicate_does_not_repeat_action(self):
        calls = []
        payload = (b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed\n')*2
        _, report = self.invoke(payload, calls.append)
        self.assertEqual(len(calls), 1)
        self.assertEqual(report['exactEventCount'], 2)
        self.assertFalse(experiment_completed({'matchingExperiment': {
            'status': 'Official-action-returned-success', 'authenticationPromptObserved': True, 'transport': report}}))

    def test_foreign_nonce_and_unterminated_line_do_not_trigger(self):
        calls = []
        payload = b'NIDAA_PICKER_MATCH_REQUEST:'+b'b'*32+b':face_id_prompt_observed\n'
        payload += b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed'
        _, report = self.invoke(payload, calls.append)
        self.assertEqual(calls, [])
        self.assertEqual(report['exactEventCount'], 0)
        self.assertTrue(report['foreignEventObserved'])

    def test_uncertain_callback_never_retried(self):
        calls = []
        def fail_once(_):
            calls.append(True)
            raise ValueError('Private error must not be exported')
        _, report = self.invoke((b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed\n')*2, fail_once)
        self.assertEqual(len(calls), 1)
        self.assertTrue(report['callbackFailed'])
        self.assertNotIn('Private error', repr(report))

    def test_buffered_event_after_process_exit_never_acts(self):
        calls = []
        popen = subprocess.Popen
        def already_finished(*args, **kwargs):
            child = popen(*args, **kwargs)
            child.wait(timeout=10)
            return child
        with patch('matching_face_stream.subprocess.Popen', side_effect=already_finished):
            _, report = self.invoke(b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':face_id_prompt_observed\n', calls.append)
        self.assertEqual(calls, [])
        self.assertTrue(report['lateEventObserved'])
        self.assertFalse(experiment_completed({'matchingExperiment': {
            'status': 'Official-action-returned-success', 'authenticationPromptObserved': True, 'transport': report}}))

    def test_helper_schema_rejects_unknown_and_wrong_types(self):
        value = {'schemaVersion': 1, 'actionCode': 0,
                 'matchingActionAttempted': True, 'menuFound': True, 'menuEnabled': True,
                 'ownedWindowVerified': True, 'ownedFocusVerified': True,
                 'markKnown': True, 'enrolled': True, 'enrollmentActionAttempted': False,
                 'authenticationPromptObserved': False, 'hypothesis': 'picker_requires_biometric_response'}
        self.assertTrue(valid_matching_report(value))
        for invalid in ({**value, 'extra': 'untrusted'}, {**value, 'actionCode': True},
                        {**value, 'enrolled': 1}, {**value, 'authenticationPromptObserved': True},
                        {**value, 'enrollmentActionAttempted': True}):
            self.assertFalse(valid_matching_report(invalid))

    def test_old_tap_only_event_never_triggers(self):
        calls = []
        _, report = self.invoke(b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped\n', calls.append)
        self.assertEqual(calls, [])
        self.assertEqual(report['exactEventCount'], 0)
        self.assertTrue(report['foreignEventObserved'])

    def orchestrate(self, suffix):
        helper = {'schemaVersion': 1, 'actionCode': 0,
                  'matchingActionAttempted': True, 'menuFound': True, 'menuEnabled': True,
                  'ownedWindowVerified': True, 'ownedFocusVerified': True,
                  'markKnown': True, 'enrolled': True, 'enrollmentActionAttempted': False,
                  'authenticationPromptObserved': False, 'hypothesis': 'picker_requires_biometric_response'}
        import json
        calls = []
        observations = []
        class FakeDriver:
            def run(self, operation, argv, **kwargs):
                calls.append(operation)
                observations.append(self.report['matchingExperiment']['authenticationPromptObserved'])
                return subprocess.CompletedProcess(argv, 0, json.dumps(helper), '')
        driver = SimpleNamespace(
            _owned_menu_command=['synthetic-helper', 'owned-fixture', 'com.apple.iphonesimulator'],
            remaining=lambda: 10,
            report={'combinedCapabilityStatus': 'Passed', 'afterCanEvaluate': True,
                    'menu': {'enrolledAfter': True, 'ownedFocusVerified': True}, 'commands': []})
        base = SimpleNamespace(Driver=FakeDriver, Blocked=RuntimeError, TimedOut=TimeoutError)
        env = os.environ.copy()
        env.update(TEST_RUNNER_NIDAA_PICKER_MATCH_NONCE='a'*32,
                   TEST_RUNNER_NIDAA_PICKER_MATCH_OWNED_UDID='AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE')
        payload = ('NIDAA_PICKER_MATCH_REQUEST:'+'a'*32+':'+suffix+'\n').encode()
        argv = [sys.executable, '-c', 'import sys,time;sys.stdout.buffer.write('+repr(payload)+');sys.stdout.flush();time.sleep(0.25)']
        result = run_saved_with_response(driver, base, 'autofill_saved_selected_test', argv, 10,
                                         env, Path(__file__).parent,
                                         lambda *_: self.fail('Unexpected partial output'))
        self.assertEqual(result.returncode, 0)
        return driver.report, calls, observations

    def test_prompt_observation_stays_false_for_old_tap_event(self):
        report, calls, observations = self.orchestrate('passwords_picker_tapped')
        self.assertEqual(calls, [])
        self.assertEqual(observations, [])
        self.assertFalse(report['matchingExperiment']['authenticationPromptObserved'])
        self.assertEqual(report['matchingExperiment']['status'], 'Waiting-for-event')
        self.assertFalse(experiment_completed(report))

    def test_prompt_event_observation_is_distinct_from_helper_observation(self):
        report, calls, observations = self.orchestrate('face_id_prompt_observed')
        self.assertEqual(calls, ['reopen_system_events_before_matching', 'official_matching_face_single_attempt'])
        self.assertEqual(observations, [True, True])
        self.assertTrue(report['matchingExperiment']['authenticationPromptObserved'])
        self.assertFalse(report['matchingExperiment']['helper']['authenticationPromptObserved'])
        self.assertTrue(experiment_completed(report))
        report['matchingExperiment']['authenticationPromptObserved'] = False
        self.assertFalse(experiment_completed(report))


if __name__ == '__main__':
    unittest.main()
