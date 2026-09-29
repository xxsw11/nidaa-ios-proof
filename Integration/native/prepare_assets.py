"""Download a pinned official Mailpit release; never execute an installer from the network."""
from pathlib import Path
import hashlib
import json
import platform
import subprocess
import sys
import tarfile
import urllib.request


def download(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'NIDAA-native-private-trial', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def main():
    tools = Path(sys.argv[1]).resolve()
    arch = {'arm64': 'arm64', 'x86_64': 'amd64'}[platform.machine()]
    name = 'mailpit-darwin-' + arch + '.tar.gz'
    # GitHub's official release asset digest, inspected 2026-09-29. This release
    # has no separate checksums file. Pin both supported native architectures.
    expected = {'arm64':'f72ac5bae2c8ef6bd719c1aa11237500e9a81e50ba759f92b9b1e80812920a85',
                'amd64':'ce0c67a2fd1d3ae1a1f6616d8020243b3783d7ef64f4efc0ac40611f4e7aabfe'}[arch]
    data = download('https://github.com/axllent/mailpit/releases/download/v1.31.3/'+name)
    assert hashlib.sha256(data).hexdigest() == expected, 'Mailpit release checksum mismatch'
    archive = tools / name
    archive.write_bytes(data)
    with tarfile.open(archive) as bundle:
        members = [entry for entry in bundle if entry.isfile() and Path(entry.name).name == 'mailpit']
        assert len(members) == 1
        (tools/'mailpit').write_bytes(bundle.extractfile(members[0]).read())
    (tools/'mailpit').chmod(0o700)
    pg = Path((tools/'postgresql-prefix.txt').read_text().strip())/'bin'
    version = lambda argv: subprocess.check_output(argv, text=True).strip()
    evidence = Path('artifacts/native-environment')
    evidence.mkdir(parents=True, exist_ok=True)
    report = {
        'kind': 'Native dependency preparation; not runtime execution',
        'authVersion': 'v2.196.0',
        'authSourceCommit': version(['git', '-C', str(tools/'auth-source'), 'rev-parse', 'HEAD']),
        'authBuildGoToolchain': 'go1.26.5',
        'authBinarySHA256': hashlib.sha256((tools/'auth').read_bytes()).hexdigest(),
        'mailpitVersion': 'v1.31.3', 'mailpitArchiveSHA256': expected,
        'postgresVersion': version([str(pg/'postgres'), '--version']),
        'postgresSelection': 'Homebrew postgresql@17; observed minor recorded, not claimed identical to Docker17.6',
        'architecture': platform.machine(), 'macOS': platform.mac_ver()[0],
    }
    (evidence/'native-prepare.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
