"""Allowlist native evidence; never copy raw XCTest logs, recordings or secrets."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
private, suite, code = sys.argv[1:]
private = (root/private).resolve()
assert private.is_relative_to(root/'PrivateEvidence') and suite in ('integration', 'autofill', 'live')
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
if suite == 'autofill':
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
allowed = {
 'disposable-simulator-autofill-passwords-and-passkeys-on',
 'disposable-simulator-autofill-fixture-failure',
 'autofill-saved-credential-availability-screen',
 'autofill-saved-credential-new-password-controls-header',
 'autofill-noncredential-secure-field-crop',
 'autofill-noncredential-visible-field-crop',
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
            stages = ['passwords-home', 'new-password-form', 'autofill-launch', 'password-picker-launch', 'saved-account-selection']
            if human in ['autofill-saved-credential-form-controls-'+stage for stage in stages] and source.suffix in ('.txt','.text'):
                stage = human.removeprefix('autofill-saved-credential-form-controls-')
                note = source.read_text(encoding='utf-8')
                labels = ['Website or App','Website','App or Website','User Name','Username','Password','Notes','Save','Done','Cancel','New Password','example.com','Passwords','Password AutoFill','AutoFill','Other Passwords','Other Passwords…','كلمات السر','كلمات المرور','تعبئة تلقائية','كلمات سر أخرى']
                item = r'(?:textField|secureTextField|button|staticText):(?:'+'|'.join(re.escape(label) for label in labels)+')'
                if re.fullmatch('stage='+re.escape(stage)+r'; fixed controls \(no values\): (?:'+item+r'(?:, '+item+r')*)?', note):
                    (output/('saved-credential-controls-'+stage+'.txt')).write_text(note, encoding='utf-8')
            if human=='autofill-saved-credential-observed-requirement' and source.suffix in ('.txt','.text'):
                note = source.read_text(encoding='utf-8')
                requirements = ['Sign In to iCloud','Sign in to your Apple Account','Set Up a Passcode','Enter iPhone Passcode','تسجيل الدخول إلى iCloud','إدخال رمز دخول iPhone']
                item = '(?:'+'|'.join(re.escape(label) for label in requirements)+')'
                if re.fullmatch('Observed personal-account/device-passcode requirement: '+item+'(?:, '+item+')*', note):
                    report['savedCredentialRequirement'] = note
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
            if human=='integration-reveal-geometry' and source.suffix in ('.txt','.text'):
                note=source.read_text(encoding='utf-8')
                lines=note.strip().splitlines()
                if 1 <= len(lines) <= 11 and re.fullmatch(r'controlID=integration[A-Za-z]+',lines[0]) and all(re.fullmatch(r'control=[0-9 .(),e+\-inf]+;viewport=[0-9 .(),e+\-inf]+',line) for line in lines[1:]):
                    reveal_diagnostics.append(lines)
report['screenshots']=images
report['draftReadiness']=draft_diagnostics
report['revealGeometry']=reveal_diagnostics
text=json.dumps(report,indent=2)+'\n'
assert not re.search(r'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}|-----BEGIN .*PRIVATE KEY|Native-Fictional-Only', text)
(output/'result.json').write_text(text)
print(json.dumps({'suite':suite,'exitCode':int(code),'summary':report['summary'].get('result'),'safeOriginalScreenshots':len(images)}))
if int(code)==0:
    actual=report['summary']
    assert actual.get('totalTestCount')==({'integration':8,'autofill':4,'live':2}[suite]), 'No empty or incomplete test selection may pass'
    assert actual.get('failedTests')==0 and report['debugTestSucceeded'] and report['releaseBuildSucceeded']
    if suite == 'autofill':
        required = {'testEnabledManualRegistrationAndFieldNavigation','testEnabledPasteLoginAndRecovery','testEnabledVisibilityUsesOnlyNonCredentialDemonstration'}
        outcomes = {name: result for _, name, result in report['testCaseResults']}
        assert all(outcomes.get(name) == 'passed' for name in required)
        if report['savedCredentialSelection'] == 'passed':
            assert actual.get('passedTests') == 4 and actual.get('skippedTests') == 0
        else:
            assert report['savedCredentialSelection'] == 'skipped' and report.get('savedCredentialRequirement')
            assert actual.get('passedTests') == 3 and actual.get('skippedTests') == 1
    else:
        assert actual.get('passedTests') == {'integration':8,'live':2}[suite]
        assert actual.get('skippedTests') == 0
