"""Packaging/security boundary checks; Swift and UI behavior are tested by Xcode separately."""
from pathlib import Path
import plistlib
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class NativeStagePackagingTests(unittest.TestCase):
    def test_existing_project_includes_all_app_sources(self):
        p = plistlib.loads((ROOT / 'NidaaProof.xcodeproj/project.pbxproj').read_bytes())
        refs = {v.get('path') for v in p['objects'].values() if v['isa'] == 'PBXFileReference'}
        self.assertTrue(all(f.relative_to(ROOT).as_posix() in refs for f in (ROOT / 'App').rglob('*.swift')))
        self.assertTrue(any(v['isa'] == 'PBXNativeTarget' and v['name'] == 'NidaaUITests' for v in p['objects'].values()))

    def test_notification_and_remote_registration_guarded(self):
        scope = (ROOT / 'App/Services/ExecutionScope.swift').read_text()
        self.assertIn('allowsSystemNotifications = false', scope)
        for file in ['NotificationService.swift', 'RemoteRegistrationService.swift']:
            self.assertIn('guard ExecutionScope.allowsSystemNotifications', (ROOT / 'App/Services' / file).read_text())

    def test_authentication_bypass_only_inside_debug_simulator_compilation(self):
        store = (ROOT / 'App/Experience/ExperienceStore.swift').read_text(encoding='utf-8')
        body = store.split('private func authenticate(', 1)[1]
        guarded = body.split('#if DEBUG && targetEnvironment(simulator)', 1)[1].split('#endif', 1)[0]
        self.assertIn('if simulationAuthentication', guarded)
        self.assertIn('authentication.authenticate', body.split('#endif', 1)[1])

    def test_privacy_manifest_declares_local_preferences(self):
        p = plistlib.loads((ROOT / 'App/PrivacyInfo.xcprivacy').read_bytes())
        self.assertFalse(p['NSPrivacyTracking'])
        self.assertEqual(p['NSPrivacyCollectedDataTypes'], [])
        self.assertEqual(p['NSPrivacyAccessedAPITypes'][0]['NSPrivacyAccessedAPITypeReasons'], ['CA92.1'])

    def test_ui_test_scheme_is_wired(self):
        s = ET.parse(ROOT / 'NidaaProof.xcodeproj/xcshareddata/xcschemes/NidaaProof-Local.xcscheme')
        tests = s.findall('TestAction/Testables/TestableReference/BuildableReference')
        self.assertEqual([x.attrib['BlueprintName'] for x in tests], ['NidaaUITests'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
