"""Record and enforce the exact checkout used by each unified regression job."""
import json
import os
from pathlib import Path
import re
import subprocess

actual=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
expected=os.environ['GITHUB_SHA']
assert re.fullmatch('[0-9a-f]{40}',actual) and actual==expected, 'Checkout differs from the workflow source'
record={'commit':actual,'eventCommit':expected,'run':os.environ['GITHUB_RUN_ID'],
        'attempt':os.environ['GITHUB_RUN_ATTEMPT'],'workflow':os.environ['GITHUB_WORKFLOW'],
        'runnerOS':os.environ.get('RUNNER_OS'),'runnerArchitecture':os.environ.get('RUNNER_ARCH')}
target=Path('artifacts/source.json');target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
