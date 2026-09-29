import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

source = Path(__file__).with_name('guarded_selection_validator.py')
if not source.is_file():
    source = Path(__file__).with_name('early_passwords_entry_validator.py')
spec = importlib.util.spec_from_file_location('selection_validator', source)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
OWNED = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'


class PostSelectionTests(unittest.TestCase):
    def value(self):
        return dict(selectedRole=9, selectedLabelContainsEmail=True, selectedLabelContainsSite=False,
                    selectedLabelEqualsEmail=False, selectedLabelEqualsSite=False,
                    emailFieldExists=True, emailMatchesExpected=False, emailBlank=True, signupEnabled=False)

    def fixture(self, root, value=None):
        (root/'state.txt').write_text(json.dumps(self.value() if value is None else value), encoding='utf-8')
        item = dict(suggestedHumanReadableName='autofill-native-selection-state.txt', deviceId=OWNED, exportedFileName='state.txt')
        manifest = [dict(testIdentifier=validator.TEST_IDENTIFIER, attachments=[item])]
        (root/'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        return manifest

    def test_exact_fixed_state_exports(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.fixture(root)
            result = validator.export_selection_state(root, OWNED)
            self.assertEqual(result['status'], 'Exported')
            self.assertEqual(result['values'], self.value())

    def test_unknown_values_and_bool_role_rejected(self):
        for value in ({**self.value(), 'credential': 'PRIVATE'}, {**self.value(), 'selectedRole': True},
                      {**self.value(), 'emailBlank': 'false'}, {**self.value(), 'selectedRole': -1}):
            self.assertFalse(validator.valid_selection_state(value))

    def test_wrong_origin_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.fixture(root)
            self.assertEqual(validator.export_selection_state(root, OWNED.replace('AAAA', 'FFFF'))['status'], 'Rejected')

    def test_duplicate_and_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); manifest = self.fixture(root)
            manifest[0]['attachments'] *= 2
            (root/'manifest.json').write_text(json.dumps(manifest))
            self.assertEqual(validator.export_selection_state(root, OWNED)['status'], 'Rejected')
            manifest = self.fixture(root)
            manifest[0]['attachments'][0]['exportedFileName'] = '../state.txt'
            (root/'manifest.json').write_text(json.dumps(manifest))
            self.assertEqual(validator.export_selection_state(root, OWNED)['status'], 'Rejected')

    def test_duplicate_json_key_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.fixture(root)
            (root/'state.txt').write_text('{"selectedRole":9,"selectedRole":50}')
            self.assertEqual(validator.export_selection_state(root, OWNED)['status'], 'Rejected')

    def test_new_phase_allowlist_rejects_other_phase_and_label(self):
        tree = dict(phase='before_selection', newPasswordFormClosed=True, emailBlank=True,
                    snapshotsComplete=True, truncated=False, maskCount=0, nodes=[])
        for phase in ('before_selection', 'after_fill_wait'):
            self.assertTrue(validator.valid_picker_tree({**tree, 'phase': phase}))
        self.assertFalse(validator.valid_picker_tree({**tree, 'phase': 'unknown'}))
        node = dict(surface='app', node=0, parent=-1, role=2, frame=[0, 0, 402, 874], label='PRIVATE', identifier='')
        self.assertFalse(validator.valid_picker_tree({**tree, 'nodes': [node]}))


    def test_query_state_exact_counters(self):
        value = dict(snapshotFailures=0, completeSnapshotsWithoutIdentity=3, identitiesObserved=1)
        self.assertTrue(validator.valid_query_state(value))
        for invalid in ({**value, 'snapshotFailures': True}, {**value, 'identitiesObserved': -1},
                        {**value, 'secret': 'PRIVATE'}, {**value, 'identitiesObserved': 10001}):
            self.assertFalse(validator.valid_query_state(invalid))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); manifest=self.fixture(root, value)
            manifest[0]['attachments'][0]['suggestedHumanReadableName']='autofill-native-picker-query-state.txt'
            (root/'manifest.json').write_text(json.dumps(manifest))
            self.assertEqual(validator.export_query_state(root, OWNED)['values'], value)


if __name__ == '__main__':
    unittest.main()
