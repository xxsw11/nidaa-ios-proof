"""One official Simulator response after one validated post-Passwords-tap event.

This is a controlled hypothesis test, not evidence of an observed native prompt.
All subprocess text stays private. Exported dictionaries have fixed keys/values.
"""
import importlib.util
import json
from pathlib import Path
import re
import time


def valid_matching_report(value):
    flags = {'matchingActionAttempted', 'menuFound', 'menuEnabled', 'ownedWindowVerified',
             'ownedFocusVerified', 'markKnown', 'enrolled', 'enrollmentActionAttempted',
             'authenticationPromptObserved'}
    return (isinstance(value, dict) and set(value) == flags | {'schemaVersion', 'actionCode', 'hypothesis'}
            and type(value['schemaVersion']) is int and value['schemaVersion'] == 1
            and all(type(value[key]) is bool for key in flags)
            and (value['actionCode'] is None or type(value['actionCode']) is int)
            and value['enrollmentActionAttempted'] is False
            and value['authenticationPromptObserved'] is False
            and value['hypothesis'] == 'picker_requires_biometric_response')


def run_saved_with_response(driver, base, operation, argv, maximum, env, cwd, partial):
    module_path = Path(__file__).with_name('matching_face_stream.py')
    spec = importlib.util.spec_from_file_location('nidaa_private_event_stream', module_path)
    stream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stream)
    nonce = env.get('TEST_RUNNER_NIDAA_PICKER_MATCH_NONCE', '')
    owned = env.get('TEST_RUNNER_NIDAA_PICKER_MATCH_OWNED_UDID', '')
    if not re.fullmatch('[0-9a-f]{32}', nonce) or not re.fullmatch('[0-9A-F-]{36}', owned):
        raise base.Blocked('matching_fixture_environment_invalid')
    command = getattr(driver, '_owned_menu_command', None)
    if not isinstance(command, list) or len(command) != 3:
        raise base.Blocked('matching_owned_menu_context_missing')
    report = driver.report
    if (report.get('combinedCapabilityStatus') != 'Passed' or report.get('afterCanEvaluate') is not True
            or report.get('menu', {}).get('enrolledAfter') is not True
            or report.get('menu', {}).get('ownedFocusVerified') is not True):
        raise base.Blocked('matching_enrollment_precondition_unproven')
    experiment = report['matchingExperiment'] = {
        'hypothesis': 'picker_requires_biometric_response', 'authenticationPromptObserved': False,
        'trigger': 'exact_nonce_event_after_completed_native_passwords_tap',
        'maximumMatchingActions': 1, 'status': 'Waiting-for-event', 'actionAttempted': False,
        'actionOutcomeUncertain': False, 'originalAssertionsRetained': True,
        'rawEvidenceUploaded': False}
    timeout = min(maximum, driver.remaining())
    record = {'operation': operation, 'maximumSeconds': maximum,
              'effectiveTimeoutSeconds': round(timeout, 3)}
    report['commands'].append(record)
    report['stage'] = operation
    started = time.monotonic()
    def respond(remaining):
        experiment['status'] = 'Event-validated'
        experiment['nonceMatched'] = True
        if remaining <= 5:
            experiment['status'] = 'Notexecuted-budget'
            return
        try:
            reopened = base.Driver.run(driver, 'reopen_system_events_before_matching',
                                       ['open', '-g', '-b', 'com.apple.systemevents'],
                                       maximum=min(5, remaining))
            if reopened.returncode:
                experiment['status'] = 'System-events-unavailable'
                return
            # The helper freshly verifies this exact owned window/focus and
            # checked enrollment before its one non-idempotent Matching action.
            experiment['status'] = 'Matching-helper-started'
            experiment['actionAttempted'] = None
            experiment['actionOutcomeUncertain'] = True
            remaining = timeout - (time.monotonic() - started)
            response = base.Driver.run(driver, 'official_matching_face_single_attempt',
                                      command + ['--matching-face-only'], maximum=min(60, max(0, remaining)))
            value = json.loads(response.stdout)
            if not valid_matching_report(value):
                experiment['status'] = 'Rejected-helper-schema'
                return
            experiment['helper'] = value
            experiment['helperExitCode'] = response.returncode
            experiment['actionAttempted'] = value['matchingActionAttempted']
            experiment['actionOutcomeUncertain'] = value['matchingActionAttempted'] and value['actionCode'] != 0
            successful = (response.returncode == 0 and value['actionCode'] == 0
                          and all(value[key] for key in ('matchingActionAttempted', 'menuFound', 'menuEnabled',
                                                        'ownedWindowVerified', 'ownedFocusVerified', 'markKnown', 'enrolled')))
            experiment['status'] = 'Official-action-returned-success' if successful else 'Matching-action-unproven'
            # A returned AX success is not proof of an authenticated picker.
            experiment['authenticationSucceeded'] = 'Not inferred from menu result'
        except (base.Blocked, base.TimedOut, OSError, ValueError, TypeError):
            experiment['status'] = 'Matching-command-or-schema-incomplete'
            # The one-shot transport never retries this callback.
    try:
        result, transport = stream.run_with_one_event(
            argv, env=env, cwd=cwd, timeout=timeout,
            expected_line=('NIDAA_PICKER_MATCH_REQUEST:'+nonce+':passwords_picker_tapped').encode('ascii'),
            on_event=respond, partial=partial)
        experiment['transport'] = transport
        record.update(status='Completed', exitCode=result.returncode)
        return result
    except stream.StreamFailure as error:
        record['status'] = 'Failed-private-stream'
        record['failureCategory'] = error.category
        if error.category == 'bounded_saved_test_timeout':
            raise base.TimedOut(operation) from None
        raise base.Blocked('matching_private_stream_failed') from None
    except OSError:
        record['status'] = 'Tool-error'
        raise base.Blocked('matching_test_process_unavailable') from None
    finally:
        record['elapsedSeconds'] = round(time.monotonic() - started, 3)


def experiment_completed(report):
    value = report.get('matchingExperiment', {})
    transport = value.get('transport', {})
    return (value.get('status') == 'Official-action-returned-success'
            and transport.get('exactEventCount') == 1
            and transport.get('foreignEventObserved') is False
            and transport.get('lateEventObserved') is False
            and transport.get('callbackFailed') is False)
