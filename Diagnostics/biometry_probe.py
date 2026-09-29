"""Disposable Simulator / official Face ID menu capability probe. No app login.

Publish only to Diagnostics/biometry_probe.py on the separate diagnostic branch.
No TCC modifications, private notifications, raw GUI dumps or screenshots.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile
import time
from uuid import UUID, uuid4

SWIFT = r'''
import Foundation
import AppKit
import ApplicationServices
import CoreServices

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
let trusted = AXIsProcessTrusted()
let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
var result: [String: Any] = ["accessibilityTrusted": trusted, "automationStatus": permission,
                           "automationPromptRequested": false, "uiElementsEnabled": false]
guard permission == noErr else { emit(result); exit(3) }
var error: NSDictionary?
let enabled = NSAppleScript(source: "tell application id \"com.apple.systemevents\" to return UI elements enabled")!.executeAndReturnError(&error)
if let error = error {
    result["scriptErrorCode"] = error[NSAppleScript.errorNumber] as? Int ?? 0
    emit(result); exit(3)
}
result["uiElementsEnabled"] = enabled.booleanValue
guard trusted && enabled.booleanValue else { emit(result); exit(3) }
if CommandLine.arguments.count == 1 { emit(result); exit(0) }
let name = CommandLine.arguments[1]
guard name.hasPrefix("NIDAA Biometry Probe ") && name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }) else { exit(4) }
guard CommandLine.arguments.count == 3 else { exit(4) }
let bundle = CommandLine.arguments[2]
guard bundle.hasPrefix("com.apple.") && bundle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { exit(4) }
result["queryStage"] = "running_application_wait"
var application: NSRunningApplication?
let applicationDeadline = Date().addingTimeInterval(15)
repeat {
    application = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    if application != nil { break }
    Thread.sleep(forTimeInterval: 0.25)
} while Date() < applicationDeadline
guard let application = application else {
    result["simulatorProcessObserved"] = false; emit(result); exit(3)
}
result["simulatorProcessObserved"] = true
let pid = application.processIdentifier
let source = """
set probeStage to "system_events_process_wait"
set ownedWindowVerified to false
set featuresPresent to false
set hardwarePresent to false
set facePresent to false
set enrolledPresent to false
set markReadable to false
try
tell application id "com.apple.systemevents"
  repeat with attempt from 1 to 60
    if exists application process whose unix id is \(pid) then exit repeat
    delay 0.25
  end repeat
  if not (exists application process whose unix id is \(pid)) then error number -27000
  tell first application process whose unix id is \(pid)
    set probeStage to "owned_window_wait"
    repeat with attempt from 1 to 60
      if exists window whose name contains "\(name)" then exit repeat
      delay 0.25
    end repeat
    if not (exists window whose name contains "\(name)" ) then error number -27001
    set probeStage to "select_owned_window"
    set ownedWindow to first window whose name contains "\(name)"
    set probeStage to "raise_owned_window"
    set frontmost to true
    perform action "AXRaise" of ownedWindow
    set probeStage to "verify_front_owned_window"
    if not ((name of front window) contains "\(name)") then error number -27002
    set ownedWindowVerified to true
    set probeStage to "features_hardware_presence"
    set featuresPresent to exists menu bar item "Features" of menu bar 1
    set hardwarePresent to exists menu bar item "Hardware" of menu bar 1
    if featuresPresent then
      set topItem to menu bar item "Features" of menu bar 1
    else if hardwarePresent then
      set topItem to menu bar item "Hardware" of menu bar 1
    else
      error number -27003
    end if
    set probeStage to "open_features_hardware_menu"
    click topItem
    set probeStage to "face_id_presence"
    set facePresent to exists menu item "Face ID" of menu 1 of topItem
    if not facePresent then error number -27004
    set faceItem to menu item "Face ID" of menu 1 of topItem
    set probeStage to "open_face_id_menu"
    click faceItem
    set probeStage to "enrolled_presence"
    set enrolledPresent to exists menu item "Enrolled" of menu 1 of faceItem
    if not enrolledPresent then error number -27005
    set enrollItem to menu item "Enrolled" of menu 1 of faceItem
    set probeStage to "enrolled_enabled"
    if not (enabled of enrollItem) then error number -27006
    set probeStage to "enrolled_mark_read_before"
    set markReadable to exists attribute "AXMenuItemMarkChar" of enrollItem
    if not markReadable then error number -27007
    set markBefore to value of attribute "AXMenuItemMarkChar" of enrollItem
    set checkedBefore to (markBefore is not missing value and markBefore is not "")
    set changed to false
    if not checkedBefore then
      set probeStage to "verify_owned_window_before_enrollment"
      if not ((name of front window) contains "\(name)") then error number -27002
      set probeStage to "enable_enrollment"
      click enrollItem
      set changed to true
      set probeStage to "reopen_features_after_enrollment"
      click topItem
      set probeStage to "reopen_face_id_after_enrollment"
      click faceItem
    end if
    set probeStage to "enrolled_mark_read_after"
    set enrollItem to menu item "Enrolled" of menu 1 of faceItem
    if not (exists attribute "AXMenuItemMarkChar" of enrollItem) then error number -27008
    set markAfter to value of attribute "AXMenuItemMarkChar" of enrollItem
    set checkedAfter to (markAfter is not missing value and markAfter is not "")
    set probeStage to "matching_face_presence"
    set matchingPresent to exists menu item "Matching Face" of menu 1 of faceItem
    set matchingEnabled to false
    set probeStage to "matching_face_enabled"
    if matchingPresent then set matchingEnabled to enabled of menu item "Matching Face" of menu 1 of faceItem
    set probeStage to "close_menu"
    key code 53
    return "ok|" & ((checkedBefore as integer) as text) & "|" & ((changed as integer) as text) & "|" & ((checkedAfter as integer) as text) & "|" & ((matchingPresent as integer) as text) & "|" & ((matchingEnabled as integer) as text) & "|" & ((ownedWindowVerified as integer) as text) & "|" & ((featuresPresent as integer) as text) & "|" & ((hardwarePresent as integer) as text) & "|" & ((facePresent as integer) as text) & "|" & ((enrolledPresent as integer) as text) & "|" & ((markReadable as integer) as text)
  end tell
end tell
on error number code
  return "error|" & (code as text) & "|" & probeStage & "|" & ((ownedWindowVerified as integer) as text) & "|" & ((featuresPresent as integer) as text) & "|" & ((hardwarePresent as integer) as text) & "|" & ((facePresent as integer) as text) & "|" & ((enrolledPresent as integer) as text) & "|" & ((markReadable as integer) as text)
end try
"""
error = nil
result["queryStage"] = "apple_script_compile_or_dispatch"
let response = NSAppleScript(source: source)!.executeAndReturnError(&error)
if let error = error {
    result["scriptErrorCode"] = error[NSAppleScript.errorNumber] as? Int ?? 0
    if let range = error[NSAppleScript.errorRange] as? NSValue {
        result["scriptErrorRangeLocation"] = range.rangeValue.location
        result["scriptErrorRangeLength"] = range.rangeValue.length
    }
    emit(result); exit(3)
}
let fields = (response.stringValue ?? "").split(separator: "|").map(String.init)
if fields.first == "error" && fields.count == 9 {
    result["scriptErrorCode"] = Int(fields[1]) ?? 0
    result["queryStage"] = fields[2]
    for (key, value) in zip(["ownedWindowVerified", "featuresMenuPresent", "hardwareMenuPresent", "faceIDMenuPresent", "enrolledMenuPresent", "enrolledMarkReadable"], fields.dropFirst(3)) {
        result[key] = value == "1"
    }
    emit(result); exit(3)
}
let values = fields.dropFirst().compactMap { Int($0) }
guard fields.first == "ok" && values.count == 11 && values.allSatisfy({ $0 == 0 || $0 == 1 }) else { result["parseFailed"] = true; emit(result); exit(3) }
result["queryStage"] = "complete"
result["ownedWindowVerified"] = true
for (key, value) in zip(["enrolledBefore", "enrollmentChanged", "enrolledAfter", "matchingFaceMenuPresent", "matchingFaceMenuEnabled"], values) {
    result[key] = value == 1
}
for (key, value) in zip(["ownedWindowVerified", "featuresMenuPresent", "hardwareMenuPresent", "faceIDMenuPresent", "enrolledMenuPresent", "enrolledMarkReadable"], values.dropFirst(5)) {
    result[key] = value == 1
}
result["matchingFaceInvoked"] = false
emit(result)
exit(values[2] == 1 && values[3] == 1 ? 0 : 3)
'''


class Blocked(Exception):
    pass


class ProbeTimeout(Exception):
    def __init__(self, record):
        self.record = record


COMMAND_TRACE = []
COMMAND_DEADLINE = None


def command(argv, timeout=30):
    # Only fixed command/subcommand tokens are published. Paths, device UUIDs
    # and arguments are excluded even from timeout diagnostics.
    allowed = {'--find', 'simctl', 'help', 'swiftc', 'list', 'devices', 'available',
               'create', 'boot', 'bootstatus', 'shutdown', 'delete', '-g', '-b', '-p', '-a',
               'com.apple.systemevents'}
    coarse = [Path(argv[0]).name] + [value if value in allowed else '[argument]' for value in argv[1:3]]
    requested_timeout = timeout
    if COMMAND_DEADLINE is not None:
        timeout = max(0, min(timeout, COMMAND_DEADLINE-time.monotonic()))
    record = {'command': coarse, 'timeoutSeconds': round(timeout, 3), 'requestedTimeoutSeconds': requested_timeout}
    COMMAND_TRACE.append(record)
    started = time.monotonic()
    try:
        if timeout <= 0:
            record['timedOut'] = True
            record['probeBudgetExhausted'] = True
            raise ProbeTimeout(record)
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        record['exitCode'] = result.returncode
        return result
    except subprocess.TimeoutExpired:
        record['timedOut'] = True
        raise ProbeTimeout(record) from None
    finally:
        record['elapsedSeconds'] = round(time.monotonic()-started, 3)


def main():
    global COMMAND_DEADLINE
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('artifacts/biometry-capability/report.json'))
    args = parser.parse_args()
    COMMAND_TRACE.clear()
    # Leave up to 60 seconds for exact-owned-device cleanup and 30 seconds for
    # artifact upload within the workflow's eight-minute limit.
    COMMAND_DEADLINE = time.monotonic()+390
    report = {'schemaVersion': 1, 'status': 'Blocked', 'capabilityOnly': True, 'appCredentialsCreated': False,
              'privateAPIsUsed': False, 'TCCChanged': False, 'physicalBiometryProven': False,
              'ownedDeviceCreated': False, 'ownedDeviceDeleted': False,
              'commandTrace': COMMAND_TRACE,
              'probeSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    owned = None
    try:
        if platform.system() != 'Darwin':
            raise Blocked('macOS_required')
        report['stage'] = 'locate_simctl'
        located = command(['xcrun', '--find', 'simctl'], timeout=30)
        report['simctlLocateExitCode'] = located.returncode
        if located.returncode or not Path(located.stdout.strip()).is_file():
            raise Blocked('installed_simctl_unavailable')
        report['stage'] = 'simctl_help'
        help_result = command([located.stdout.strip(), 'help'], timeout=120)
        report['simctlHelpExitCode'] = help_result.returncode
        report['simctlHelpMentionsBiometry'] = any(word in help_result.stdout.lower() for word in ('biometric', 'biometry', 'face id'))
        if help_result.returncode:
            raise Blocked('simctl_help_unavailable')
        with tempfile.TemporaryDirectory(prefix='nidaa-biometry-probe-') as temporary:
            source = Path(temporary)/'Capability.swift'
            binary = Path(temporary)/'capability'
            source.write_text(SWIFT, encoding='utf-8')
            report['stage'] = 'compile_permission_helper'
            built = command(['xcrun', 'swiftc', str(source), '-o', str(binary)], timeout=90)
            report['permissionHelperCompileExitCode'] = built.returncode
            if built.returncode:
                raise Blocked('permission_helper_compile_failed')
            # -600 means the Apple Event target is not running, not denied
            # permission. Launch the system app normally before asking the same
            # native helper for no-prompt authorization; no automation event,
            # TCC edit or consent request is used to perform this launch.
            report['stage'] = 'launch_system_events'
            launched = command(['open', '-g', '-b', 'com.apple.systemevents'], timeout=10)
            report['systemEventsLaunchExitCode'] = launched.returncode
            if launched.returncode:
                raise Blocked('system_events_launch_failed')
            time.sleep(1)
            report['stage'] = 'no_prompt_GUI_permission_check'
            permissions = command([str(binary)])
            report['permissionHelperExitCode'] = permissions.returncode
            report['permissions'] = json.loads(permissions.stdout)
            if permissions.returncode:
                status = report['permissions'].get('automationStatus')
                if status == -600:
                    raise Blocked('system_events_target_unavailable')
                if status == -1743:
                    raise Blocked('automation_permission_denied')
                if status == -1744:
                    raise Blocked('automation_consent_required_no_prompt_requested')
                if status != 0:
                    raise Blocked('automation_permission_check_failed')
                if report['permissions'].get('accessibilityTrusted') is not True:
                    raise Blocked('accessibility_permission_unavailable')
                raise Blocked('system_events_UI_elements_unavailable')
            report['stage'] = 'owned_simulator_setup'
            listing = command(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'])
            if listing.returncode:
                raise Blocked('simulator_inventory_unavailable')
            data = json.loads(listing.stdout)
            devices = [(runtime, d) for runtime, values in data['devices'].items() if 'iOS' in runtime
                       for d in values if d.get('isAvailable') and 'iPhone' in d['name']]
            if not devices:
                raise Blocked('iPhone_template_unavailable')
            # Same preference as Scripts/select_simulator.py --template. Only
            # the template type/runtime are reused; never boot the template.
            def priority(item):
                _, device = item
                return (0 if device['name'] in ['iPhone 16 Pro','iPhone 17 Pro','iPhone 15 Pro'] else 1,
                        'Max' in device['name'], 'SE' in device['name'], device['name'])
            runtime, template = sorted(devices, key=priority)[0]
            name = 'NIDAA Biometry Probe '+uuid4().hex
            created = command(['xcrun', 'simctl', 'create', name, template['deviceTypeIdentifier'], runtime])
            if created.returncode:
                raise Blocked('owned_simulator_creation_failed')
            owned = str(UUID(created.stdout.strip())).upper()
            report['ownedDeviceCreated'] = True
            report['runtimeIdentifier'] = runtime
            boot = command(['xcrun', 'simctl', 'boot', owned])
            report['bootExitCode'] = boot.returncode
            if boot.returncode:
                raise Blocked('owned_simulator_boot_failed')
            ready = command(['xcrun', 'simctl', 'bootstatus', owned, '-b'], timeout=150)
            report['bootstatusExitCode'] = ready.returncode
            if ready.returncode:
                raise Blocked('owned_simulator_not_ready')
            developer = command(['xcode-select', '-p'])
            if developer.returncode:
                raise Blocked('developer_directory_unavailable')
            simulator = Path(developer.stdout.strip())/'Applications/Simulator.app'
            if not simulator.is_dir():
                raise Blocked('selected_Simulator_app_unavailable')
            with (simulator/'Contents/Info.plist').open('rb') as stream:
                bundle_identifier = plistlib.load(stream)['CFBundleIdentifier']
            if not isinstance(bundle_identifier, str) or not bundle_identifier.startswith('com.apple.'):
                raise Blocked('selected_Simulator_bundle_unavailable')
            report['installedSimulatorBundleMatchesExpected'] = bundle_identifier == 'com.apple.iphonesimulator'
            opened = command(['open', '-a', str(simulator), '--args', '-CurrentDeviceUDID', owned])
            report['openExactDeviceExitCode'] = opened.returncode
            if opened.returncode:
                raise Blocked('owned_simulator_window_unavailable')
            report['stage'] = 'official_Face_ID_menu'
            inspected = command([str(binary), name, bundle_identifier], timeout=90)
            report['menuHelperExitCode'] = inspected.returncode
            report['menu'] = json.loads(inspected.stdout)
            if inspected.returncode:
                raise Blocked('official_menu_inspection_or_enrollment_unavailable')
            report['status'] = 'Passed'
            report['scope'] = 'Official Face ID Enrolled menu only; no app challenge or AutoFill insertion'
    except Blocked as error:
        report['blocker'] = str(error)
    except ProbeTimeout as error:
        report['blocker'] = 'bounded_command_timeout'
        report['timeoutCommand'] = error.record['command']
        report['timeoutSeconds'] = error.record['timeoutSeconds']
        report['timeoutElapsedSeconds'] = error.record['elapsedSeconds']
    except (OSError, ValueError, KeyError, TypeError):
        report['blocker'] = 'capability_output_or_tool_error'
    finally:
        COMMAND_DEADLINE = None
        if owned:
            try:
                stopped = command(['xcrun', 'simctl', 'shutdown', owned], timeout=30)
                deleted = command(['xcrun', 'simctl', 'delete', owned], timeout=30)
                report['ownedShutdownExitCode'] = stopped.returncode
                report['ownedDeleteExitCode'] = deleted.returncode
                report['ownedDeviceDeleted'] = deleted.returncode == 0
                if deleted.returncode:
                    report['status'] = 'Blocked'
                    report['blocker'] = 'owned_simulator_cleanup_failed'
            except (OSError, ProbeTimeout):
                report['status'] = 'Blocked'
                report['blocker'] = 'owned_simulator_cleanup_failed'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8')
        print(json.dumps(report, sort_keys=True))
    return 0 if report['status'] == 'Passed' else 3


if __name__ == '__main__':
    raise SystemExit(main())
