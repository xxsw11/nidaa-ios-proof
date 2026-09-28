"""NIDAA-scoped Docker Compose lifecycle. Does not prune or touch other projects."""
import argparse
import base64
import json
import os
import re
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
ENV = ROOT / '.runtime.env'
COMPOSE = ['docker', 'compose', '--project-name', 'nidaa-integration', '--env-file', str(ENV), '-f', str(ROOT / 'compose.yml')]


def run(*args, capture=False):
    return subprocess.run(COMPOSE + list(args), check=True, text=True, capture_output=capture)


def initialize():
    if ENV.exists():
        return
    import jwt
    secret = secrets.token_hex(32)
    values = {name: secrets.token_hex(24) for name in ['DB_PASSWORD', 'AUTH_DB_PASSWORD', 'SERVICE_DB_PASSWORD', 'RELAY_CONTROL_KEY']}
    values.update(JWT_SECRET=secret, RECEIPT_KEY=base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())
    values['AUTH_ADMIN_TOKEN'] = jwt.encode({'role': 'service_role', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + 86400 * 7}, secret, algorithm='HS256')
    ENV.write_text(''.join(f'{k}={v}\n' for k, v in values.items()), encoding='utf-8')
    if os.name != 'nt':
        ENV.chmod(0o600)
    print('Created ephemeral local credentials (not displayed).')


def check_ports():
    if run('ps', '-q', capture=True).stdout.strip():
        return
    for port in (55421, 55424):
        with socket.socket() as sock:
            try:
                sock.bind(('127.0.0.1', port))
            except OSError:
                raise SystemExit(f'NIDAA port {port} is occupied; no existing service was changed.')


def relay_control(method='GET'):
    values = dict(line.split('=',1) for line in ENV.read_text().splitlines() if '=' in line)
    req = urllib.request.Request('http://127.0.0.1:55421/__nidaa_relay', method=method,
                                 headers={'X-Nidaa-Control':values['RELAY_CONTROL_KEY']})
    with urllib.request.urlopen(req,timeout=5) as result:
        assert result.status == 204


def start_relay():
    try:
        relay_control()
        return
    except Exception:
        pass
    options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {'start_new_session': True}
    subprocess.Popen([sys.executable,str(ROOT/'loopback.py')], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,**options)


def stop_relay():
    try:
        relay_control('DELETE')
    except Exception:
        pass


def health():
    relay_control()
    for path in ('/auth/v1/health', '/health'):
        with urllib.request.urlopen('http://127.0.0.1:55421' + path, timeout=5) as response:
            assert response.status == 200
    ids = run('ps', '-q', capture=True).stdout.split()
    for cid in ids:
        row = json.loads(subprocess.check_output(['docker', 'inspect', cid]))[0]
        for bindings in row['NetworkSettings']['Ports'].values():
            for binding in bindings or []:
                assert binding['HostIp'] == '127.0.0.1', 'Non-loopback publication detected'
        for net in row['NetworkSettings']['Networks']:
            network = json.loads(subprocess.check_output(['docker', 'network', 'inspect', net]))[0]
            assert network['Internal'] is True, 'Egress network detected'
    print('Auth + domain health passed through loopback relay; no Docker published ports; all runtime networks internal.')


def diagnostics():
    # Startup diagnostics only; never export Auth/mail/DB logs or container environment.
    secrets_to_redact = [line.split('=', 1)[1] for line in ENV.read_text().splitlines() if '=' in line]
    for name in ('service', 'gateway'):
        ids = run('ps', '--all', '-q', name, capture=True).stdout.split()
        for cid in ids:
            row = json.loads(subprocess.check_output(['docker', 'inspect', cid]))[0]
            print(json.dumps({'service': name, 'state': row['State']['Status'], 'exit': row['State']['ExitCode'], 'ports': row['NetworkSettings']['Ports']}))
        probe = subprocess.run(COMPOSE + ['exec', '-T', name, 'python', '-c',
            "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:" + ('8000' if name == 'service' else '8080') + "/health',timeout=3).status)"], text=True, capture_output=True)
        print(json.dumps({'service': name, 'internal_health_exit': probe.returncode, 'internal_health_ok': probe.stdout.strip() == '200'}))
        output = subprocess.run(COMPOSE + ['logs', '--no-color', '--tail', '45', name], text=True, capture_output=True).stdout
        for secret in secrets_to_redact:
            if secret:
                output = output.replace(secret, '[redacted]')
        output = re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[redacted-token]', output)
        output = re.sub(r'[\w.+-]+@[\w.-]+', '[redacted-address]', output)
        print(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'health', 'stop', 'reset', 'test', 'swift-test', 'worker', 'versions'])
    parser.add_argument('--confirm-nidaa-reset', action='store_true')
    args = parser.parse_args()
    if not shutil.which('docker'):
        raise SystemExit('Docker-compatible CLI/runtime unavailable. Use the container-capable CI trial; no local execution claimed.')
    if args.action == 'versions':
        subprocess.run(['docker', 'version', '--format', '{{.Server.Version}}'], check=True)
        subprocess.run(['docker', 'compose', 'version'], check=True)
        print('Supabase CLI:', shutil.which('supabase') or 'not installed; pinned Auth containers used directly')
        return
    if args.action in ('stop', 'reset') and not ENV.exists():
        print('No generated NIDAA runtime credentials; no trial resources changed.')
        return
    initialize()
    if args.action == 'start':
        check_ports()
        run('build')
        run('up', '-d', '--wait', 'db', 'mail', 'auth')
        run('run', '--rm', 'bootstrap')
        run('up', '-d', 'service', 'gateway')
        start_relay()
        for attempt in range(30):
            try:
                health()
                break
            except Exception:
                if attempt == 29:
                    diagnostics()
                    raise SystemExit('NIDAA startup health failed; inspect local service errors without exporting secrets.')
                time.sleep(2)
    elif args.action == 'health':
        health()
    elif args.action == 'stop':
        stop_relay()
        run('down')
    elif args.action == 'reset':
        if not args.confirm_nidaa_reset:
            raise SystemExit('Reset deletes ONLY the nidaa-integration trial volume. Re-run with --confirm-nidaa-reset.')
        stop_relay()
        run('down', '--volumes')
        ENV.unlink(missing_ok=True)
    elif args.action == 'test':
        run('run', '--rm', 'tests', 'python', '-m', 'Integration.diagnose')
        run('run', '--rm', 'tests')
    elif args.action == 'worker':
        run('run', '--rm', 'worker')
    elif args.action == 'swift-test':
        run('build', 'swift-trial')
        evidence = ROOT.parent / 'artifacts'
        evidence.mkdir(exist_ok=True)
        for name in ('unit-tests.log', 'swift-version.txt', 'Package.resolved'):
            output = run('run', '--rm', 'swift-trial', 'cat', '/swifttrial/' + name, capture=True).stdout
            (evidence / ('swift-' + name)).write_text(output, encoding='utf-8')
        run('run', '--rm', 'swift-trial')


if __name__ == '__main__':
    main()
