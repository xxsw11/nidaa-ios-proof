import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import subprocess
from controlled_matching_run import valid_matching_report, experiment_completed
from matching_face_stream import run_with_one_event


class MatchingTransportTests(unittest.TestCase):
    def invoke(self, payload, callback):
        marker = b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped'
        result, report = run_with_one_event(
            [sys.executable, '-c', 'import sys,time;sys.stdout.buffer.write('+repr(payload)+');sys.stdout.flush();time.sleep(0.25)'],
            env=os.environ.copy(), cwd=Path(__file__).parent, timeout=10,
            expected_line=marker, on_event=callback,
            partial=lambda *_: self.fail('Unexpected partial output'))
        self.assertEqual(result.returncode, 0)
        return result, report

    def test_exact_event_once_preserves_private_output(self):
        calls = []
        payload = b'PRIVATE-FIXTURE-NOT-EXPORTED\nNIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped\n'
        result, report = self.invoke(payload, calls.append)
        self.assertEqual(len(calls), 1)
        self.assertEqual(report['exactEventCount'], 1)
        self.assertFalse(report['callbackFailed'])
        self.assertNotIn('PRIVATE-FIXTURE', repr(report))
        self.assertIn('PRIVATE-FIXTURE', result.stdout)

    def test_duplicate_does_not_repeat_action(self):
        calls = []
        payload = (b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped\n')*2
        _, report = self.invoke(payload, calls.append)
        self.assertEqual(len(calls), 1)
        self.assertEqual(report['exactEventCount'], 2)
        self.assertFalse(experiment_completed({'matchingExperiment': {
            'status': 'Official-action-returned-success', 'transport': report}}))

    def test_foreign_nonce_and_unterminated_line_do_not_trigger(self):
        calls = []
        payload = b'NIDAA_PICKER_MATCH_REQUEST:'+b'b'*32+b':passwords_picker_tapped\n'
        payload += b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped'
        _, report = self.invoke(payload, calls.append)
        self.assertEqual(calls, [])
        self.assertEqual(report['exactEventCount'], 0)
        self.assertTrue(report['foreignEventObserved'])

    def test_uncertain_callback_never_retried(self):
        calls = []
        def fail_once(_):
            calls.append(True)
            raise ValueError('Private error must not be exported')
        _, report = self.invoke((b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped\n')*2, fail_once)
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
            _, report = self.invoke(b'NIDAA_PICKER_MATCH_REQUEST:'+b'a'*32+b':passwords_picker_tapped\n', calls.append)
        self.assertEqual(calls, [])
        self.assertTrue(report['lateEventObserved'])
        self.assertFalse(experiment_completed({'matchingExperiment': {
            'status': 'Official-action-returned-success', 'transport': report}}))

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


if __name__ == '__main__':
    unittest.main()
