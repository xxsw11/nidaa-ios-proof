"""Disposable Simulator / official Face ID menu capability probe. No app login.

Publish only to Diagnostics/biometry_probe.py on the separate diagnostic branch.
No TCC modifications, private notifications, raw GUI dumps or screenshots.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import time
from uuid import UUID, uuid4

SWIFT = r'''
import Foundation
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
let source = """
tell application id "com.apple.systemevents"
  tell first application process whose bundle identifier is "com.apple.iphonesimulator"
    set frontmost to true
    if not (exists window whose name contains "\(name)") then error number -27001
    perform action "AXRaise" of first window whose name contains "\(name)"
    if not ((name of front window) contains "\(name)") then error number -27002
    if exists menu bar item "Features" of menu bar 1 then
      set topItem to menu bar item "Features" of menu bar 1
    else if exists menu bar item "Hardware" of menu bar 1 then
      set topItem to menu bar item "Hardware" of menu bar 1
    else
      error number -27003
    end if
    click topItem
    if not (exists menu item "Face ID" of menu 1 of topItem) then error number -27004
    set faceItem to menu item "Face ID" of menu 1 of topItem
    click faceItem
    if not (exists menu item "Enrolled" of menu 1 of faceItem) then error number -27005
    set enrollItem to menu item "Enrolled" of menu 1 of faceItem
    if not (enabled of enrollItem) then error number -27006
    if not (exists attribute "AXMenuItemMarkChar" of enrollItem) then error number -27007
    set markBefore to value of attribute "AXMenuItemMarkChar" of enrollItem
    set checkedBefore to (markBefore is not missing value and markBefore is not "")
    set changed to false
    if not checkedBefore then
      click enrollItem
      set changed to true
      click topItem
      click faceItem
    end if
    set enrollItem to menu item "Enrolled" of menu 1 of faceItem
    if not (exists attribute "AXMenuItemMarkChar" of enrollItem) then error number -27008
    set markAfter to value of attribute "AXMenuItemMarkChar" of enrollItem
    set checkedAfter to (markAfter is not missing value and markAfter is not "")
    set matchingPresent to exists menu item "Matching Face" of menu 1 of faceItem
    set matchingEnabled to false
    if matchingPresent then set matchingEnabled to enabled of menu item "Matching Face" of menu 1 of faceItem
    key code 53
    return ((checkedBefore as integer) as text) & "|" & ((changed as integer) as text) & "|" & ((checkedAfter as integer) as text) & "|" & ((matchingPresent as integer) as text) & "|" & ((matchingEnabled as integer) as text)
  end tell
end tell
"""
error = nil
let response = NSAppleScript(source: source)!.executeAndReturnError(&error)
if let error = error {
    result["scriptErrorCode"] = error[NSAppleScript.errorNumber] as? Int ?? 0
    emit(result); exit(3)
}
let values = (response.stringValue ?? "").split(separator: "|").compactMap { Int($0) }
guard values.count == 5 && values.allSatisfy({ $0 == 0 || $0 == 1 }) else { result["parseFailed"] = true; emit(result); exit(3) }
for (key, value) in zip(["enrolledBefore", "enrollmentChanged", "enrolledAfter", "matchingFaceMenuPresent", "matchingFaceMenuEnabled"], values) {
    result[key] = value == 1
}
result["matchingFaceInvoked"] = false
emit(result)
exit(values[2] == 1 && values[3] == 1 ? 0 : 3)
'''


class Blocked(Exception):
    pass


def command(argv, timeout=30):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('artifacts/biometry-capability/report.json'))
    args = parser.parse_args()
    report = {'schemaVersion': 1, 'status': 'Blocked', 'capabilityOnly': True, 'appCredentialsCreated': False,
              'privateAPIsUsed': False, 'TCCChanged': False, 'physicalBiometryProven': False,
              'ownedDeviceCreated': False, 'ownedDeviceDeleted': False,
              'probeSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    owned = None
    try:
        if platform.system() != 'Darwin':
            raise Blocked('macOS_required')
        help_result = command(['xcrun', 'simctl', 'help'])
        report['simctlHelpExitCode'] = help_result.returncode
        report['simctlHelpMentionsBiometry'] = any(word in help_result.stdout.lower() for word in ('biometric', 'biometry', 'face id'))
        if help_result.returncode:
            raise Blocked('simctl_help_unavailable')
        with tempfile.TemporaryDirectory(prefix='nidaa-biometry-probe-') as temporary:
            source = Path(temporary)/'Capability.swift'
            binary = Path(temporary)/'capability'
            source.write_text(SWIFT, encoding='utf-8')
            built = command(['xcrun', 'swiftc', str(source), '-o', str(binary)], timeout=90)
            report['permissionHelperCompileExitCode'] = built.returncode
            if built.returncode:
                raise Blocked('permission_helper_compile_failed')
            permissions = command([str(binary)])
            report['permissionHelperExitCode'] = permissions.returncode
            report['permissions'] = json.loads(permissions.stdout)
            if permissions.returncode:
                raise Blocked('host_GUI_permissions_unavailable_without_prompt')
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
            opened = command(['open', '-a', str(simulator), '--args', '-CurrentDeviceUDID', owned])
            report['openExactDeviceExitCode'] = opened.returncode
            if opened.returncode:
                raise Blocked('owned_simulator_window_unavailable')
            time.sleep(2)
            inspected = command([str(binary), name])
            report['menuHelperExitCode'] = inspected.returncode
            report['menu'] = json.loads(inspected.stdout)
            if inspected.returncode:
                raise Blocked('official_menu_inspection_or_enrollment_unavailable')
            report['status'] = 'Passed'
            report['scope'] = 'Official Face ID Enrolled menu only; no app challenge or AutoFill insertion'
    except Blocked as error:
        report['blocker'] = str(error)
    except subprocess.TimeoutExpired:
        report['blocker'] = 'bounded_command_timeout'
    except (OSError, ValueError, KeyError, TypeError):
        report['blocker'] = 'capability_output_or_tool_error'
    finally:
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
            except (OSError, subprocess.TimeoutExpired):
                report['status'] = 'Blocked'
                report['blocker'] = 'owned_simulator_cleanup_failed'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8')
        print(json.dumps(report, sort_keys=True))
    return 0 if report['status'] == 'Passed' else 3


if __name__ == '__main__':
    raise SystemExit(main())
