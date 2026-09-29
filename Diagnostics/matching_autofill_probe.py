#!/usr/bin/env python3
"""Run the original saved-password UI test on the verified enrolled fixture.

Imports the successful capability driver without invoking its CLI until the
single after-phase hook is installed. All raw saved-password evidence remains
private; only fixed result fields and a strictly validated early-entry tree
leave PrivateEvidence. Raw screenshots, logs and ciphertext are never exported. This separate experiment requests one official Matching Face response after a nonce-bound XCTest observation of a visible Face ID prompt and its after-tap capture. Menu success alone is not authentication proof.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import sys
import time
from uuid import uuid4


SAVED_SELECTOR = 'NidaaUITests/AutoFillUITests/testSavedCredentialSelection'
DESCRIPTION = 'Disposable diagnostic checks biometric availability without requesting authentication.'


def classify_failure_signatures(text):
    """Emit fixed booleans only; never export a matched message or substring."""
    patterns = {
        'matching_snapshot_failure': r'failed to (?:get|obtain|retrieve) matching snapshots?',
        'snapshot_failure': r'(?:failed|unable|could not) to (?:get|obtain|retrieve|capture|generate) (?:a |the )?snapshot',
        'query_timeout': r'timed? ?out.{0,120}(?:query|snapshot|accessibility)|(?:query|snapshot|accessibility).{0,120}timed? ?out',
        'multiple_matches': r'multiple (?:matching elements|matches found)|ambiguous match',
        'no_matching_elements': r'no matches found|no matching elements',
        'application_not_running': r'application.{0,80}(?:not running|not foreground)|failed to (?:launch|activate) (?:the )?app',
        'accessibility_connection_failure': r'(?:accessibility|\bAX(?:Error|UIElement|RemoteElement)?\b).{0,100}(?:connection|server|error)|(?:connection|server).{0,100}(?:accessibility|\bAX(?:Error|UIElement|RemoteElement)?\b)',
        'element_not_hittable': r'(?:element|control).{0,80}not hittable',
        'interrupted_query': r'(?:query|snapshot).{0,80}(?:cancelled|canceled|interrupted)',
        'test_process_terminated': r'test runner.{0,80}(?:exited|crashed|terminated)|lost connection to.{0,80}test',
    }
    return {key: re.search(pattern, text, re.IGNORECASE) is not None for key, pattern in patterns.items()}


def private_log(path, stdout, stderr):
    with path.open('wb') as stream:
        for data in (stdout, stderr):
            if data:
                stream.write(data.encode('utf-8') if isinstance(data, str) else data)
                stream.write(b'\n')


def export_fixed_evidence(driver, base, project, private, owned, result, counts, test_code):
    """Construct public fields explicitly; never copy logs or broad exports."""
    output = project/'artifacts/native-review/autofill-saved'
    if output.exists():
        result['safeExportStatus'] = 'Rejected-output-collision'
        return False
    output.mkdir(parents=True)
    logs = (private/'xcode-ui-tests.log').read_text(encoding='utf-8', errors='replace')
    release = (private/'xcode-release.log').read_text(encoding='utf-8', errors='replace')
    outcomes = re.findall(r"Test Case '-\[(?:NidaaUITests\.)?AutoFillUITests testSavedCredentialSelection\]' (passed|failed|skipped)", logs)
    outcome = outcomes[0] if len(outcomes) == 1 else 'Not executed' if not outcomes else 'Ambiguous'
    source_files = ('AutoFillUITests.swift', 'IntegrationTestSupport.swift', 'BiometryCapabilityUITests.swift', 'LocalExperienceUITests.swift')
    pattern = r'\b('+ '|'.join(re.escape(name) for name in source_files)+r'):([0-9]+):(?:[0-9]+:)?\s*error:'
    locations = sorted({(name, int(line)) for name, line in re.findall(pattern, logs)
                        if 0 < int(line) <= 100000})
    debug_succeeded = test_code == 0 and '** TEST SUCCEEDED **' in logs
    release_succeeded = result.get('releaseExitCode') == 0 and '** BUILD SUCCEEDED **' in release
    safe = {'schemaVersion': 1, 'suite': 'autofill-saved', 'testIdentifier': 'AutoFillUITests/testSavedCredentialSelection()',
            'testResult': outcome, 'exitCode': test_code,
            'summary': counts if counts is not None else {},
            'debugTestSucceeded': debug_succeeded, 'releaseBuildSucceeded': release_succeeded,
            'failureLocations': [{'fileName': name, 'line': line} for name, line in locations],
            'rawEvidenceUploaded': False, 'encryptedEvidenceUploaded': False, 'screenshotsUploaded': False,
            'sameOwnedEnrolledSimulator': True, 'matchingFaceInvoked': False,
            'earlyEntryTree': {'status': 'Unavailable', 'reason': 'validator-unavailable'}}
    result['debugTestSucceeded'] = debug_succeeded
    result['releaseBuildSucceeded'] = release_succeeded
    result['savedCredentialSelection'] = outcome
    validator_path = Path(__file__).with_name('early_passwords_entry_validator.py')
    if validator_path.is_file():
        try:
            spec = importlib.util.spec_from_file_location('nidaa_entry_validator', validator_path)
            validator = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(validator)
            safe['earlyEntryTree'] = validator.export_early_passwords_entry(
                private/'screenshots', output/'early-passwords-entry.json', owned_udid=owned)
            safe['selectionState'] = validator.export_selection_state(private/'screenshots', owned)
            safe['queryState'] = validator.export_query_state(private/'screenshots', owned)
            if hasattr(validator, 'export_picker_trees'):
                safe['pickerTrees'] = validator.export_picker_trees(private/'screenshots', output, owned_udid=owned)
        except (OSError, ValueError, TypeError, AttributeError):
            safe['earlyEntryTree'] = {'status': 'Rejected', 'reason': 'validator-error'}
    safe['matchingExperiment'] = driver.report.get('matchingExperiment', {})
    safe['matchingFaceInvoked'] = safe['matchingExperiment'].get('actionAttempted', False)
    result['matchingFaceInvoked'] = safe['matchingFaceInvoked']
    driver.report['matchingFaceInvoked'] = safe['matchingFaceInvoked']
    result['earlyEntryTreeStatus'] = safe['earlyEntryTree']['status']
    safe['failureCategory'] = base.failure_category(logs, '') if test_code else 'none'
    # Query exceptions can abort before the explicit selection-failure capture.
    # Classify private output without exporting its message or credential-bearing
    # XCUI query. This is diagnostic-only and does not change/retry the UI action.
    error_lines = [line for line in logs.splitlines() if re.search(r'\berror:|Testing failed:|Test Failure', line, re.IGNORECASE)]
    safe['failureSignatures'] = classify_failure_signatures('\n'.join(error_lines)) if test_code else {}
    safe['classifiedErrorLineCount'] = len(error_lines)
    safe['failureSignatureLimit'] = 'Fixed substring signatures on error lines only; no message or query text exported. An unmatched signature does not prove an error absent.'
    (output/'result.json').write_text(json.dumps(safe, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    result['safeExportStatus'] = 'Fixed-fields-written'
    return (debug_succeeded and release_succeeded and outcome == 'passed'
            and safe['earlyEntryTree']['status'] == 'Exported'
            and safe.get('selectionState', {}).get('status') == 'Exported'
            and safe.get('queryState', {}).get('status') == 'Exported'
            and all(safe.get('pickerTrees', {}).get(phase) is True for phase in ('before_selection', 'after_fill_wait'))
            and safe.get('pickerTrees', {}).get('status') != 'Rejected')


def run_saved_selection(driver, base, owned, project, temporary):
    report = driver.report
    result = report['savedCredentialDiagnostic'] = {'status': 'Running', 'testSelector': SAVED_SELECTOR,
                                                  'sameOwnedEnrolledSimulator': True, 'matchingFaceInvoked': False,
                                                  'rawEvidencePublic': False, 'releaseStatus': 'Notexecuted'}
    result['rawEvidenceLocation'] = 'Owned private runner directory; never uploaded in any form'
    report['fictionalCredentialFixtureAttempted'] = True
    private = project/'PrivateEvidence'/('native-review-autofill-saved-'+uuid4().hex)
    private.mkdir(parents=True, mode=0o700)
    relative_private = private.relative_to(project).as_posix()
    environment = os.environ.copy()
    for key in list(environment):
        if key.startswith('NIDAA_') or key.startswith('TEST_RUNNER_NIDAA_'):
            environment.pop(key)
    environment.update(NIDAA_UI_SUITE='autofill-saved',
                       NIDAA_SIMULATOR_EVIDENCE_DIR=relative_private)
    environment['TEST_RUNNER_NIDAA_PICKER_MATCH_NONCE'] = uuid4().hex
    environment['TEST_RUNNER_NIDAA_PICKER_MATCH_OWNED_UDID'] = owned
    common = ['xcodebuild', '-project', str(project/'NidaaProof.xcodeproj'), '-scheme', 'NidaaProof-Local',
              '-sdk', 'iphonesimulator', '-destination', 'platform=iOS Simulator,id='+owned,
              '-derivedDataPath', str(temporary/'DerivedData'), 'ARCHS='+platform.machine(),
              'ONLY_ACTIVE_ARCH=YES', 'NIDAA_BUNDLE_ID=com.example.nidaa.simulatorproof', 'DEVELOPMENT_TEAM=',
              'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'CODE_SIGN_ENTITLEMENTS=',
              'INFOPLIST_KEY_NSFaceIDUsageDescription='+DESCRIPTION]
    debug_log = private/'xcode-ui-tests.log'
    release_log = private/'xcode-release.log'
    debug_log.touch()
    release_log.touch()
    (private/'ui-selection.txt').write_text('UI suite: autofill-saved\n-only-testing:'+SAVED_SELECTOR+'\n', encoding='utf-8')
    test_code = 125
    try:
        tested = driver.run('autofill_saved_selected_test', common+['-configuration', 'Debug', '-parallel-testing-enabled', 'NO',
                            '-only-testing:'+SAVED_SELECTOR, '-resultBundlePath', str(private/'LocalExperience.xcresult'), 'test'],
                            maximum=720, env=environment, cwd=project,
                            partial=lambda stdout, stderr: private_log(debug_log, stdout, stderr))
        test_code = tested.returncode
        private_log(debug_log, tested.stdout, tested.stderr)
        if test_code:
            result['failureCategory'] = base.failure_category(tested.stdout, tested.stderr)
    except base.TimedOut:
        test_code = 124
        result['failureCategory'] = 'bounded_saved_test_timeout'
    except base.Blocked:
        result['failureCategory'] = 'saved_test_budget_or_tool_unavailable'
    result['testExitCode'] = test_code
    result['systemLogsCollected'] = False
    result['rawEvidencePolicy'] = 'Runner-private only; never exported or uploaded, including encrypted archives.'
    bundle = private/'LocalExperience.xcresult'
    counts = None
    if bundle.is_dir():
        try:
            attachments = driver.run('export_private_saved_test_attachments',
                                     ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                                      '--output-path', str(private/'screenshots')], maximum=60)
            result['attachmentExportExitCode'] = attachments.returncode
            summary = driver.run('read_private_saved_test_summary',
                                 ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], maximum=30)
            if summary.returncode == 0:
                (private/'ui-summary.json').write_text(summary.stdout, encoding='utf-8')
                value = json.loads(summary.stdout)
                counts = {key: value[key] for key in ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')}
                if any(type(value) is not int or value < 0 for value in counts.values()):
                    counts = None
                else:
                    result['testSummary'] = counts
        except (base.TimedOut, base.Blocked, ValueError, TypeError, KeyError):
            result['summaryStatus'] = 'Incomplete'
    try:
        released = driver.run('autofill_independent_release_build', common+['-configuration', 'Release', 'build'],
                              maximum=360, env=environment, cwd=project,
                              partial=lambda stdout, stderr: private_log(release_log, stdout, stderr))
        private_log(release_log, released.stdout, released.stderr)
        result['releaseExitCode'] = released.returncode
        result['releaseStatus'] = 'Passed' if released.returncode == 0 else 'Failed'
    except (base.TimedOut, base.Blocked):
        result['releaseStatus'] = 'Incomplete'
    safe_exported = export_fixed_evidence(driver, base, project, private, owned, result, counts, test_code)
    passed = (test_code == 0 and counts == {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}
              and result['releaseStatus'] == 'Passed' and safe_exported
              and driver.matching_experiment_completed())
    result['status'] = 'Passed' if passed else 'Failed'
    result['matchingExperimentCompleted'] = driver.matching_experiment_completed()
    result['acceptanceGate'] = 'One nonce-bound official Matching Face action after XCTest observes a visible Face ID prompt. Authentication is not inferred from the menu action alone. Original saved-credential selector: exactly one passed test and no skips/failures; Release build passed; fixed-field result and strictly validated early-entry tree exported. No raw or encrypted credential evidence exported.'
    report['autoFillValidated'] = passed
    if not passed:
        raise base.Blocked('enrolled_saved_credential_diagnostic_failed')


def main():
    # The parent driver continues to own its exact-device cleanup and original
    # before/after capability gates. This wrapper never creates another device.
    module_path = Path(__file__).with_name('xctest_biometry_probe.py')
    if not module_path.is_file():
        module_path = Path(__file__).with_name('xctest-biometry-probe.py')
    spec = importlib.util.spec_from_file_location('nidaa_capability_driver', module_path)
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    match_spec = importlib.util.spec_from_file_location('nidaa_controlled_matching', Path(__file__).with_name('controlled_matching_run.py'))
    matching = importlib.util.module_from_spec(match_spec)
    match_spec.loader.exec_module(matching)
    class EnrolledDriver(base.Driver):
        def run(self, operation, argv, maximum=30, env=None, cwd=None, partial=None):
            if operation in {'compile_public_AX_helper', 'owned_bootstatus', 'xctest_before', 'official_menu_single_enrollment_attempt', 'xctest_after', 'autofill_saved_selected_test', 'official_matching_face_single_attempt', 'autofill_independent_release_build', 'cleanup_shutdown', 'cleanup_delete'}:
                print('NIDAA diagnostic stage: ' + operation, flush=True)
            if operation == 'official_menu_single_enrollment_attempt':
                self._owned_menu_command = list(argv)
            if operation == 'autofill_saved_selected_test':
                return matching.run_saved_with_response(self, base, operation, argv, maximum, env, cwd, partial)
            return super().run(operation, argv, maximum=maximum, env=env, cwd=cwd, partial=partial)
        def matching_experiment_completed(self):
            return matching.experiment_completed(self.report)

        def __init__(self, report):
            super().__init__(report)
            self.deadline = time.monotonic()+1800
            report.update(executionBudgetSeconds=1800, scope='Controlled one-shot official Matching Face response after observed visible Face ID prompt on verified enrolled owned Simulator',
                          orchestrationSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), realAccountsCreated=False,
                          fictionalCredentialFixtureAttempted=False)
            report.pop('appCredentialsCreated', None)
            # The availability observer requests no authentication. The actual
            # Passwords journey may present system authentication; do not apply
            # the observer's no-prompt claim to that separate UI journey.
            report.pop('authenticationPromptRequested', None)
            report['biometryObserverAuthenticationPromptRequested'] = False
            report['savedJourneySystemAuthentication'] = 'Inspect strictly sanitized UI trees; raw evidence remains runner-private'
    original_phase = base.run_phase
    def extended_phase(driver, helper, phase, owned, project, temporary):
        value = original_phase(driver, helper, phase, owned, project, temporary)
        if phase == 'after' and value['canEvaluate'] is True:
            menu = driver.report.get('menu', {})
            if (menu.get('queryStage') == 'complete' and menu.get('ownedWindowVerified') is True
                    and menu.get('matchingFaceInvoked') is False
                    and driver.report['observations']['before']['status'] == 'Observed'):
                driver.report['combinedCapabilityStatus'] = 'Passed'
                driver.report['beforeCanEvaluate'] = driver.report['observations']['before']['result']['canEvaluate']
                driver.report['afterCanEvaluate'] = True
                run_saved_selection(driver, base, owned, project, temporary)
        return value
    # Match the existing AutoFill fixture's disposable-name guard without
    # relaxing it. This exact name is created, focused and deleted by the driver.
    base.OWNED_DEVICE_PREFIX = 'NIDAA-Disposable-Biometry-'
    base.Driver = EnrolledDriver
    base.run_phase = extended_phase
    if '--helper-path' not in sys.argv:
        helper_path = Path(__file__).with_name('biometry_matching_helper.py')
        if not helper_path.is_file():
            helper_path = Path(__file__).with_name('biometry-matching-helper.py')
        sys.argv.extend(['--helper-path', str(helper_path)])
    if '--output' not in sys.argv:
        sys.argv.extend(['--output', 'artifacts/enrolled-autofill/report.json'])
    return base.main()


if __name__ == '__main__':
    raise SystemExit(main())
