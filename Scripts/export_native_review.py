"""Allowlist native evidence; never copy raw XCTest logs, recordings or secrets."""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
private, suite, code = sys.argv[1:]
private = (root/private).resolve()
assert private.is_relative_to(root/'PrivateEvidence') and suite in ('integration', 'autofill', 'autofill-saved', 'live')
output = root/'artifacts/native-review'/suite
output.mkdir(parents=True, exist_ok=False)
report = {'suite': suite, 'exitCode': int(code), 'commit': os.environ.get('GITHUB_SHA'),
          'run': os.environ.get('GITHUB_RUN_ID'), 'attempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
          'scope': 'MOCK network with native AutoFill enabled' if suite != 'live' else 'Real native UI/backend; sequential Simulator; simulated local device authentication',
          'rawEvidence': 'Private XCTest logs/xcresult/recordings excluded from publication',
          'physicalDevice': 'Not tested', 'savedCredentialSelection': 'Not tested in this suite'}
summary_path = private/'ui-summary.json'
if summary_path.exists():
    summary = json.loads(summary_path.read_text())
    keys = ['result','totalTestCount','passedTests','failedTests','skippedTests','expectedFailures','startTime','finishTime','devicesAndConfigurations','environmentDescription']
    report['summary'] = {key: summary[key] for key in keys if key in summary}
    # Failure text can contain typed values. Keep only the known test identifier.
    report['failedTestIdentifiers'] = []
    failure_text = []
    for failure in summary.get('testFailures', []):
        identifier = failure.get('testIdentifierString', failure.get('testIdentifier'))
        if isinstance(identifier, str) and re.fullmatch(r'[A-Za-z0-9_./() -]+', identifier):
            report['failedTestIdentifiers'].append(identifier)
        # Use only fixed diagnostic categories below, never arbitrary XCTest text.
        if isinstance(failure.get('failureText'), str):
            failure_text.append(failure['failureText'])
else:
    report['summary'] = {'result': 'Not executed or result bundle unavailable'}
    failure_text = []
log_path = private/'xcode-ui-tests.log'
if not log_path.exists(): log_path=private/'driver-private.log'
logs=log_path.read_text(errors='replace') if log_path.exists() else ''
diagnostics = logs + '\n' + '\n'.join(failure_text)
report['testCaseResults'] = re.findall(r"Test Case '-\[([A-Za-z0-9_.]+) ([A-Za-z0-9_]+)\]' (passed|failed|skipped)", logs)
saved_results = [result for _, name, result in report['testCaseResults'] if name == 'testSavedCredentialSelection']
if suite in ('autofill', 'autofill-saved'):
    report['savedCredentialSelection'] = saved_results[-1] if saved_results else 'Not executed'
report['failureLocations'] = sorted(set(re.findall(r'([A-Za-z0-9_]+\.swift):([0-9]+):(?:[0-9]+:)? error:', logs)))
report['infrastructureSignals'] = {name: pattern.lower() in diagnostics.lower() for name, pattern in {
    'runnerBootstrapFailure':'operation never finished bootstrapping',
    'runnerKilledBeforeTests':'signal kill before starting test execution',
    'runnerEarlyExit':'Early unexpected exit',
    'failedLaunch':'Failed to launch',
    'failedInstall':'Failed to install',
    'testRunnerLost':'Lost connection to the test runner',
    'timedOut':'Timed out',
    'simulatorBootFailure':'Unable to boot device',
    'compileFailure':'** TEST BUILD FAILED **',
    'testFailed':'** TEST FAILED **'}.items()}
# Compiler diagnostics precede runtime and contain public source only; retain
# location/category, not arbitrary quoted values, token-like strings or URLs.
report['compilerDiagnostics'] = [re.sub(r'"[^"\n]*"|\x27[^\x27\n]*\x27', '<quoted source>', line.split('/nidaa-ios-proof/')[-1])
    for line in logs.splitlines() if re.search(r'\.swift:\d+:\d+: error:', line)][:30]
if report['compilerDiagnostics']:
    report['infrastructureSignals']['compileFailure'] = True
release = private/'xcode-release.log'
report['debugTestSucceeded'] = '** TEST SUCCEEDED **' in logs
report['releaseBuildSucceeded'] = release.exists() and '** BUILD SUCCEEDED **' in release.read_text(errors='replace')
for name in ['disposable-simulator.txt','simulator-template.txt','ui-selection.txt']:
    if (private/name).is_file(): shutil.copy2(private/name, output/name)
host = subprocess.run(['xcodebuild','-version'], capture_output=True, text=True)
report['xcode'] = host.stdout.strip()
manifest = private/'screenshots/manifest.json'
images=[]
draft_diagnostics=[]
reveal_diagnostics=[]
reveal_presence=[]
native_form_readiness=[]
# Full-screen diagnostics are accepted only with a matching strict tree report.
picker_diagnostics=[]
picker_images=[]
private_settings_images=[]
picker_labels=set(['', '[redacted]', 'Passwords', 'Password', 'Password AutoFill', 'AutoFill Password', 'Fill Password', 'AutoFill', 'AutoFill…', 'Other Passwords', 'Other Passwords…', 'Open Passwords', 'Search', 'Search Passwords', 'Allow', 'Don’t Allow', "Don't Allow", 'Continue', 'Cancel', 'Done', 'Close', 'Back', 'Save', 'New Password', 'User Name', 'Username', 'Website or Label', 'Website or App', 'Notes', 'All', 'Passkeys', 'Codes', 'Deleted', 'Sign In to iCloud', 'Sign in to your Apple Account', 'Set Up a Passcode', 'Enter iPhone Passcode', 'Use Passcode', 'Face ID', 'Touch ID', 'Authentication Required', 'Unlock Passwords', 'Select All', 'Select', 'Paste', 'Copy', 'Cut', 'كلمات السر', 'كلمات المرور', 'تعبئة كلمات السر', 'تعبئة تلقائية', 'تعبئة تلقائية…', 'كلمات سر أخرى', 'كلمات مرور أخرى', 'بحث', 'إلغاء', 'تم', 'متابعة', 'السماح', 'عدم السماح', 'فتح كلمات السر', 'تسجيل الدخول إلى iCloud', 'إدخال رمز دخول iPhone', 'NIDAA', 'نداء', 'تجربة الربط المحلي', 'MOCK · محاكاة واجهة فقط', 'حساب خيالي مستقل', 'البريد الإلكتروني', 'كلمة المرور', 'تسجيل الدخول', 'إنشاء حساب تجريبي', 'طلب استعادة كلمة المرور', 'لديّ رمز تحقق أو استعادة', 'إغلاق', 'إظهار كلمة المرور', 'إخفاء كلمة المرور', 'الحسابات والنتائج التالية خيالية داخل الواجهة. لا يثبت هذا اختبارًا من المحاكي إلى الخادم.', 'الإرسال مزيف للاختبار · APNs غير مفعّل · لا إشعار أو صوت على هاتف.', 'استخدم بريدًا ينتهي بـ \u200e.invalid. التحقق يصل إلى صندوق محلي معزول؛ لا تستخدم بيانات شخصية.', 'integrationEmail', 'integrationPassword', 'integrationPasswordVisibility', 'integrationPasswordPaste', 'integrationLogin', 'integrationSignup', 'integrationRecover', 'integrationExistingToken', 'integrationKeyboardDone', 'integrationMockBanner'])
picker_phases={'before_tap','after_tap','selection_failure'}
def valid_reveal_presence(value):
    flags={'scrollExists','windowExists','targetExists','appForeground'}
    if not isinstance(value,dict) or set(value)!=flags|{'phase','controlID','completedDrags'}: return False
    # Narrowly retain the observed large-Arabic logout control only.
    if value['phase']!='existence_guard_failed' or value['controlID']!='integrationLogout': return False
    if type(value['completedDrags']) is not int or not 0<=value['completedDrags']<=10: return False
    if not all(type(value[k]) is bool for k in flags): return False
    return not (value['scrollExists'] and value['windowExists'] and value['targetExists'])

def valid_picker_tree(value):
    flags={'newPasswordFormClosed','emailBlank','snapshotsComplete','truncated'}
    if not isinstance(value,dict) or set(value)!=flags|{'phase','maskCount','nodes'}: return False
    if not isinstance(value['phase'],str) or value['phase'] not in picker_phases or not all(type(value[k]) is bool for k in flags): return False
    if type(value['maskCount']) is not int or not 0<=value['maskCount']<=2000: return False
    nodes=value['nodes']
    if not isinstance(nodes,list) or len(nodes)>2000: return False
    for index,node in enumerate(nodes):
        if not isinstance(node,dict) or set(node)!={'surface','node','parent','role','frame','label','identifier'}: return False
        if not isinstance(node['surface'],str) or node['surface'] not in {'app','springboard','passwords'}: return False
        if type(node['node']) is not int or node['node']!=index: return False
        if type(node['parent']) is not int or not -1<=node['parent']<index: return False
        if type(node['role']) is not int or not 0<=node['role']<=1000: return False
        if not all(isinstance(node[k],str) and node[k] in picker_labels for k in ('label','identifier')): return False
        if not isinstance(node['frame'],list) or len(node['frame'])!=4: return False
        if not all(type(v) in (int,float) and math.isfinite(v) and abs(v)<100000 for v in node['frame']): return False
    return True

allowed = {
 'disposable-simulator-autofill-passwords-and-passkeys-on',
 'disposable-simulator-autofill-fixture-failure',
 'autofill-saved-credential-availability-screen',
 'autofill-saved-credential-new-password-controls-header',
 'autofill-noncredential-secure-field-crop',
 'autofill-noncredential-visible-field-crop',
 'autofill-native-empty-identity-fields-crop',
 'autofill-native-picker-header-crop',
 'autofill-native-provider-global-toggle',
 'autofill-native-provider-row',
 'integration-mock-autofill-saved-credential-selected-mock-login',
 'integration-mock-autofill-enabled-registration-complete-mock',
 'integration-mock-autofill-enabled-recovery-complete-mock',
 'integration-mock-autofill-enabled-large-rtl-hidden-demonstration',
 'integration-native-real-native-real-sequential-resolved-after-restart',
}
allowed.update('integration-mock-'+name for name in ['01-auth-rtl','02-awaiting-verification','03-directional-consent','04-explicit-confirmation','05-shared-outgoing','06-unknown-outcome','07-acknowledged-not-responded','08-human-response-keeps-case-open','09-large-arabic-auth','10-large-arabic-consent'])
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for item in test.get('attachments',[]):
            human=item.get('suggestedHumanReadableName','').split('_0_')[0]
            exported=item.get('exportedFileName','')
            source=(private/'screenshots'/exported).resolve()
            assert source.is_relative_to(private/'screenshots')
            if human=='autofill-native-provider-settings-screen' and source.suffix=='.png':
                private_settings_images.append({'name':human+'.png','originalExport':exported,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'redacted':False,'scope':'Disposable Settings fixture; encrypted pending local review'})
            if human=='autofill-native-picker-accessibility-tree' and source.suffix in ('.txt','.text'):
                try: tree=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError,UnicodeError): tree=None
                if valid_picker_tree(tree): picker_diagnostics.append(tree)
            if human.startswith('autofill-native-picker-full-screen-redacted-') and source.suffix=='.png':
                phase=human.removeprefix('autofill-native-picker-full-screen-redacted-').replace('-','_')
                if phase in picker_phases: picker_images.append((phase,human,source,exported))
            if human in allowed and source.suffix=='.png':
                target=output/(human+'.png')
                assert not target.exists(), 'Duplicate named screenshot must be reviewed explicitly'
                shutil.copy2(source,target)
                images.append({'name':target.name,'originalExport':exported,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
            if human=='autofill-saved-credential-availability' and source.suffix in ('.txt','.text'):
                note=source.read_text()
                # Probe text is composed solely of fixed candidate labels in source.
                assert len(note)<1000 and not re.search(r'eyJ|https?://|@',note)
                (output/'saved-credential-availability.txt').write_text(note)
            if human=='autofill-saved-credential-form-controls' and source.suffix in ('.txt','.text'):
                note=source.read_text()
                labels=['Website','User Name','Username','Password','Notes','Save','Done','Cancel','New Password','example.com']
                item=r'(?:textField|secureTextField|button|staticText):(?:'+'|'.join(re.escape(label) for label in labels)+')'
                if re.fullmatch(r'Observed new-password form controls \(no values\): (?:'+item+r'(?:, '+item+r')*)?',note):
                    (output/'saved-credential-form-controls.txt').write_text(note)
            stages = ['passwords-home', 'new-password-form', 'autofill-launch', 'password-picker-launch', 'saved-account-selection', 'saved-account-selection-app', 'saved-account-selection-springboard', 'saved-account-selection-passwords', 'saved-entry-persistence']
            if human in ['autofill-saved-credential-form-controls-'+stage for stage in stages] and source.suffix in ('.txt','.text'):
                stage = human.removeprefix('autofill-saved-credential-form-controls-')
                note = source.read_text(encoding='utf-8')
                labels = ['Website or Label','Website or App','Website','App or Website','User Name','Username','Password','Notes','Save','Done','Cancel','New Password','All','Search','No Passwords','example.com','Passwords','Password AutoFill','AutoFill','Other Passwords','Other Passwords…','كلمات السر','كلمات المرور','تعبئة تلقائية','كلمات سر أخرى']
                item = r'(?:textField|secureTextField|button|staticText):(?:'+'|'.join(re.escape(label) for label in labels)+')'
                if re.fullmatch('stage='+re.escape(stage)+r'; fixed controls \(no values\): (?:'+item+r'(?:, '+item+r')*)?', note):
                    (output/('saved-credential-controls-'+stage+'.txt')).write_text(note, encoding='utf-8')
            if human=='autofill-saved-credential-observed-requirement' and source.suffix in ('.txt','.text'):
                note = source.read_text(encoding='utf-8')
                requirements = ['Sign In to iCloud','Sign in to your Apple Account','Set Up a Passcode','Enter iPhone Passcode','تسجيل الدخول إلى iCloud','إدخال رمز دخول iPhone']
                item = '(?:'+'|'.join(re.escape(label) for label in requirements)+')'
                if re.fullmatch('Observed personal-account/device-passcode requirement: '+item+'(?:, '+item+')*', note):
                    report['savedCredentialRequirement'] = note
            if human=='autofill-native-form-role-geometry' and source.suffix in ('.txt','.text'):
                try:
                    geometry=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError, UnicodeError):
                    geometry=None
                flags={'websiteFound','usernameFound','userLabelFound','passwordLabelFound'}
                if isinstance(geometry,dict) and set(geometry)==flags|{'controls'} and all(type(geometry[k]) is bool for k in flags):
                    controls=geometry['controls']
                    if isinstance(controls,list) and len(controls)<=30 and all(isinstance(c,dict) and set(c)=={'role','frame','hittable'} and c['role'] in ('textField','secureTextField','textView') and type(c['hittable']) is bool and isinstance(c['frame'],list) and len(c['frame'])==4 and all(type(v) in (int,float) and math.isfinite(v) and abs(v)<100000 for v in c['frame']) for c in controls):
                        report['nativeFormRoleGeometry']=geometry
            if human=='autofill-native-form-readiness' and source.suffix in ('.txt','.text'):
                try:
                    readiness=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError, UnicodeError):
                    readiness=None
                flags={'websiteMatches','usernameMatches','passwordFieldFound','passwordFieldHittable','saveEnabled'}
                if isinstance(readiness,dict) and set(readiness)==flags|{'phase'} and readiness['phase'] in ('before_password','after_password') and all(type(readiness[k]) is bool for k in flags):
                    native_form_readiness.append(readiness)
            if human=='autofill-native-picker-state' and source.suffix in ('.txt','.text'):
                try:
                    state=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError, UnicodeError):
                    state=None
                flags={'appForeground','springboardForeground','passwordsForeground','appSavedIdentityVisible','springboardSavedIdentityVisible','passwordsSavedIdentityVisible'}
                if isinstance(state,dict) and set(state)==flags and all(type(state[k]) is bool for k in flags):
                    report['nativePickerState']=state
            if human=='autofill-native-provider-geometry' and source.suffix in ('.txt','.text'):
                try: geometry=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError,UnicodeError): geometry=None
                def frame_valid(frame):
                    return isinstance(frame,list) and len(frame)==4 and all(type(v) in (int,float) and math.isfinite(v) and abs(v)<100000 for v in frame)
                flags={'exists','hittable','selected','runnerContains','windowContains','sizeEligible','valueKnown','enabled'}
                controls={'global_switch','provider_switch','provider_cell','provider_button','provider_text','provider_row_switch'}
                if isinstance(geometry,dict) and set(geometry)=={'runnerFrame','windowFrame','rows'} and all(frame_valid(geometry[k]) for k in ('runnerFrame','windowFrame')):
                    rows=geometry['rows']
                    if isinstance(rows,list) and len(rows)<=6 and all(isinstance(r,dict) and set(r)==flags|{'control','frame'} and r['control'] in controls and frame_valid(r['frame']) and all(type(r[k]) is bool for k in flags) for r in rows):
                        report['nativeProviderGeometry']=geometry
            boolean_diagnostics={
                'autofill-saved-entry-persistence': ('savedEntryPersistence', {'allListOpened','persistedEntryFound','passwordsForeground'}),
                'autofill-native-provider-state': ('nativeProviderState', {'globalEnabledKnown','globalEnabled','providerControlObserved','providerEnabledKnown','providerEnabled'})}
            if human in boolean_diagnostics and source.suffix in ('.txt','.text'):
                try: state=json.loads(source.read_text(encoding='utf-8'))
                except (ValueError,UnicodeError): state=None
                key,flags=boolean_diagnostics[human]
                if isinstance(state,dict) and set(state)==flags and all(type(state[k]) is bool for k in flags):
                    report[key]=state
            if human=='integration-mock-draft-readiness' and source.suffix in ('.txt','.text'):
                # Only fixed UI booleans; never publish arbitrary attachment text.
                note=source.read_text()
                keys=['login_exists','login_enabled','signup_exists','signup_enabled','busy','latinKeys','arabicKeys','strongCover']
                native_keys=['nativeReady','hasText','firstResponder','asciiKeyboard','secure','receivedSeveralEdits','inputEnglish','inputArabic','inputOther','bindingReady']
                pattern=r'(before_keyboard_done|after_keyboard_done): '+', '.join(key+r'=(true|false)' for key in keys)+r', native=\{('+','.join(key+r'=(?:true|false)' for key in native_keys)+r'|unavailable)\}'
                lines=note.strip().splitlines()
                matches=[re.fullmatch(pattern,line) for line in lines]
                if len(matches)==2 and all(matches):
                    phases=[]
                    for match in matches:
                        row=match.groups()
                        native={} if row[-1]=='unavailable' else {key:value=='true' for key,value in (pair.split('=') for pair in row[-1].split(','))}
                        phases.append({'phase':row[0], **{key:value=='true' for key,value in zip(keys,row[1:1+len(keys)])},'native':native})
                    draft_diagnostics.append(phases)
            if human=='integration-reveal-presence' and source.suffix in ('.txt','.text'):
                state=None
                if source.stat().st_size<=2048:
                    try: state=json.loads(source.read_text(encoding='utf-8'))
                    except (ValueError,UnicodeError): pass
                if valid_reveal_presence(state): reveal_presence.append(state)
            if human=='integration-reveal-geometry' and source.suffix in ('.txt','.text'):
                note=source.read_text(encoding='utf-8')
                lines=note.strip().splitlines()
                if 1 <= len(lines) <= 11 and re.fullmatch(r'controlID=integration[A-Za-z]+',lines[0]) and all(re.fullmatch(r'control=[0-9 .(),e+\-inf]+;viewport=[0-9 .(),e+\-inf]+',line) for line in lines[1:]):
                    reveal_diagnostics.append(lines)
for tree in picker_diagnostics:
    target=output/('picker-accessibility-'+tree['phase']+'.json')
    assert not target.exists(), 'Duplicate picker phase requires review'
    target.write_text(json.dumps(tree,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert len(private_settings_images)<=1, 'Duplicate private Settings image requires review'
sealed_images=list(private_settings_images)
for phase,human,source,exported in picker_images:
    matches=[d for d in picker_diagnostics if d['phase']==phase]
    if len(matches)!=1: continue
    tree=matches[0]
    if not (tree['newPasswordFormClosed'] and tree['emailBlank'] and tree['snapshotsComplete'] and not tree['truncated']): continue
    name=human+'.png'
    assert name not in [item['name'] for item in sealed_images], 'Duplicate full-screen diagnostic requires review'
    sealed_images.append({'name':name,'originalExport':exported,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'redacted':True,'tree':'picker-accessibility-'+phase+'.json'})
if sealed_images:
    # Snapshot masks are not atomic with a changing system screen. Seal even
    # redacted full-screen captures; a reviewer must inspect them before reuse.
    archive=private/'picker-screenshots.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as bundle:
        for item in sealed_images:
            bundle.write(private/'screenshots'/item['originalExport'],item['name'])
    encrypted=private/'picker-screenshots.p7m'
    openssl=shutil.which('openssl')
    sealed=False
    if openssl:
        try:
            result=subprocess.run([openssl,'cms','-encrypt','-aes-256-cbc','-binary','-in',str(archive),'-out',str(encrypted),'-outform','DER',str(root/'QA/NativeReview/diagnostic-recipient-cert.pem')],capture_output=True,timeout=15)
            sealed=result.returncode==0 and encrypted.is_file()
        except (OSError,subprocess.TimeoutExpired): pass
    report['pickerScreenshotsEncrypted']=sealed
    if sealed:
        target=output/encrypted.name
        shutil.copy2(encrypted,target)
        report['sealedPickerScreenshots']=sealed_images
        report['sealedPickerArchiveSHA256']=hashlib.sha256(target.read_bytes()).hexdigest()
report['pickerDiagnosticPhases']=[d['phase'] for d in picker_diagnostics]
report['screenshots']=images
report['draftReadiness']=draft_diagnostics
report['revealGeometry']=reveal_diagnostics
report['revealPresence']=reveal_presence
report['nativeFormReadiness']=native_form_readiness
text=json.dumps(report,indent=2)+'\n'
assert not re.search(r'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}|-----BEGIN .*PRIVATE KEY|Native-Fictional-Only', text)
(output/'result.json').write_text(text)
print(json.dumps({'suite':suite,'exitCode':int(code),'summary':report['summary'].get('result'),'safeOriginalScreenshots':len(images)}))
if int(code)==0:
    actual=report['summary']
    assert actual.get('totalTestCount')==({'integration':8,'autofill':4,'autofill-saved':1,'live':2}[suite]), 'No empty or incomplete test selection may pass'
    assert actual.get('failedTests')==0 and report['debugTestSucceeded'] and report['releaseBuildSucceeded']
    if suite in ('autofill', 'autofill-saved'):
        required = {'testEnabledManualRegistrationAndFieldNavigation','testEnabledPasteLoginAndRecovery','testEnabledVisibilityUsesOnlyNonCredentialDemonstration'} if suite == 'autofill' else set()
        outcomes = {name: result for _, name, result in report['testCaseResults']}
        assert all(outcomes.get(name) == 'passed' for name in required)
        if report['savedCredentialSelection'] == 'passed':
            assert actual.get('passedTests') == len(required)+1 and actual.get('skippedTests') == 0
        else:
            assert report['savedCredentialSelection'] == 'skipped' and report.get('savedCredentialRequirement')
            assert actual.get('passedTests') == len(required) and actual.get('skippedTests') == 1
            raise AssertionError('Observed requirement is recorded as skipped; saved selection acceptance gate remains unpassed')
    else:
        assert actual.get('passedTests') == {'integration':8,'live':2}[suite]
        assert actual.get('skippedTests') == 0
