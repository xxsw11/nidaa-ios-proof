"""Privacy and incomplete-evidence contract for logout navigation telemetry."""
import ast
from contextlib import redirect_stdout
import copy
import io
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class RevealSurfaceSchemaTests(unittest.TestCase):
    def test_complete_partial_and_sensitive_records_are_classified_strictly(self):
        script = ROOT / 'Scripts/export_native_review.py'
        module = ast.parse(script.read_text(encoding='utf-8'))
        functions = [node for node in module.body if isinstance(node, ast.FunctionDef)
                     and node.name in {'valid_reveal_surface', 'reveal_surface_json'}]
        self.assertEqual(len(functions), 2)
        namespace = {'json': json, 'math': math}
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(script), 'exec'), namespace)
        valid, decode = namespace['valid_reveal_surface'], namespace['reveal_surface_json']
        step = {'phase': 'finished', 'completedDrags': 0,
            **{key: True for key in ('appForeground', 'scrollExists', 'windowExists', 'targetExists',
                                    'targetHittable', 'snapshotAvailable', 'snapshotComplete')},
            'truncated': False,
            **{key: [0, 0, 402, 874] for key in ('appFrame', 'windowFrame', 'selectedScrollFrame', 'viewport', 'lastTargetFrame')},
            **{key: [] for key in ('requestedStart', 'requestedEnd', 'actualStart', 'actualEnd')},
            'nodes': [{'node': 0, 'parent': -1, 'role': 2, 'identifier': '', 'frame': [0, 0, 402, 874]}],
            'scrollNodeIndices': []}
        base = {'schemaVersion': 1, 'controlID': 'integrationLogout', 'steps': [step]}
        self.assertTrue(valid(base))
        before = copy.deepcopy(step)
        before.update(phase='before_drag', requestedStart=[201, 673.5], requestedEnd=[201, 272.5],
                      actualStart=[201, 673.5], actualEnd=[201, 272.5])
        checkpoint = {**base, 'steps': [before]}
        self.assertTrue(valid(checkpoint), 'A checkpoint must survive an aborted gesture')
        first_without_snapshot = {**before, 'snapshotAvailable': False, 'snapshotComplete': False,
            'nodes': [], 'appFrame': [], 'windowFrame': [], 'selectedScrollFrame': [],
            'actualStart': [], 'actualEnd': []}
        self.assertTrue(valid({**base, 'steps': [first_without_snapshot]}))
        for completed in (0, 1):
            self.assertTrue(valid({**base, 'steps': [before, {**step, 'completedDrags': completed}]}))
        unknown = {**step, 'snapshotAvailable': False, 'snapshotComplete': False, 'nodes': []}
        self.assertTrue(valid({**base, 'steps': [unknown]}))
        self.assertTrue(valid({**base, 'steps': [{**step, 'snapshotComplete': False, 'truncated': True}]}))
        self.assertTrue(valid({**base, 'steps': [{**before, 'actualStart': [], 'actualEnd': []}]}))
        mutations = [
            lambda v: v.update(secret='PRIVATE_SENTINEL_DO_NOT_EXPORT'),
            lambda v: v['steps'][0].update(value='PRIVATE_SENTINEL_DO_NOT_EXPORT'),
            lambda v: v['steps'][0]['nodes'][0].update(label='PRIVATE_SENTINEL_DO_NOT_EXPORT'),
            lambda v: v['steps'][0]['nodes'][0].update(identifier='PRIVATE_SENTINEL_DO_NOT_EXPORT'),
            lambda v: v['steps'][0]['nodes'][0].update(role=True),
            lambda v: v['steps'][0]['nodes'][0].update(parent=0),
            lambda v: v['steps'][0]['nodes'][0].update(frame=[0, 0, float('nan'), 20]),
            lambda v: v['steps'][0]['nodes'][0].update(frame=[0, 0, -1, 20]),
            lambda v: v['steps'][0]['nodes'][0].update(frame=[10**1000, 0, 1, 20]),
            lambda v: v['steps'][0].update(snapshotAvailable=False),
            lambda v: v['steps'][0].update(snapshotComplete=True, truncated=True),
            lambda v: v['steps'][0].update(scrollNodeIndices=[0, 0]),
            lambda v: v['steps'][0].update(completedDrags=5),
            lambda v: v['steps'][0].update(requestedStart=[1, 2]),
            lambda v: v.update(steps=[]),
            lambda v: v['steps'][0].update(nodes=v['steps'][0]['nodes'] * 2001),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(malformed=index):
                value = copy.deepcopy(base); mutate(value)
                self.assertFalse(valid(value))
                self.assertIsNone(decode(json.dumps(value)))
        deep = copy.deepcopy(base)
        deep['steps'][0]['nodes'] = [{'node': i, 'parent': i - 1, 'role': 2, 'identifier': '', 'frame': [0, 0, 1, 1]} for i in range(51)]
        self.assertFalse(valid(deep))
        self.assertIsNone(decode('{"schemaVersion":1,"schemaVersion":1,"controlID":"integrationLogout","steps":[]}'))
        self.assertIsNone(decode('{broken'))
        # Exercise actual export in reversed attachment order: retain the fullest
        # matching checkpoint, reject arbitrary content, and never infer a pass.
        private_root = ROOT / 'PrivateEvidence'
        private_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='surface-schema-', dir=private_root) as source_dir, tempfile.TemporaryDirectory() as destination:
            private = Path(source_dir)
            screens = private / 'screenshots'; screens.mkdir()
            finished = {**base, 'steps': [before, {**step, 'completedDrags': 1}]}
            unsafe = copy.deepcopy(checkpoint)
            unsafe['steps'][0]['nodes'][0]['label'] = 'PRIVATE_SENTINEL_DO_NOT_EXPORT'
            for name, value in [('finished', finished), ('checkpoint', checkpoint), ('unsafe', unsafe)]:
                (screens / (name + '.txt')).write_text(json.dumps(value), encoding='utf-8')
            (screens / 'manifest.json').write_text(json.dumps([{'attachments': [
                {'suggestedHumanReadableName': 'integration-reveal-surface-state', 'exportedFileName': name + '.txt'}
                for name in ('finished', 'checkpoint', 'unsafe')]}]), encoding='utf-8')
            output = Path(destination) / 'export'
            code = script.read_text(encoding='utf-8').replace("output = root/'artifacts/native-review'/suite", 'output = Path(' + repr(str(output)) + ')')
            class Version:
                stdout = 'Xcode test fixture'
                returncode = 0
            with patch.object(sys, 'argv', [str(script), str(private.relative_to(ROOT)), 'integration', '65']), patch('subprocess.run', return_value=Version()), redirect_stdout(io.StringIO()):
                exec(compile(code, str(script), 'exec'), {'__file__': str(script)})
            raw = (output / 'result.json').read_text(encoding='utf-8')
            exported = json.loads(raw)
            self.assertEqual(exported['revealSurfaceState'], [finished])
            self.assertEqual(exported['revealSurfaceExports'], {'accepted': 2, 'rejected': 1})
            self.assertFalse(exported['debugTestSucceeded'])
            self.assertNotIn('PRIVATE_SENTINEL_DO_NOT_EXPORT', raw)


if __name__ == '__main__':
    unittest.main()
