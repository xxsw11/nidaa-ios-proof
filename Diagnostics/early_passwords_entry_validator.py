"""Diagnostic-only fixed-schema AX export. Never exports images, logs or archives."""
from pathlib import Path
import json
import math
import re

# Replaced during preparation with the exact literal whitelist from the latest
# reveal diagnostic exporter (published diagnostic source 854), not UI content.
PICKER_LABELS = frozenset(['', '[redacted]', 'Passwords', 'Password', 'Password AutoFill', 'AutoFill Password', 'Fill Password', 'AutoFill', 'AutoFill…', 'Other Passwords', 'Other Passwords…', 'Open Passwords', 'Search', 'Search Passwords', 'Allow', 'Don’t Allow', "Don't Allow", 'Continue', 'Cancel', 'Done', 'Close', 'Back', 'Save', 'New Password', 'User Name', 'Username', 'Website or Label', 'Website or App', 'Notes', 'All', 'Passkeys', 'Codes', 'Deleted', 'Sign In to iCloud', 'Sign in to your Apple Account', 'Set Up a Passcode', 'Enter iPhone Passcode', 'Use Passcode', 'Face ID', 'Touch ID', 'Authentication Required', 'Unlock Passwords', 'Select All', 'Select', 'Paste', 'Copy', 'Cut', 'كلمات السر', 'كلمات المرور', 'تعبئة كلمات السر', 'تعبئة تلقائية', 'تعبئة تلقائية…', 'كلمات سر أخرى', 'كلمات مرور أخرى', 'بحث', 'إلغاء', 'تم', 'متابعة', 'السماح', 'عدم السماح', 'فتح كلمات السر', 'تسجيل الدخول إلى iCloud', 'إدخال رمز دخول iPhone', 'NIDAA', 'نداء', 'تجربة الربط المحلي', 'MOCK · محاكاة واجهة فقط', 'حساب خيالي مستقل', 'البريد الإلكتروني', 'كلمة المرور', 'تسجيل الدخول', 'إنشاء حساب تجريبي', 'طلب استعادة كلمة المرور', 'لديّ رمز تحقق أو استعادة', 'إغلاق', 'إظهار كلمة المرور', 'إخفاء كلمة المرور', 'الحسابات والنتائج التالية خيالية داخل الواجهة. لا يثبت هذا اختبارًا من المحاكي إلى الخادم.', 'الإرسال مزيف للاختبار · APNs غير مفعّل · لا إشعار أو صوت على هاتف.', 'استخدم بريدًا ينتهي بـ \u200e.invalid. التحقق يصل إلى صندوق محلي معزول؛ لا تستخدم بيانات شخصية.', 'integrationEmail', 'integrationPassword', 'integrationPasswordVisibility', 'integrationPasswordPaste', 'integrationLogin', 'integrationSignup', 'integrationRecover', 'integrationExistingToken', 'integrationKeyboardDone', 'integrationMockBanner'])
ATTACHMENT_NAME = 'autofill-passwords-entry-accessibility-tree'
TEST_IDENTIFIER = 'AutoFillUITests/testSavedCredentialSelection()'


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def valid_early_passwords_tree(value):
    flags = {'passwordsForeground', 'springboardForeground', 'snapshotsComplete', 'truncated'}
    if not isinstance(value, dict) or set(value) != flags | {'phase', 'nodes'}:
        return False
    if value['phase'] != 'passwords_entry_after_onboarding' or not all(type(value[k]) is bool for k in flags):
        return False
    if value['snapshotsComplete'] is not True or value['truncated'] is not False:
        return False
    nodes = value['nodes']
    if not isinstance(nodes, list) or not 2 <= len(nodes) <= 2000:
        return False
    roots = set()
    for index, node in enumerate(nodes):
        if not isinstance(node, dict) or set(node) != {'surface', 'node', 'parent', 'role', 'frame', 'label', 'identifier'}:
            return False
        if not isinstance(node['surface'], str) or node['surface'] not in {'passwords', 'springboard'}:
            return False
        if type(node['node']) is not int or node['node'] != index:
            return False
        parent = node['parent']
        if type(parent) is not int or not -1 <= parent < index:
            return False
        if type(node['role']) is not int or not 0 <= node['role'] <= 1000:
            return False
        if not all(isinstance(node[k], str) and node[k] in PICKER_LABELS for k in ('label', 'identifier')):
            return False
        frame = node['frame']
        if not isinstance(frame, list) or len(frame) != 4:
            return False
        if not all(type(v) in (int, float) and math.isfinite(v) and abs(v) < 100000 for v in frame):
            return False
        if frame[2] < 0 or frame[3] < 0:
            return False
        if parent == -1:
            if node['surface'] in roots or node['role'] != 2:
                return False
            roots.add(node['surface'])
        elif nodes[parent]['surface'] != node['surface']:
            return False
    return roots == {'passwords', 'springboard'}


def export_early_passwords_entry(attachment_directory, output_file, owned_udid):
    """Return fixed status/reason only; exact owned-test manifest selects the input."""
    directory = Path(attachment_directory).resolve()
    output = Path(output_file)
    if output.name != 'early-passwords-entry.json' or output.exists():
        return {'status': 'Rejected', 'reason': 'output-target'}
    if not isinstance(owned_udid, str) or not re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', owned_udid):
        return {'status': 'Rejected', 'reason': 'owned-device'}
    try:
        manifest_path = directory / 'manifest.json'
        if not manifest_path.is_file():
            return {'status': 'Unavailable', 'reason': 'manifest-missing'}
        if manifest_path.stat().st_size > 1024 * 1024:
            return {'status': 'Rejected', 'reason': 'manifest-size'}
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
        if not isinstance(manifest, list):
            return {'status': 'Rejected', 'reason': 'manifest-schema'}
        pattern = re.escape(ATTACHMENT_NAME) + r'(?:_0_[0-9A-Fa-f-]{36})?(?:\.txt|\.text)?'
        candidates = []
        for test in manifest:
            if not isinstance(test, dict):
                return {'status': 'Rejected', 'reason': 'manifest-schema'}
            for item in test.get('attachments', []):
                if not isinstance(item, dict):
                    return {'status': 'Rejected', 'reason': 'manifest-schema'}
                human = item.get('suggestedHumanReadableName', '')
                if not isinstance(human, str) or not re.fullmatch(pattern, human):
                    continue
                if test.get('testIdentifier') != TEST_IDENTIFIER or item.get('deviceId') != owned_udid:
                    return {'status': 'Rejected', 'reason': 'attachment-origin'}
                exported = item.get('exportedFileName')
                if not isinstance(exported, str) or Path(exported).name != exported:
                    return {'status': 'Rejected', 'reason': 'attachment-path'}
                source = (directory / exported).resolve()
                if source.parent != directory or source.suffix not in ('.txt', '.text'):
                    return {'status': 'Rejected', 'reason': 'attachment-path'}
                candidates.append(source)
        if len(candidates) != 1:
            return {'status': 'Unavailable' if not candidates else 'Rejected', 'reason': 'attachment-count'}
        source = candidates[0]
        if source.stat().st_size > 1024 * 1024:
            return {'status': 'Rejected', 'reason': 'attachment-size'}
        tree = json.loads(source.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
        if not valid_early_passwords_tree(tree):
            return {'status': 'Rejected', 'reason': 'tree-schema'}
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('x', encoding='utf-8') as stream:
            stream.write(json.dumps(tree, ensure_ascii=False, indent=2) + '\n')
        return {'status': 'Exported', 'reason': 'validated-fixed-schema'}
    except (OSError, ValueError, TypeError, UnicodeError):
        # No exception text, source fragments, raw labels, IDs or paths escape.
        return {'status': 'Rejected', 'reason': 'read-or-schema'}


PICKER_PHASES = {'before_tap', 'after_tap', 'selection_failure', 'before_selection', 'after_fill_wait'}
PICKER_LABELS = PICKER_LABELS | {'Use Password', 'Use This Password', 'استخدام كلمة السر', 'استخدام كلمة المرور', 'استخدام كلمة السر هذه', 'استخدام كلمة المرور هذه', 'تعبئة كلمة السر', 'تعبئة كلمة المرور'}


def valid_picker_tree(value):
    flags = {'newPasswordFormClosed', 'emailBlank', 'snapshotsComplete', 'truncated'}
    if not isinstance(value, dict) or set(value) != flags | {'phase', 'maskCount', 'nodes'}:
        return False
    if not isinstance(value['phase'], str) or value['phase'] not in PICKER_PHASES:
        return False
    if not all(type(value[k]) is bool for k in flags):
        return False
    if type(value['maskCount']) is not int or not 0 <= value['maskCount'] <= 2000:
        return False
    nodes = value['nodes']
    if not isinstance(nodes, list) or len(nodes) > 2000:
        return False
    for index, node in enumerate(nodes):
        if not isinstance(node, dict) or set(node) != {'surface', 'node', 'parent', 'role', 'frame', 'label', 'identifier'}:
            return False
        if not isinstance(node['surface'], str) or node['surface'] not in {'app', 'springboard', 'passwords'}:
            return False
        if type(node['node']) is not int or node['node'] != index:
            return False
        if type(node['parent']) is not int or not -1 <= node['parent'] < index:
            return False
        if node['parent'] >= 0 and nodes[node['parent']]['surface'] != node['surface']:
            return False
        if type(node['role']) is not int or not 0 <= node['role'] <= 1000:
            return False
        if not all(isinstance(node[k], str) and node[k] in PICKER_LABELS for k in ('label', 'identifier')):
            return False
        frame = node['frame']
        if not isinstance(frame, list) or len(frame) != 4:
            return False
        if not all(type(v) in (int, float) and math.isfinite(v) and abs(v) < 100000 for v in frame):
            return False
        if frame[2] < 0 or frame[3] < 0:
            return False
    return True


def export_picker_trees(attachment_directory, output_directory, owned_udid):
    """Export at most five fixed-name, schema-validated JSON trees; no images."""
    report = {'status': 'Unavailable', 'reason': 'attachment-count',
              'before_tap': False, 'after_tap': False, 'selection_failure': False}
    directory = Path(attachment_directory).resolve()
    if not isinstance(owned_udid, str) or not re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', owned_udid):
        report.update(status='Rejected', reason='owned-device'); return report
    try:
        manifest_path = directory / 'manifest.json'
        if not manifest_path.is_file():
            report['reason'] = 'manifest-missing'; return report
        if manifest_path.stat().st_size > 1024 * 1024:
            report.update(status='Rejected', reason='manifest-size'); return report
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
        if not isinstance(manifest, list):
            report.update(status='Rejected', reason='manifest-schema'); return report
        pattern = r'autofill-native-picker-accessibility-tree(?:_0_[0-9A-Fa-f-]{36})?(?:\.txt|\.text)?'
        trees = {}
        for test in manifest:
            if not isinstance(test, dict) or not isinstance(test.get('attachments', []), list):
                report.update(status='Rejected', reason='manifest-schema'); return report
            for item in test.get('attachments', []):
                if not isinstance(item, dict):
                    report.update(status='Rejected', reason='manifest-schema'); return report
                human = item.get('suggestedHumanReadableName', '')
                if not isinstance(human, str) or not re.fullmatch(pattern, human):
                    continue
                if test.get('testIdentifier') != TEST_IDENTIFIER or item.get('deviceId') != owned_udid:
                    report.update(status='Rejected', reason='attachment-origin'); return report
                exported = item.get('exportedFileName')
                if not isinstance(exported, str) or Path(exported).name != exported:
                    report.update(status='Rejected', reason='attachment-path'); return report
                source = (directory / exported).resolve()
                if source.parent != directory or source.suffix not in ('.txt', '.text'):
                    report.update(status='Rejected', reason='attachment-path'); return report
                if source.stat().st_size > 1024 * 1024:
                    report.update(status='Rejected', reason='attachment-size'); return report
                tree = json.loads(source.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
                if not valid_picker_tree(tree):
                    report.update(status='Rejected', reason='tree-schema'); return report
                if tree['phase'] in trees:
                    report.update(status='Rejected', reason='duplicate-phase'); return report
                trees[tree['phase']] = tree
        if not trees:
            return report
        output = Path(output_directory)
        if any((output / ('picker-accessibility-' + phase + '.json')).exists() for phase in trees):
            report.update(status='Rejected', reason='output-target'); return report
        output.mkdir(parents=True, exist_ok=True)
        for phase, tree in trees.items():
            with (output / ('picker-accessibility-' + phase + '.json')).open('x', encoding='utf-8') as stream:
                stream.write(json.dumps(tree, ensure_ascii=False, indent=2) + '\n')
            report[phase] = True
        report.update(status='Exported', reason='validated-fixed-schema')
        return report
    except (OSError, ValueError, TypeError, UnicodeError):
        report.update(status='Rejected', reason='read-or-schema'); return report


def valid_selection_state(value):
    flags = {'selectedLabelContainsEmail', 'selectedLabelContainsSite', 'selectedLabelEqualsEmail',
             'selectedLabelEqualsSite', 'emailFieldExists', 'emailMatchesExpected', 'emailBlank', 'signupEnabled'}
    return (isinstance(value, dict) and set(value) == flags | {'selectedRole'}
            and type(value['selectedRole']) is int and 0 <= value['selectedRole'] <= 1000
            and all(type(value[key]) is bool for key in flags))


def export_selection_state(attachment_directory, owned_udid):
    """Return only validated fixed booleans/role from the exact owned XCTest."""
    rejected = {'status': 'Rejected', 'reason': 'origin-or-schema'}
    if not isinstance(owned_udid, str) or not re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', owned_udid):
        return rejected
    try:
        directory = Path(attachment_directory).resolve()
        manifest_path = directory / 'manifest.json'
        if not manifest_path.is_file():
            return {'status': 'Unavailable', 'reason': 'manifest-missing'}
        if manifest_path.stat().st_size > 1024 * 1024:
            return rejected
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
        if not isinstance(manifest, list):
            return rejected
        pattern = r'autofill-native-selection-state(?:_0_[0-9A-Fa-f-]{36})?(?:\.txt|\.text)?'
        candidates = []
        for test in manifest:
            if not isinstance(test, dict) or not isinstance(test.get('attachments', []), list):
                return rejected
            for item in test.get('attachments', []):
                if not isinstance(item, dict):
                    return rejected
                human = item.get('suggestedHumanReadableName', '')
                if not isinstance(human, str) or not re.fullmatch(pattern, human):
                    continue
                if test.get('testIdentifier') != TEST_IDENTIFIER or item.get('deviceId') != owned_udid:
                    return rejected
                exported = item.get('exportedFileName')
                if not isinstance(exported, str) or Path(exported).name != exported:
                    return rejected
                source = (directory / exported).resolve()
                if source.parent != directory or source.suffix not in ('.txt', '.text') or source.stat().st_size > 4096:
                    return rejected
                value = json.loads(source.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
                if not valid_selection_state(value):
                    return rejected
                candidates.append(value)
        if not candidates:
            return {'status': 'Unavailable', 'reason': 'attachment-missing'}
        if len(candidates) != 1:
            return rejected
        return {'status': 'Exported', 'reason': 'validated-fixed-schema', 'values': candidates[0]}
    except (OSError, ValueError, TypeError, UnicodeError):
        return rejected
