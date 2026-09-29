"""One bounded precredential policy experiment; no backend or runtime fallback.

Run the controller outside Seatbelt. It launches only this fixed socket probe
under the candidate and the deny-all control. No credentials or payloads are
read/sent. Network failure without EPERM/EACCES is never counted as isolation.
"""
import argparse
import ctypes
import errno
import hashlib
import json
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FAMILIES = {'IPv4': (socket.AF_INET, '127.0.0.1', '0.0.0.0', '192.0.2.1'),
            'IPv6': (socket.AF_INET6, '::1', '::', '2001:db8::1')}


def attempt(family, kind, action):
    stage = 'create'
    try:
        with socket.socket(family, kind) as sock:
            sock.settimeout(1)
            stage = 'operation'
            action(sock)
    except OSError as error:
        return {'status': 'policy_denied' if error.errno in (errno.EPERM, errno.EACCES) else 'other_error',
                'errno': error.errno, 'stage': stage}
    return {'status': 'succeeded', 'errno': None, 'stage': stage}


def loopback_tcp(sock, host):
    sock.bind((host, 0))
    sock.listen(1)
    with socket.socket(sock.family, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(sock.getsockname())
        connection, _ = sock.accept()
        connection.close()


def loopback_udp(sock, host):
    sock.bind((host, 0))
    with socket.socket(sock.family, socket.SOCK_DGRAM) as client:
        client.settimeout(1)
        client.sendto(b'', sock.getsockname())
        sock.recvfrom(1)


def wildcard(family, host):
    state = {'bind': {'status': 'not_attempted'}, 'listen': {'status': 'not_attempted'}}
    def action(sock):
        try:
            sock.bind((host, 0))
        except OSError as error:
            state['bind'] = {'status': 'policy_denied' if error.errno in (errno.EPERM, errno.EACCES) else 'other_error', 'errno': error.errno}
            return
        state['bind'] = {'status': 'succeeded', 'errno': None}
        try:
            sock.listen(1)
        except OSError as error:
            state['listen'] = {'status': 'policy_denied' if error.errno in (errno.EPERM, errno.EACCES) else 'other_error', 'errno': error.errno}
        else:
            state['listen'] = {'status': 'succeeded', 'errno': None}
        # The enclosing context closes immediately. Never accepts a peer.
    state['socket'] = attempt(family, socket.SOCK_STREAM, action)
    return state


def probe():
    values = {}
    for name, (family, local, any_host, external) in FAMILIES.items():
        values[name] = {
            'externalTCP': attempt(family, socket.SOCK_STREAM, lambda s: s.connect((external, 9))),
            'externalUDP': attempt(family, socket.SOCK_DGRAM, lambda s: s.sendto(b'', (external, 9))),
            'wildcardTCP': wildcard(family, any_host),
            'wildcardUDPBind': attempt(family, socket.SOCK_DGRAM, lambda s: s.bind((any_host, 0))),
            # listen() can implicitly bind an unbound socket. Test this path too.
            'implicitWildcardListen': attempt(family, socket.SOCK_STREAM, lambda s: s.listen(1)),
            'loopbackTCP': attempt(family, socket.SOCK_STREAM, lambda s: loopback_tcp(s, local)),
            'loopbackUDP': attempt(family, socket.SOCK_DGRAM, lambda s: loopback_udp(s, local)),
        }
    return values


def passed(values, control=False):
    if set(values) != set(FAMILIES):
        return False
    for item in values.values():
        for key in ('externalTCP', 'externalUDP', 'wildcardUDPBind', 'implicitWildcardListen'):
            if item[key]['status'] != 'policy_denied' or item[key]['stage'] != 'operation':
                return False
        if item['wildcardTCP']['bind']['status'] != 'policy_denied':
            return False
        if item['wildcardTCP']['listen']['status'] != 'not_attempted':
            return False
        for key in ('loopbackTCP', 'loopbackUDP'):
            if item[key]['status'] != ('policy_denied' if control else 'succeeded'):
                return False
    return True


def capabilities(environment):
    result = {'platform': platform.system(), 'macOS': platform.mac_ver()[0], 'architecture': platform.machine(),
              'sandboxExecutablePresent': Path('/usr/bin/sandbox-exec').is_file(),
              'containerCommandsPresent': {name: shutil.which(name) is not None for name in ('docker', 'podman', 'colima')},
              'containerRuntimeVerified': False, 'vmBootAttempted': False}
    try:
        value = subprocess.run(['/usr/sbin/sysctl', '-n', 'kern.hv_support'], env=environment,
                               capture_output=True, text=True, timeout=5)
        result['hypervisorSupport'] = int(value.stdout.strip()) if value.returncode == 0 and value.stdout.strip() in ('0', '1') else None
    except (OSError, subprocess.TimeoutExpired):
        result['hypervisorSupport'] = None
    try:
        framework = ctypes.CDLL('/System/Library/Frameworks/Virtualization.framework/Virtualization')
        objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
        objc.objc_getClass.argtypes = [ctypes.c_char_p]
        objc.objc_getClass.restype = ctypes.c_void_p
        objc.sel_registerName.argtypes = [ctypes.c_char_p]
        objc.sel_registerName.restype = ctypes.c_void_p
        objc.objc_msgSend.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        objc.objc_msgSend.restype = ctypes.c_bool
        cls = objc.objc_getClass(b'VZVirtualMachine')
        result['virtualizationFrameworkSupported'] = bool(objc.objc_msgSend(cls, objc.sel_registerName(b'isSupported'))) if cls else None
        del framework
    except (OSError, AttributeError):
        result['virtualizationFrameworkSupported'] = None
    return result


def run_profile(profile, environment):
    result = {'profileSHA256': hashlib.sha256(profile.read_bytes()).hexdigest(), 'passed': False}
    try:
        process = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile), sys.executable, str(Path(__file__).resolve()), '--probe'],
                                 env=environment, capture_output=True, text=True, timeout=20)
        result['exitCode'] = process.returncode
        # Fixed precredential source only; omit raw errors/environment/paths.
        result['diagnosticCategories'] = [label for text, label in (
            ('syntax error', 'syntax_error'), ('host must be', 'host_filter_rejected'),
            ('unbound variable', 'unknown_filter'), ('operation not permitted', 'policy_denied'))
            if text in process.stderr.lower()]
        result['observations'] = json.loads(process.stdout) if process.returncode == 0 else {}
        result['passed'] = passed(result['observations'], control=profile.name == 'network-deny-control.sb')
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        result['diagnosticIncomplete'] = True
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.probe:
        print(json.dumps(probe(), sort_keys=True))
        return 0
    if platform.system() != 'Darwin':
        print(json.dumps({'status': 'Not tested', 'reason': 'macOS_required'}))
        return 3
    with tempfile.TemporaryDirectory(prefix='nidaa-precredential-') as temporary:
        environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': temporary, 'TMPDIR': temporary,
                       'PYTHONDONTWRITEBYTECODE': '1'}
        result = {'schemaVersion': 1, 'precredentialOnly': True, 'baselineRepeated': False,
                  'baselineProfileSHA256': hashlib.sha256((HERE/'loopback.sb').read_bytes()).hexdigest(),
                  'probeSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'capabilities': capabilities(environment)}
        result['control'] = run_profile(HERE/'network-deny-control.sb', environment)
        result['candidate'] = run_profile(HERE/'loopback-inbound-candidate.sb', environment)
        result['status'] = 'Passed' if result['control']['passed'] and result['candidate']['passed'] else 'Failed'
        result['runtimeProfileChanged'] = False
        encoded = json.dumps(result, indent=2, sort_keys=True)+'\n'
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded, encoding='utf-8')
        print(encoded, end='')
    return 0 if result['status'] == 'Passed' else 3


if __name__ == '__main__':
    sys.exit(main())
