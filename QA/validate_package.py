"""Structural checks only. Passing does not establish Swift compilation or iOS behavior."""
from pathlib import Path
import hashlib
import importlib.util
import io
import json
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET
import csv
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
checks = []


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    checks.append({"name": name, "status": "Passed"})


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    project = plistlib.loads((ROOT / "NidaaProof.xcodeproj/project.pbxproj").read_bytes())
    objects = project["objects"]
    check("Project root and object IDs parse as a property list", project["rootObject"] in objects and all(re.fullmatch(r"[A-F0-9]{24}", k) for k in objects))
    singular = ["fileRef", "productRef", "package", "mainGroup", "productRefGroup", "buildConfigurationList", "baseConfigurationReference", "productReference"]
    plural = ["children", "files", "buildConfigurations", "buildPhases", "targets", "packageReferences", "packageProductDependencies", "dependencies", "buildRules"]
    references = [v[key] for v in objects.values() for key in singular if key in v]
    references += [i for v in objects.values() for key in plural if key in v for i in v[key]]
    check("All project object references resolve", all(v in objects for v in references))
    refs = [o for o in objects.values() if o["isa"] == "PBXFileReference" and o.get("sourceTree") == "<group>"]
    check("All referenced source and configuration paths exist", all((ROOT / o["path"]).is_file() for o in refs))
    swift_refs = {o["path"] for o in refs if o["path"].endswith(".swift")}
    swift_actual = {p.relative_to(ROOT).as_posix() for p in (ROOT / "App").rglob("*.swift")}
    check("Every app Swift file is included", swift_refs == swift_actual)
    source_phase = next(o for o in objects.values() if o["isa"] == "PBXSourcesBuildPhase")
    built = {objects[objects[i]["fileRef"]]["path"] for i in source_phase["files"]}
    check("Source build phase matches app sources exactly", built == swift_actual)
    configurations = [o for o in objects.values() if o["isa"] == "XCBuildConfiguration" and "baseConfigurationReference" in o]
    configs = {o["name"]: o["buildSettings"] for o in configurations}
    check("Default Debug and Release have no entitlements or APNs compilation flag", all(configs[n]["CODE_SIGN_ENTITLEMENTS"] == "" and "APNS_ENABLED" not in configs[n]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] for n in ["Debug", "Release"]))
    check("Only APNs-Debug opts into development push", configs["APNs-Debug"]["CODE_SIGN_ENTITLEMENTS"] == "Config/APNs.entitlements" and "APNS_ENABLED" in configs["APNs-Debug"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"])
    ent = plistlib.loads((ROOT / "Config/APNs.entitlements").read_bytes())
    check("Entitlements contain only ordinary development APNs", ent == {"aps-environment": "development"})
    info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    check("Face ID purpose exists and background modes are absent", bool(info.get("NSFaceIDUsageDescription")) and "UIBackgroundModes" not in info)
    base = (ROOT / "Config/Base.xcconfig").read_text(encoding="utf-8")
    check("Signing identifiers are deliberately blank, not invented", bool(re.search(r"^NIDAA_BUNDLE_ID =\s*$", base, re.M)) and bool(re.search(r"^DEVELOPMENT_TEAM =\s*$", base, re.M)) and not (ROOT / "Config/Developer.xcconfig").exists())
    target = next(k for k, v in objects.items() if v["isa"] == "PBXNativeTarget")
    schemes = list((ROOT / "NidaaProof.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"))
    for p in schemes:
        tree = ET.parse(p)
        check(f"{p.stem} scheme resolves target and configuration", all(x.attrib["BlueprintIdentifier"] == target for x in tree.findall(".//BuildableReference")) and tree.find("LaunchAction").attrib["buildConfiguration"] in configs)
    package = (ROOT / "ProofCore/Package.swift").read_text(encoding="utf-8")
    check("Swift package is local without fetched dependencies", '.package(' not in package and (ROOT / "ProofCore/Sources/ProofCore/Evidence.swift").exists())
    app = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "App").rglob("*.swift"))
    check("No critical request, continuous audio, calling or torch API is used", not re.search(r"\.criticalAlert\b|interruptionLevel\s*=\s*\.critical\b|defaultCritical|AVAudioSession|PushKit|CallKit|setTorchMode|AVAudioPlayer", app))
    check("Local request is one-shot with system sound", 'repeats: false' in app and 'content.sound = .default' in app and 'timeInterval: delay' in app)
    check("No embedded private credentials or third-party endpoints in app", not re.search(r"BEGIN (?:EC |RSA )?PRIVATE KEY|https?://|Bearer ", app))
    check("Mac shell scripts use LF line endings", all(b'\r' not in p.read_bytes() for p in (ROOT / "Scripts").glob("*.sh")))
    all_text = [p for p in ROOT.rglob("*") if p.is_file() and p.suffix in [".swift", ".md", ".py", ".json", ".plist", ".xcconfig", ".csv"]]
    banned = re.compile("\u0645\u0631\u0648\u0629|\u0645\u0631\u0648\u0647|m" + "arwah?|m" + "erwah?", re.I)
    check("No previous family name in active proof text", not any(banned.search(p.read_text(encoding="utf-8-sig")) for p in all_text))
    rows = list(csv.DictReader((ROOT / "QA/device-test-matrix.csv").open(encoding="utf-8-sig")))
    check("All nine scenarios exist for local, remote and critical separately", len(rows) == 27 and all(sum(x["notification_type"] == kind for x in rows) == 9 for kind in ["Ordinary local", "Ordinary APNs", "Critical Alert"]))
    check("No physical result is fabricated", all(x["status"] == ("Awaiting approval" if x["notification_type"] == "Critical Alert" else "Not tested") and x["observed_result"] == "No physical-device execution" for x in rows))
    spec = importlib.util.spec_from_file_location("test_payload", ROOT / "QA/test_payload.py")
    tests = importlib.util.module_from_spec(spec);spec.loader.exec_module(tests)
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(tests))
    check("Offline APNs payload behavioral tests pass", result.wasSuccessful() and result.testsRun == 8)
    (ROOT / "QA/python-test-output.txt").write_text(output.getvalue(), encoding="utf-8")
    broken = []
    for p in ROOT.rglob("*.md"):
        for link in re.findall(r"\]\(([^)]+)\)", p.read_text(encoding="utf-8")):
            if "://" in link or link.startswith("#"):
                continue
            destination = (p.parent / link.split("#")[0]).resolve()
            # The report being generated by this run is checked after it is written.
            if not destination.exists() and destination != (ROOT / "QA/windows-checks.json").resolve():
                broken.append(f"{p.relative_to(ROOT)}: {link}")
    check("Documentation local links resolve", not broken)
    swift_tests = (ROOT / "ProofCore/Tests/ProofCoreTests/EvidenceTests.swift").read_text(encoding="utf-8")
    report = {
        "runAt": datetime.now(timezone.utc).isoformat(),
        "environment": "Windows 10.0.19045; Python",
        "structuralChecks": checks,
        "offlinePythonBehavioralTests": {"run": result.testsRun, "passed": result.wasSuccessful()},
        "swiftUnitTests": {"prepared": len(re.findall(r"func test", swift_tests)), "status": "Not tested", "reason": "Swift compiler unavailable"},
        "iOSBuild": "Not tested", "signing": "Not tested", "nativeVisualReview": "Not tested",
        "physicalDeviceTests": "Not tested", "APNs": "Not tested", "criticalAlerts": "Awaiting approval",
        "limits": "Structural validation is not Swift parsing, compilation, SDK linking or runtime verification. Python checks only the offline payload helper."
    }
    (ROOT / "QA/windows-checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"structuralChecksPassed": len(checks), "pythonTestsPassed": result.testsRun, "swiftTestsPreparedNotRun": report["swiftUnitTests"]["prepared"], "iOSBuild": "Not tested"}, indent=2))


if __name__ == "__main__":
    main()
