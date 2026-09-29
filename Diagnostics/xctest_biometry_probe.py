#!/usr/bin/env python3
"""Disposable Simulator biometry observation through the existing UI runner.

Only one explicitly selected XCTest runs per phase. No custom application is
installed by this driver, no authentication prompt or Matching Face is invoked,
and raw Xcode output/result bundles are never published as diagnostic evidence.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import tempfile
import time
from uuid import UUID, uuid4


SELECTOR = 'NidaaUITests/BiometryCapabilityUITests/testObserveBiometry'
PREFIX = b'NIDAA_BIOMETRY_OBSERVATION:'


class Blocked(Exception):
    pass


class TimedOut(Exception):
    def __init__(self, operation):
        self.operation = operation


class Driver:
    def __init__(self, report):
        self.report = report
        self.deadline = time.monotonic()+1200

    def remaining(self):
        return max(0, self.deadline-time.monotonic())

    def run(self, operation, argv, maximum=30, env=None, cwd=None, partial=None):
        self.report['stage'] = operation
        timeout = min(maximum, self.remaining())
        record = {'operation': operation, 'maximumSeconds': maximum, 'effectiveTimeoutSeconds': round(timeout, 3)}
        self.report['commands'].append(record)
        if timeout <= 0:
            record['status'] = 'Notexecuted-budget'
            raise Blocked('execution_budget_exhausted')
        started = time.monotonic()
        try:
            result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env, cwd=cwd)
            record['exitCode'] = result.returncode
            record['status'] = 'Completed'
            return result
        except subprocess.TimeoutExpired as error:
            record['status'] = 'Timed-out'
            if partial is not None:
                partial(error.stdout, error.stderr)
            raise TimedOut(operation) from None
        except OSError as error:
            record['status'] = 'Tool-error'
            record['errorNumber'] = error.errno
            raise Blocked('command_tool_error') from None
        finally:
            record['elapsedSeconds'] = round(time.monotonic()-started, 3)


def observation_stream(stdout, stderr):
    # Build output may be large. Keep only exact complete owned-test record
    # lines before calling the existing bounded schema/nonce validator.
    records = []
    for output in (stdout, stderr):
        if output is None:
            continue
        raw = output.encode('utf-8') if isinstance(output, str) else output
        for line in raw.splitlines(keepends=True):
            if line.startswith(PREFIX) and line.endswith(b'\n'):
                if len(line) > 2100:
                    return b''
                records.append(line)
                if len(records) > 1:
                    return b''
    return b''.join(records)


def has_observation_prefix(stdout, stderr):
    for output in (stdout, stderr):
        if output is not None:
            raw = output.encode('utf-8') if isinstance(output, str) else output
            if any(line.startswith(PREFIX) for line in raw.splitlines()):
                return True
    return False


def failure_category(stdout, stderr):
    # Fixed classifications only. Never copy file paths, identifiers, assertion
    # text, source excerpts, or arbitrary compiler output into the report.
    text = ((stdout or '')+'\n'+(stderr or '')).lower()
    if 'could not resolve package dependencies' in text or 'failed to clone repository' in text:
        return 'package_resolution'
    if 'unable to find a destination' in text or 'ineligible destinations' in text:
        return 'destination_unavailable'
    if 'link command failed' in text or 'undefined symbols for architecture' in text:
        return 'linker_failure'
    if re.search(r':\d+:\d+:\s*error:', text) or 'emit-module command failed' in text:
        return 'source_compilation'
    if 'requires a development team' in text or ('code signing' in text and 'error:' in text):
        return 'signing_configuration'
    if 'failed to install' in text or 'could not install' in text:
        return 'test_runner_installation'
    if 'failed to launch' in text or 'could not launch' in text or 'failed to establish a connection' in text:
        return 'test_runner_launch_or_connection'
    if 'biometry diagnostic runner is missing its face id usage description' in text:
        return 'test_runner_usage_description_missing'
    if any(message in text for message in ('missing or invalid biometry diagnostic',
                                          'biometry diagnostic does not match the owned simulator',
                                          'biometry diagnostic record could not be serialized',
                                          'biometry diagnostic record could not be encoded',
                                          'biometry diagnostic requires the owned disposable simulator')):
        return 'diagnostic_test_guard_or_serialization'
    if 'test case' in text and (' failed (' in text or "' failed" in text):
        return 'selected_test_failure'
    if 'testing failed:' in text or '** test failed **' in text:
        return 'test_command_failure'
    return 'unclassified_xcodebuild_failure'


def attachment_observation(driver, helper, phase, nonce, owned, temporary, entry):
    status = entry['attachmentFallback'] = {'status': 'Notexecuted'}
    bundle = temporary/(phase+'.xcresult')
    if not bundle.is_dir():
        status['status'] = 'Result-bundle-unavailable'
        return None, 'Attachment-bundle-unavailable'
    if driver.remaining() < 30:
        status['status'] = 'Notexecuted-budget'
        return None, 'Attachment-budget-unavailable'
    directory = temporary/(phase+'-attachments')
    try:
        exported = driver.run('export_'+phase+'_exact_observation_attachment',
                              ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                               '--output-path', str(directory)], maximum=30)
    except (TimedOut, Blocked):
        status['status'] = 'Export-incomplete'
        return None, 'Attachment-export-incomplete'
    status['exportExitCode'] = exported.returncode
    if exported.returncode:
        status['status'] = 'Export-failed'
        return None, 'Attachment-export-failed'
    manifest = directory/'manifest.json'
    if not manifest.is_file() or manifest.stat().st_size > 1024*1024:
        status['status'] = 'Manifest-unavailable-or-oversized'
        return None, 'Attachment-manifest-invalid'
    try:
        tests = json.loads(manifest.read_text(encoding='utf-8'))
        if not isinstance(tests, list) or len(tests) > 20:
            raise ValueError('shape')
        expected_name = 'nidaa-biometry-observation-'+phase
        name_pattern = re.compile(re.escape(expected_name)+r'(?:_0_[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})?\.(?:txt|text)')
        matches = []
        for test in tests:
            if not isinstance(test, dict) or test.get('testIdentifier') != 'BiometryCapabilityUITests/testObserveBiometry()':
                continue
            attachments = test.get('attachments', [])
            if not isinstance(attachments, list) or len(attachments) > 100:
                raise ValueError('shape')
            for item in attachments:
                if not isinstance(item, dict):
                    continue
                human = item.get('suggestedHumanReadableName')
                if not isinstance(human, str) or not name_pattern.fullmatch(human):
                    continue
                if not isinstance(item.get('deviceId'), str) or item['deviceId'].upper() != owned.upper():
                    raise ValueError('owned device mismatch')
                filename = item.get('exportedFileName')
                if not isinstance(filename, str) or not filename or Path(filename).name != filename or '/' in filename or '\\' in filename:
                    raise ValueError('path')
                target = (directory/filename).resolve()
                if not target.is_relative_to(directory.resolve()) or not target.is_file() or target.stat().st_size > 2100:
                    raise ValueError('file')
                matches.append(target)
        if len(matches) != 1:
            raise ValueError('one exact attachment required')
        # UI test attaches the identical complete prefixed console record. The
        # fresh phase nonce is inside the schema, never inferred from its name.
        value, reason = helper.parse_observation(matches[0].read_bytes(), phase, nonce)
        status['status'] = 'Validated' if value is not None else 'Schema-or-freshness-failed'
        return value, reason
    except (OSError, ValueError, TypeError, KeyError):
        status['status'] = 'Manifest-or-exact-attachment-invalid'
        return None, 'Attachment-validation-failed'


def verify_one_test_summary(driver, phase, temporary, entry):
    summary = entry['testSummary'] = {'status': 'Notexecuted'}
    bundle = temporary/(phase+'.xcresult')
    if not bundle.is_dir():
        summary['status'] = 'Result-bundle-unavailable'
        return False
    if driver.remaining() < 20:
        summary['status'] = 'Notexecuted-budget'
        return False
    try:
        queried = driver.run('verify_'+phase+'_one_test_summary',
                             ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], maximum=20)
    except (TimedOut, Blocked):
        summary['status'] = 'Query-incomplete'
        return False
    summary['queryExitCode'] = queried.returncode
    if queried.returncode or len(queried.stdout) > 1024*1024:
        summary['status'] = 'Query-failed-or-oversized'
        return False
    try:
        value = json.loads(queried.stdout)
        counts = {key: value[key] for key in ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')}
        if any(type(count) is not int or count < 0 for count in counts.values()):
            raise ValueError('counts')
    except (ValueError, TypeError, KeyError):
        summary['status'] = 'Invalid-summary'
        return False
    summary.update(counts)
    valid = counts == {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}
    summary['status'] = 'Validated' if valid else 'Not-exactly-one-passed-test'
    return valid


def run_phase(driver, helper, phase, owned, project, temporary):
    entry = driver.report['observations'][phase] = {'status': 'Notexecuted-budget'}
    if driver.remaining() < 120:
        raise Blocked('observer_phase_budget_unavailable')
    nonce = uuid4().hex
    environment = os.environ.copy()
    # Prevent inherited trial/credential switches from steering the selected
    # isolated XCTest. The test itself never launches the product application.
    for key in list(environment):
        if key.startswith('NIDAA_') or key.startswith('TEST_RUNNER_NIDAA_'):
            environment.pop(key)
    environment.update(TEST_RUNNER_NIDAA_BIOMETRY_PHASE=phase,
                       TEST_RUNNER_NIDAA_BIOMETRY_NONCE=nonce,
                       TEST_RUNNER_NIDAA_BIOMETRY_OWNED_UDID=owned)
    argv = ['xcodebuild', '-project', str(project/'NidaaProof.xcodeproj'), '-scheme', 'NidaaProof-Local',
            '-sdk', 'iphonesimulator', '-destination', 'platform=iOS Simulator,id='+owned,
            '-derivedDataPath', str(temporary/'DerivedData'), 'ARCHS='+platform.machine(), 'ONLY_ACTIVE_ARCH=YES',
            'NIDAA_BUNDLE_ID=com.example.nidaa.simulatorproof', 'DEVELOPMENT_TEAM=', 'CODE_SIGNING_ALLOWED=NO',
            'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'CODE_SIGN_ENTITLEMENTS=',
            'INFOPLIST_KEY_NSFaceIDUsageDescription=Disposable diagnostic checks biometric availability without requesting authentication.',
            '-configuration', 'Debug', '-parallel-testing-enabled', 'NO', '-only-testing:'+SELECTOR,
            '-resultBundlePath', str(temporary/(phase+'.xcresult')), 'test']
    entry['status'] = 'Running'
    def recover_partial(stdout, stderr):
        value, reason = helper.parse_observation(observation_stream(stdout, stderr), phase, nonce)
        entry['timeoutObservationParseStatus'] = reason or 'Validated'
        if value is not None:
            entry['partialObservation'] = value
            entry['observationRecoveredFromTimedOutCommand'] = True
            entry['nonceMatched'] = True
    try:
        tested = driver.run('xctest_'+phase, argv, maximum=600 if phase == 'before' else 360,
                            env=environment, cwd=project, partial=recover_partial)
    except TimedOut:
        entry['status'] = 'Failed-timeout'
        entry['failureCategory'] = 'bounded_xcodebuild_timeout'
        raise
    entry['testExitCode'] = tested.returncode
    value, reason = helper.parse_observation(observation_stream(tested.stdout, tested.stderr), phase, nonce)
    if value is None and not has_observation_prefix(tested.stdout, tested.stderr):
        value, reason = attachment_observation(driver, helper, phase, nonce, owned, temporary, entry)
        if value is not None:
            entry['observationSource'] = 'Exact-owned-XCTest-attachment'
    elif value is not None:
        entry['observationSource'] = 'Validated-console-record'
    entry['recordParseStatus'] = reason or 'Validated'
    if value is not None:
        entry['result'] = value
        entry['nonceMatched'] = True
    if tested.returncode:
        entry['status'] = 'Failed-test-command'
        entry['failureCategory'] = failure_category(tested.stdout, tested.stderr)
        raise Blocked('selected_xctest_failed')
    if not verify_one_test_summary(driver, phase, temporary, entry):
        entry['status'] = 'Failed-test-summary'
        entry['failureCategory'] = 'selected_test_count_or_summary_unproven'
        raise Blocked('selected_xctest_summary_incomplete')
    if value is None:
        entry['status'] = 'Failed-observation-validation'
        raise Blocked('fresh_observer_record_unavailable')
    entry['status'] = 'Observed'
    return value


def cleanup(driver, owned):
    driver.deadline = time.monotonic()+90
    errors = []
    for operation, maximum in [('shutdown', 30), ('delete', 60)]:
        try:
            result = driver.run('cleanup_'+operation, ['xcrun', 'simctl', operation, owned], maximum=maximum)
            driver.report['cleanup'][operation] = {'exitCode': result.returncode}
            if operation == 'delete':
                driver.report['ownedDeviceDeleted'] = result.returncode == 0
            if result.returncode:
                errors.append(operation+'_failed')
        except (TimedOut, Blocked):
            driver.report['cleanup'][operation] = {'status': 'Failed'}
            errors.append(operation+'_incomplete')
    if errors:
        driver.report['cleanupErrors'] = errors
        driver.report['status'] = 'Blocked'
        driver.report.setdefault('blocker', 'owned_device_cleanup_incomplete')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project-root', type=Path, default=Path.cwd())
    parser.add_argument('--helper-path', type=Path, default=Path(__file__).with_name('biometry_probe.py'))
    parser.add_argument('--output', type=Path, default=Path('artifacts/xctest-biometry/report.json'))
    args = parser.parse_args()
    report = {'schemaVersion': 1, 'status': 'Blocked', 'scope': 'XCTest-runner biometric capability only',
              'executionBudgetSeconds': 1200, 'cleanupBudgetSeconds': 90, 'commands': [], 'cleanup': {},
              'observations': {'before': {'status': 'Notexecuted'}, 'after': {'status': 'Notexecuted'}},
              'menuOnlyStatus': 'Notexecuted', 'combinedCapabilityStatus': 'Notexecuted',
              'autoFillValidated': False, 'physicalBiometryProven': False, 'authenticationPromptRequested': False,
              'matchingFaceInvoked': False, 'appCredentialsCreated': False, 'privateAPIsUsed': False,
              'TCCChanged': False, 'customObserverAppInstalled': False,
              'ownedDeviceCreated': False, 'ownedDeviceDeleted': False, 'testSelector': SELECTOR,
              'probeSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    driver = Driver(report)
    owned = None
    temporary_manager = None
    primary_stage = None
    try:
        if platform.system() != 'Darwin':
            raise Blocked('macOS_required')
        project = args.project_root.resolve()
        if not (project/'NidaaProof.xcodeproj').is_dir():
            raise Blocked('existing_project_unavailable')
        helper_path = args.helper_path.resolve()
        if not helper_path.is_file():
            raise Blocked('existing_public_AX_helper_unavailable')
        report['hostHelperSHA256'] = hashlib.sha256(helper_path.read_bytes()).hexdigest()
        spec = importlib.util.spec_from_file_location('nidaa_biometry_helper', helper_path)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        temporary_manager = tempfile.TemporaryDirectory(prefix='nidaa-xctest-biometry-')
        temporary = Path(temporary_manager.name)
        source = temporary/'Capability.swift'
        binary = temporary/'capability'
        source.write_text(helper.SWIFT, encoding='utf-8')
        compiled = driver.run('compile_public_AX_helper', ['xcrun', 'swiftc', str(source), '-o', str(binary)], maximum=90)
        report['hostHelperCompileExitCode'] = compiled.returncode
        if compiled.returncode:
            report['hostHelperCompileErrors'] = helper.compiler_errors(compiled.stderr)
            raise Blocked('host_helper_compile_failed')
        launched = driver.run('launch_system_events', ['open', '-g', '-b', 'com.apple.systemevents'], maximum=10)
        if launched.returncode:
            raise Blocked('system_events_launch_failed')
        permission = driver.run('no_prompt_permission_check', [str(binary)], maximum=30)
        report['permissions'] = json.loads(permission.stdout)
        if permission.returncode:
            raise Blocked('public_GUI_permission_check_failed')
        inventory = driver.run('simulator_inventory', ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], maximum=120)
        if inventory.returncode:
            raise Blocked('simulator_inventory_unavailable')
        devices = [(runtime, item) for runtime, items in json.loads(inventory.stdout)['devices'].items()
                   if 'iOS' in runtime for item in items if item.get('isAvailable') and 'iPhone' in item['name']]
        if not devices:
            raise Blocked('iPhone_template_unavailable')
        def priority(item):
            name = item[1]['name']
            return (0 if name in ('iPhone 16 Pro', 'iPhone 17 Pro', 'iPhone 15 Pro') else 1,
                    'Max' in name, 'SE' in name, name)
        runtime, template = sorted(devices, key=priority)[0]
        name = 'NIDAA Biometry Probe '+uuid4().hex
        created = driver.run('create_owned_simulator', ['xcrun', 'simctl', 'create', name, template['deviceTypeIdentifier'], runtime])
        if created.returncode:
            raise Blocked('owned_simulator_creation_failed')
        owned = str(UUID(created.stdout.strip())).upper()
        report['ownedDeviceCreated'] = True
        report['runtimeIdentifier'] = runtime
        boot = driver.run('boot_owned_simulator', ['xcrun', 'simctl', 'boot', owned])
        if boot.returncode:
            raise Blocked('owned_simulator_boot_failed')
        ready = driver.run('owned_bootstatus', ['xcrun', 'simctl', 'bootstatus', owned, '-b'], maximum=240)
        if ready.returncode:
            raise Blocked('owned_simulator_not_ready')
        developer = driver.run('selected_developer_directory', ['xcode-select', '-p'])
        if developer.returncode:
            raise Blocked('selected_developer_directory_unavailable')
        simulator = Path(developer.stdout.strip())/'Applications/Simulator.app'
        with (simulator/'Contents/Info.plist').open('rb') as stream:
            bundle = plistlib.load(stream)['CFBundleIdentifier']
        if not isinstance(bundle, str) or not bundle.startswith('com.apple.'):
            raise Blocked('selected_Simulator_bundle_unavailable')
        opened = driver.run('open_owned_simulator_window', ['open', '-a', str(simulator), '--args', '-CurrentDeviceUDID', owned])
        if opened.returncode:
            raise Blocked('owned_simulator_window_unavailable')
        window = driver.run('verify_owned_window_before_xctest', [str(binary), name, bundle, '--window-only'], maximum=60)
        report['windowReadiness'] = json.loads(window.stdout)
        if (window.returncode or report['windowReadiness'].get('ownedWindowVerified') is not True
                or report['windowReadiness'].get('ownedFocusVerified') is not True
                or report['windowReadiness'].get('enrollmentActionAttempted') is not False):
            raise Blocked('owned_window_readiness_unproven')
        before = run_phase(driver, helper, 'before', owned, project, temporary)
        menu = driver.run('official_menu_single_enrollment_attempt', [str(binary), name, bundle], maximum=90)
        report['menu'] = json.loads(menu.stdout)
        report['menuHelperExitCode'] = menu.returncode
        report['menuOnlyStatus'] = 'Passed' if menu.returncode == 0 else 'Failed'
        # Still take the after observation when the menu mark stays unchecked.
        # It is reported independently; the menu action is never repeated.
        after = run_phase(driver, helper, 'after', owned, project, temporary)
        complete_menu = (report['menu'].get('queryStage') == 'complete'
                         and report['menu'].get('ownedWindowVerified') is True
                         and report['menu'].get('matchingFaceInvoked') is False)
        if not complete_menu:
            report['combinedCapabilityStatus'] = 'Failed'
            raise Blocked('official_menu_attempt_incomplete')
        if after['canEvaluate'] is not True:
            report['combinedCapabilityStatus'] = 'Failed'
            raise Blocked('after_biometric_capability_unavailable')
        report['combinedCapabilityStatus'] = 'Passed'
        report['status'] = 'Passed'
        report['beforeCanEvaluate'] = before['canEvaluate']
        report['afterCanEvaluate'] = after['canEvaluate']
        report['gate'] = 'Fresh before/after observations with exactly one passed, zero failed and zero skipped selected XCTest per phase; completed owned menu inspection and after canEvaluate true. Menu mark result remains separate.'
    except TimedOut as error:
        report['blocker'] = 'bounded_command_timeout'
        report['timeoutOperation'] = error.operation
    except Blocked as error:
        report['blocker'] = str(error)
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        report['blocker'] = 'capability_output_or_tool_error'
    finally:
        primary_stage = report.get('stage')
        if owned:
            cleanup(driver, owned)
        report['stage'] = primary_stage
        if temporary_manager is not None:
            try:
                temporary_manager.cleanup()
                report['privateTemporaryOutputsRemoved'] = True
            except OSError:
                report['privateTemporaryOutputsRemoved'] = False
                report['status'] = 'Blocked'
                report.setdefault('blocker', 'private_temporary_cleanup_incomplete')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8')
        print(json.dumps(report, sort_keys=True))
    return 0 if report['status'] == 'Passed' else 3


if __name__ == '__main__':
    raise SystemExit(main())
