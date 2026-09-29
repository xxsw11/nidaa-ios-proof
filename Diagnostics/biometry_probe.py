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
import re
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
// Embedded into the outside-repository Python probe; public AX menu path only.
enum AXProbeFailure: Error { case failed(String, Int32) }
func fail(_ stage: String, _ code: Int32) throws -> Never {
    throw AXProbeFailure.failed(stage, code)
}
func readAX(_ element: AXUIElement, _ attribute: String, _ stage: String, optional: Bool = false) throws -> CFTypeRef? {
    result["queryStage"] = stage
    var value: CFTypeRef?
    let code = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    result["axReturnCode"] = code.rawValue
    if code != .success {
        if optional && (code == .noValue || code == .attributeUnsupported) { return nil }
        try fail(stage, code.rawValue)
    }
    return value
}
func children(_ element: AXUIElement, _ stage: String) throws -> [AXUIElement] {
    guard let value = try readAX(element, kAXChildrenAttribute, stage, optional: true) else { return [] }
    guard let list = value as? [AXUIElement] else { try fail(stage, -27020) }
    return list
}
func title(_ element: AXUIElement, _ stage: String) throws -> String? {
    return try readAX(element, kAXTitleAttribute, stage, optional: true) as? String
}
func role(_ element: AXUIElement, _ stage: String) throws -> String? {
    return try readAX(element, kAXRoleAttribute, stage, optional: true) as? String
}
var actionCodes: [String: Int32] = [:]
func action(_ element: AXUIElement, _ action: String, _ stage: String) throws {
    result["queryStage"] = stage
    let code = AXUIElementPerformAction(element, action as CFString)
    result["axReturnCode"] = code.rawValue
    actionCodes[stage] = code.rawValue
    result["axActionCodes"] = actionCodes
    // Apple documents that modal processing can return cannotComplete after
    // handling an action. Do not repeat it; the caller must read its actual
    // postcondition (owned focus, opened submenu, or final enrollment mark).
    if code != .success && code != .cannotComplete { try fail(stage, code.rawValue) }
}
func oneElement(_ value: CFTypeRef?, _ stage: String) throws -> AXUIElement {
    guard let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { try fail(stage, -27021) }
    return unsafeBitCast(value, to: AXUIElement.self)
}
func fixedItem(_ list: [AXUIElement], _ wanted: String, _ stage: String) throws -> AXUIElement? {
    for element in list {
        if try title(element, stage) == wanted { return element }
    }
    return nil
}
func submenu(_ item: AXUIElement, _ stage: String) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(4)
    repeat {
        for child in try children(item, stage) {
            if try role(child, stage) == kAXMenuRole { return child }
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    try fail(stage, -27022)
}
func isEnabled(_ item: AXUIElement, _ stage: String) throws -> Bool {
    guard let value = try readAX(item, kAXEnabledAttribute, stage) as? NSNumber else { try fail(stage, -27023) }
    return value.boolValue
}
func isChecked(_ item: AXUIElement, _ stage: String) throws -> Bool {
    result["queryStage"] = stage
    var attributes: CFArray?
    let code = AXUIElementCopyAttributeNames(item, &attributes)
    result["axReturnCode"] = code.rawValue
    if code != .success { try fail(stage, code.rawValue) }
    guard let names = attributes as? [String], names.contains(kAXMenuItemMarkCharAttribute) else { try fail(stage, -27024) }
    result["enrolledMarkReadable"] = true
    let value = try readAX(item, kAXMenuItemMarkCharAttribute, stage, optional: true)
    guard let value = value else { return false }
    guard let mark = value as? String else { try fail(stage, -27025) }
    // Empty/no value is unchecked. Unknown marks do not authorize a toggle.
    if mark.isEmpty { return false }
    if mark == "✓" || mark == "✔" { return true }
    try fail(stage, -27026)
}

let appAX = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(appAX, 2)
func requireOwnedFocus(_ stage: String) throws {
    let deadline = Date().addingTimeInterval(4)
    repeat {
        do {
            guard application.isActive else { try fail(stage, -27027) }
            let focused = try oneElement(readAX(appAX, kAXFocusedWindowAttribute, stage), stage)
            guard try title(focused, stage)?.contains(name) == true else { try fail(stage, -27002) }
            return
        } catch AXProbeFailure.failed(_, let code) {
            result["lastFocusWaitCode"] = code
            let retryable = code == AXError.cannotComplete.rawValue || code == AXError.noValue.rawValue || code == -27027 || code == -27002
            if !retryable || Date() >= deadline { try fail(stage, code) }
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    try fail(stage, (result["lastFocusWaitCode"] as? Int32) ?? -27002)
}
do {
    result["queryStage"] = "owned_AX_window_wait"
    var ownedWindow: AXUIElement?
    let deadline = Date().addingTimeInterval(20)
    repeat {
        do {
            if let value = try readAX(appAX, kAXWindowsAttribute, "owned_AX_windows", optional: true),
               let windows = value as? [AXUIElement] {
                for window in windows {
                    if try title(window, "owned_AX_window_title")?.contains(name) == true {
                        ownedWindow = window; break
                    }
                }
            }
        } catch AXProbeFailure.failed(let stage, let code) {
            result["lastWindowWaitCode"] = code
            // Only retry this read-only startup transient. No AX action is
            // repeated by this wait, especially the non-idempotent toggle.
            if code != AXError.cannotComplete.rawValue || Date() >= deadline { try fail(stage, code) }
        }
        if ownedWindow != nil { break }
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    guard let ownedWindow = ownedWindow else { try fail("owned_AX_window_wait", -27001) }
    result["ownedWindowVerified"] = true
    result["queryStage"] = "activate_owned_Simulator"
    guard application.activate(options: [.activateIgnoringOtherApps]) else { try fail("activate_owned_Simulator", -27028) }
    try action(ownedWindow, kAXRaiseAction, "raise_owned_AX_window")
    Thread.sleep(forTimeInterval: 0.25)
    try requireOwnedFocus("verify_owned_AX_focus")
    let bar = try oneElement(readAX(appAX, kAXMenuBarAttribute, "AX_menu_bar"), "AX_menu_bar")
    let topItems = try children(bar, "AX_menu_bar_children")
    let features = try fixedItem(topItems, "Features", "features_presence")
    let hardware = try fixedItem(topItems, "Hardware", "hardware_presence")
    result["featuresMenuPresent"] = features != nil
    result["hardwareMenuPresent"] = hardware != nil
    guard let top = features ?? hardware else { try fail("features_hardware_presence", -27003) }
    try requireOwnedFocus("verify_owned_focus_before_menu")
    try action(top, kAXPressAction, "press_features_hardware")
    let topMenu = try submenu(top, "features_submenu")
    let face = try fixedItem(children(topMenu, "features_items"), "Face ID", "face_id_presence")
    result["faceIDMenuPresent"] = face != nil
    guard let face = face else { try fail("face_id_presence", -27004) }
    try action(face, kAXPressAction, "press_face_id")
    var faceMenu = try submenu(face, "face_id_submenu")
    let enrolled = try fixedItem(children(faceMenu, "face_id_items"), "Enrolled", "enrolled_presence")
    result["enrolledMenuPresent"] = enrolled != nil
    guard let enrolled = enrolled else { try fail("enrolled_presence", -27005) }
    guard try isEnabled(enrolled, "enrolled_enabled") else { try fail("enrolled_enabled", -27006) }
    let before = try isChecked(enrolled, "enrolled_mark_before")
    result["enrolledBefore"] = before
    let matchingBefore = try fixedItem(children(faceMenu, "face_id_items_before"), "Matching Face", "matching_face_before_presence")
    result["matchingFaceMenuPresentBefore"] = matchingBefore != nil
    result["matchingFaceMenuEnabledBefore"] = try matchingBefore.map { try isEnabled($0, "matching_face_before_enabled") } ?? false
    result["enrollmentChanged"] = false
    result["enrollmentOutcomeProven"] = false
    if !before {
        try requireOwnedFocus("verify_owned_focus_before_enrollment")
        // A timeout/uncertain AXPress is never retried: toggles are not idempotent.
        result["enrollmentActionAttempted"] = true
        try action(enrolled, kAXPressAction, "press_enrolled_once")
        try requireOwnedFocus("verify_owned_focus_after_enrollment")
        try action(top, kAXPressAction, "reopen_features")
        let refreshedTop = try submenu(top, "refreshed_features_submenu")
        guard let refreshedFace = try fixedItem(children(refreshedTop, "refreshed_features_items"), "Face ID", "refreshed_face_id") else { try fail("refreshed_face_id", -27004) }
        try action(refreshedFace, kAXPressAction, "reopen_face_id")
        faceMenu = try submenu(refreshedFace, "refreshed_face_submenu")
    }
    // Enrollment may settle asynchronously. Reacquire the menu path and item
    // for every read; never press Enrolled again, even if its mark stays empty.
    let readbackStarted = ProcessInfo.processInfo.systemUptime
    let readbackDeadline = readbackStarted + 10
    var readbackSamples: [[String: Any]] = []
    var finalItems: [AXUIElement] = []
    var after = false
    repeat {
        var sample: [String: Any] = ["markKnown": false, "checked": false]
        do {
            let freshBar = try oneElement(readAX(appAX, kAXMenuBarAttribute, "readback_menu_bar"), "readback_menu_bar")
            let freshTopItems = try children(freshBar, "readback_menu_bar_items")
            let freshFeatures = try fixedItem(freshTopItems, "Features", "readback_features")
            let freshHardware = try fixedItem(freshTopItems, "Hardware", "readback_hardware")
            guard let freshTop = freshFeatures ?? freshHardware else { try fail("readback_top_menu", -27003) }
            let freshTopMenu = try submenu(freshTop, "readback_top_submenu")
            guard let freshFace = try fixedItem(children(freshTopMenu, "readback_top_items"), "Face ID", "readback_face_id") else { try fail("readback_face_id", -27004) }
            faceMenu = try submenu(freshFace, "readback_face_submenu")
            finalItems = try children(faceMenu, "readback_face_items")
            guard let finalEnrolled = try fixedItem(finalItems, "Enrolled", "readback_enrolled") else { try fail("readback_enrolled", -27005) }
            after = try isChecked(finalEnrolled, "enrolled_mark_after")
            sample["markKnown"] = true
            sample["checked"] = after
            sample["axReturnCode"] = result["axReturnCode"]
        } catch AXProbeFailure.failed(let stage, let code) {
            sample["axReturnCode"] = code
            sample["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - readbackStarted
            readbackSamples.append(sample)
            result["enrollmentReadbackSamples"] = readbackSamples
            try fail(stage, code)
        }
        sample["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - readbackStarted
        readbackSamples.append(sample)
        result["enrollmentReadbackSamples"] = readbackSamples
        if after || ProcessInfo.processInfo.systemUptime >= readbackDeadline { break }
        Thread.sleep(forTimeInterval: min(0.5, max(0, readbackDeadline - ProcessInfo.processInfo.systemUptime)))
    } while ProcessInfo.processInfo.systemUptime < readbackDeadline
    result["enrollmentReadbackElapsedSeconds"] = ProcessInfo.processInfo.systemUptime - readbackStarted
    result["enrollmentReadbackTimedOut"] = !after
    result["enrolledAfter"] = after
    result["enrollmentChanged"] = after && !before
    result["enrollmentOutcomeProven"] = after
    let matching = try fixedItem(finalItems, "Matching Face", "matching_face_presence")
    result["matchingFaceMenuPresent"] = matching != nil
    result["matchingFaceMenuEnabled"] = try matching.map { try isEnabled($0, "matching_face_enabled") } ?? false
    result["matchingFaceInvoked"] = false
    // Cancel only this owned app's opened menu through a public AX action.
    let cancelCode = AXUIElementPerformAction(faceMenu, kAXCancelAction as CFString)
    result["menuCancelReturnCode"] = cancelCode.rawValue
    result["queryStage"] = "complete"
    emit(result); exit(after && matching != nil ? 0 : 3)
} catch AXProbeFailure.failed(let stage, let code) {
    result["queryStage"] = stage
    result["axErrorCode"] = code
    emit(result); exit(3)
} catch {
    result["queryStage"] = "unexpected_AX_helper_error"
    emit(result); exit(3)
}

'''


OBSERVER_BUNDLE = 'org.nidaa.diagnostics.BiometryObserver'
OBSERVER_SWIFT = r'''
import UIKit
import LocalAuthentication

final class ObserverDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--phase"), index + 1 < arguments.count else { return false }
        let phase = arguments[index + 1]
        guard phase == "before" || phase == "after" else { return false }
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let observation: [String: Any] = ["schemaVersion": 1, "phase": phase, "policy": 1,
            "canEvaluate": available, "laErrorCode": error?.code ?? 0,
            "errorIsLocalAuthentication": error == nil || error?.domain == LAError.errorDomain,
            "biometryType": context.biometryType.rawValue, "authenticationPromptRequested": false]
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent("observer-\(phase).json"), options: [.atomic])
        } catch { return false }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(ObserverDelegate.self))
'''


class Blocked(Exception):
    pass


class ProbeTimeout(Exception):
    def __init__(self, record):
        self.record = record


COMMAND_TRACE = []
COMMAND_DEADLINE = None


def compiler_errors(stderr):
    # Only error suffixes from this public, credential-free helper source.
    # Do not publish source excerpts, tool paths, or the raw compiler stream.
    errors = []
    for line in stderr.splitlines():
        match = re.search(r':(\d+):(\d+): error: (.*)$', line)
        if not match:
            continue
        message = re.sub(r'(?:[A-Za-z]:)?[/\\][^\s\'"<>]+', '[path]', match.group(3))
        errors.append({'line': int(match.group(1)), 'column': int(match.group(2)), 'error': message[:240]})
        if len(errors) == 10:
            break
    return errors


def remaining_seconds():
    return max(0, COMMAND_DEADLINE-time.monotonic()) if COMMAND_DEADLINE is not None else 0


def build_observer(directory, report):
    observation = report['localAuthenticationObserver']
    if remaining_seconds() < 180:
        observation['buildStatus'] = 'Notexecuted-budget'
        observation['before']['status'] = 'Notexecuted-budget'
        observation['after']['status'] = 'Notexecuted-budget'
        return None
    report['stage'] = 'observer_sdk_discovery'
    sdk = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], timeout=20)
    observation['sdkDiscoveryExitCode'] = sdk.returncode
    if sdk.returncode or not Path(sdk.stdout.strip()).is_dir():
        observation['buildStatus'] = 'Failed-sdk-discovery'
        return None
    architecture = platform.machine()
    if architecture not in ('arm64', 'x86_64'):
        observation['buildStatus'] = 'Notexecuted-unsupported-host-architecture'
        return None
    app = directory/'BiometryObserver.app'
    app.mkdir()
    source = directory/'Observer.swift'
    source.write_text(OBSERVER_SWIFT, encoding='utf-8')
    metadata = {'CFBundleIdentifier': OBSERVER_BUNDLE, 'CFBundleExecutable': 'BiometryObserver',
                'CFBundleName': 'Biometry Observer', 'CFBundlePackageType': 'APPL',
                'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
                'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'MinimumOSVersion': '16.0',
                'UIDeviceFamily': [1, 2], 'LSRequiresIPhoneOS': True,
                'NSFaceIDUsageDescription': 'Disposable diagnostic checks biometric availability without requesting authentication.'}
    with (app/'Info.plist').open('wb') as stream:
        plistlib.dump(metadata, stream)
    report['stage'] = 'compile_observer_app'
    built = command(['xcrun', 'swiftc', '-sdk', sdk.stdout.strip(), '-target', architecture+'-apple-ios16.0-simulator',
                     '-framework', 'UIKit', '-framework', 'LocalAuthentication', str(source), '-o', str(app/'BiometryObserver')], timeout=90)
    observation['compileExitCode'] = built.returncode
    observation['buildStatus'] = 'Passed' if built.returncode == 0 else 'Failed-compile'
    if built.returncode:
        observation['compileErrors'] = compiler_errors(built.stderr)
        return None
    return app


def observe_local_authentication(owned, phase, report, minimum_remaining=30):
    observation = report['localAuthenticationObserver']
    entry = observation[phase] = {'status': 'Notexecuted-budget'}
    if remaining_seconds() < minimum_remaining:
        return
    entry['status'] = 'Running-container'
    report['stage'] = 'observer_'+phase+'_container'
    # The measured first container lookup exceeded the old 10-second window
    # after a successful cold install. Keep the overall 390-second clamp.
    try:
        container = command(['xcrun', 'simctl', 'get_app_container', owned, OBSERVER_BUNDLE, 'data'], timeout=30)
    except ProbeTimeout:
        entry['status'] = 'Failed-container-timeout'
        raise
    entry['containerExitCode'] = container.returncode
    if container.returncode:
        entry['status'] = 'Failed-container'
        return
    directory = Path(container.stdout.strip())
    if not directory.is_absolute() or not directory.is_dir():
        entry['status'] = 'Failed-container-path'
        return
    # The only simulator file read is this observer app's own phase-specific
    # output. A pre-existing file is rejected, never accepted as fresh evidence.
    output = directory/'Documents'/('observer-'+phase+'.json')
    if output.exists():
        entry['status'] = 'Failed-stale-output'
        return
    report['stage'] = 'observer_'+phase+'_launch'
    entry['status'] = 'Running-launch'
    try:
        launched = command(['xcrun', 'simctl', 'launch', '--terminate-running-process', owned, OBSERVER_BUNDLE, '--phase', phase], timeout=45)
    except ProbeTimeout:
        entry['status'] = 'Failed-launch-timeout'
        raise
    entry['launchExitCode'] = launched.returncode
    if launched.returncode:
        entry['status'] = 'Failed-launch'
        return
    report['stage'] = 'observer_'+phase+'_readback'
    entry['status'] = 'Running-readback'
    deadline = min(time.monotonic()+10, COMMAND_DEADLINE)
    while not output.is_file() and time.monotonic() < deadline:
        time.sleep(0.2)
    if not output.is_file():
        entry['status'] = 'Failed-output-timeout'
        return
    if output.stat().st_size > 2048:
        entry['status'] = 'Failed-output-size'
        return
    value = json.loads(output.read_text(encoding='utf-8'))
    expected = {'schemaVersion', 'phase', 'policy', 'canEvaluate', 'laErrorCode', 'errorIsLocalAuthentication',
                'biometryType', 'authenticationPromptRequested'}
    if (not isinstance(value, dict) or set(value) != expected or value['schemaVersion'] != 1 or value['phase'] != phase
            or value['policy'] != 1 or value['authenticationPromptRequested'] is not False
            or type(value['canEvaluate']) is not bool or type(value['errorIsLocalAuthentication']) is not bool
            or type(value['laErrorCode']) is not int or type(value['biometryType']) is not int):
        entry['status'] = 'Failed-output-schema'
        return
    entry['status'] = 'Observed'
    entry['result'] = value


def command(argv, timeout=30):
    # Only fixed command/subcommand tokens are published. Paths, device UUIDs
    # and arguments are excluded even from timeout diagnostics.
    allowed = {'--find', 'simctl', 'help', 'swiftc', 'list', 'devices', 'available',
               'create', 'boot', 'bootstatus', 'shutdown', 'delete', '-g', '-b', '-p', '-a',
               'com.apple.systemevents', '--sdk', 'iphonesimulator', 'install', 'launch', 'get_app_container'}
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
              'localAuthenticationObserver': {'buildStatus': 'Notexecuted', 'before': {'status': 'Notexecuted'},
                                              'after': {'status': 'Notexecuted'}, 'evaluatesAuthentication': False},
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
                report['permissionHelperCompileErrors'] = compiler_errors(built.stderr)
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
            observer_app = build_observer(Path(temporary), report)
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
            observer_installed = False
            if observer_app is not None:
                if remaining_seconds() < 125:
                    report['localAuthenticationObserver']['installStatus'] = 'Notexecuted-budget'
                    report['localAuthenticationObserver']['before']['status'] = 'Notexecuted-budget'
                    report['localAuthenticationObserver']['after']['status'] = 'Notexecuted-budget'
                else:
                    report['stage'] = 'install_observer_app'
                    installed = command(['xcrun', 'simctl', 'install', owned, str(observer_app)], timeout=30)
                    report['localAuthenticationObserver']['installExitCode'] = installed.returncode
                    observer_installed = installed.returncode == 0
                    if observer_installed:
                        observe_local_authentication(owned, 'before', report, minimum_remaining=95)
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
            if observer_installed:
                observe_local_authentication(owned, 'after', report)
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
