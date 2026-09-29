"""Regression coverage for safely retaining failed XCTest evidence."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class NativeEvidenceExportTests(unittest.TestCase):
    def test_numeric_xcode_failure_id_preserves_failure_without_exporting_raw_text(self):
        private_root = ROOT / 'PrivateEvidence'
        private_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='native-review-export-test-', dir=private_root) as source_dir, tempfile.TemporaryDirectory() as destination:
            private = Path(source_dir)
            # Shape observed in actual xcresult output, including its numeric ID.
            (private / 'ui-summary.json').write_text(json.dumps({
                'result': 'Failed', 'totalTestCount': 1, 'passedTests': 0,
                'failedTests': 1, 'skippedTests': 0,
                'testFailures': [{'testIdentifier': 1,
                    'testIdentifierString': 'NidaaUITests-Runner (123) encountered an error',
                    'failureText': 'Early unexpected exit, operation never finished bootstrapping. Test crashed with signal kill before starting test execution. PRIVATE_SENTINEL_DO_NOT_EXPORT'}]
            }))
            exported = Path(destination) / 'export'
            screens = private / 'screenshots'
            screens.mkdir()
            valid = 'login_exists=true, login_enabled=true, signup_exists=true, signup_enabled=false, busy=false, native={nativeReady=false,hasText=true,firstResponder=true,asciiKeyboard=true,secure=true,receivedSeveralEdits=true,bindingReady=false}'
            (screens / 'safe.txt').write_text('before_keyboard_done: '+valid+'\nafter_keyboard_done: '+valid)
            (screens / 'unsafe.txt').write_text('before_keyboard_done: PRIVATE_SENTINEL_DO_NOT_EXPORT')
            (screens / 'manifest.json').write_text(json.dumps([{'attachments': [
                {'suggestedHumanReadableName':'integration-mock-draft-readiness','exportedFileName':name}
                for name in ['safe.txt','unsafe.txt']]}]))
            script = ROOT / 'Scripts/export_native_review.py'
            code = script.read_text().replace("output = root/'artifacts/native-review'/suite", 'output = Path(' + repr(str(exported)) + ')')
            class XcodeVersion:
                stdout = 'Xcode test fixture'
            with patch.object(sys, 'argv', [str(script), str(private.relative_to(ROOT)), 'autofill', '65']), patch('subprocess.run', return_value=XcodeVersion()), redirect_stdout(io.StringIO()):
                exec(compile(code, str(script), 'exec'), {'__file__': str(script)})
            raw = (exported / 'result.json').read_text()
            result = json.loads(raw)
            self.assertEqual(result['exitCode'], 65)
            self.assertEqual(result['summary']['passedTests'], 0)
            self.assertTrue(result['infrastructureSignals']['runnerBootstrapFailure'])
            self.assertTrue(result['infrastructureSignals']['runnerKilledBeforeTests'])
            self.assertEqual(len(result['failedTestIdentifiers']), 1)
            self.assertNotIn('PRIVATE_SENTINEL_DO_NOT_EXPORT', raw)
            self.assertNotIn('failureText', raw)
            self.assertFalse(result['debugTestSucceeded'])
            self.assertFalse(result['releaseBuildSucceeded'])
            self.assertEqual(len(result['draftReadiness']), 1)
            self.assertTrue(result['draftReadiness'][0][0]['native']['hasText'])
            self.assertFalse(result['draftReadiness'][0][0]['native']['nativeReady'])


if __name__ == '__main__':
    unittest.main()
