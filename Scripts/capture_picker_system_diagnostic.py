"""Seal a disposable Simulator's diagnostic log; never upload plaintext.

The public recipient certificate cannot decrypt the archive. Its matching
one-use private key stays on the review workstation, outside this repository.
Only an explicitly selected saved-picker diagnostic enables this capture.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
device, directory=sys.argv[1:]
private=(root/directory).resolve()
assert private.is_relative_to(root/'PrivateEvidence')
assert re.fullmatch(r'[A-Fa-f0-9-]{36}',device)
assert os.environ.get('NIDAA_UI_SUITE')=='autofill-saved'
output=root/'artifacts/picker-system-diagnostic'
output.mkdir(parents=True,exist_ok=False)
report={'commit':os.environ.get('GITHUB_SHA'),'run':os.environ.get('GITHUB_RUN_ID'),
        'attempt':os.environ.get('GITHUB_RUN_ATTEMPT'),'plaintextUploaded':False,
        'purpose':'Disposable saved-picker transition only; review locally before publishing redacted findings'}
predicate='process CONTAINS[c] "Authentication" OR process CONTAINS[c] "SafariView" OR process == "Passwords" OR process == "NidaaProof" OR eventMessage CONTAINS[c] "credential" OR eventMessage CONTAINS[c] "autofill"'
try:
    result=subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','10m','--style','json','--info','--debug','--predicate',predicate],capture_output=True,timeout=45)
    report['collectionExitCode']=result.returncode
    if result.returncode!=0: raise RuntimeError('collection_failed')
    assert 0<len(result.stdout)<80_000_000
    raw=private/'picker-system-log.json'
    raw.write_bytes(result.stdout)
    cert=root/'QA/NativeReview/diagnostic-recipient-cert.pem'
    openssl=shutil.which('openssl')
    if not openssl: raise RuntimeError('openssl_unavailable')
    sealed=private/'picker-system-log.p7m'
    encrypted=subprocess.run([openssl,'cms','-encrypt','-aes-256-cbc','-binary','-in',str(raw),'-out',str(sealed),'-outform','DER',str(cert)],capture_output=True,timeout=15)
    report['encryptionExitCode']=encrypted.returncode
    if encrypted.returncode!=0 or not sealed.is_file(): raise RuntimeError('encryption_failed')
    target=output/sealed.name
    shutil.copyfile(sealed,target)
    report.update(encrypted=True,encryptedSHA256=hashlib.sha256(target.read_bytes()).hexdigest(),recipientCertificateSHA256=hashlib.sha256(cert.read_bytes()).hexdigest())
except (OSError,subprocess.TimeoutExpired,RuntimeError,AssertionError):
    report['diagnosticIncomplete']=True
(output/'metadata.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'systemDiagnosticEncrypted':report.get('encrypted',False),'plaintextUploaded':False}))
