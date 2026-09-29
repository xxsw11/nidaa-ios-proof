#!/usr/bin/env python3
"""Inspect a macOS runner; never start virtualization, services, or sockets.

The report records capabilities, not a successful VM boot or network-isolation
test. Compiled helper and source exist only in this probe's temporary directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import time


SWIFT = '''import Virtualization
// Public capability query only; no VM configuration, creation, or start.
if #available(macOS 11.0, *) {
    print(VZVirtualMachine.isSupported ? "true" : "false")
} else {
    print("unavailable")
}
'''
TOOLS = ('docker', 'colima', 'podman', 'qemu-system-x86_64')


def run_command(label, argv, maximum, deadline, trace):
    remaining = max(0, deadline-time.monotonic())
    record = {'operation': label, 'maximumSeconds': maximum,
              'effectiveTimeoutSeconds': round(min(maximum, remaining), 3)}
    trace.append(record)
    if remaining <= 0:
        record['status'] = 'Notexecuted-budget'
        return None
    started = time.monotonic()
    try:
        result = subprocess.run(argv, capture_output=True, text=True,
                                timeout=min(maximum, remaining))
        record['status'] = 'Completed'
        record['exitCode'] = result.returncode
        return result
    except subprocess.TimeoutExpired:
        record['status'] = 'Timed-out'
        return None
    except OSError:
        record['status'] = 'Tool-unavailable'
        return None
    finally:
        record['elapsedSeconds'] = round(time.monotonic()-started, 3)


def hypervisor_result(result):
    if result is None or result.returncode != 0:
        return {'status': 'Unavailable', 'supported': None}
    value = result.stdout.strip()
    if value not in ('0', '1'):
        return {'status': 'Unrecognized-output', 'supported': None}
    return {'status': 'Available', 'supported': value == '1', 'value': int(value)}


def virtualization_result(result):
    if result is None or result.returncode != 0:
        return {'status': 'Unavailable', 'supported': None}
    value = result.stdout.strip()
    if value not in ('true', 'false'):
        return {'status': 'Unavailable' if value == 'unavailable' else 'Unrecognized-output',
                'supported': None}
    return {'status': 'Available', 'supported': value == 'true'}


def compile_errors(stderr):
    errors = []
    for line in stderr.splitlines():
        match = re.search(r':(\d+):(\d+): error: (.*)$', line)
        if not match:
            continue
        message = re.sub(r'(?:[A-Za-z]:)?[/\\][^\s\'"<>]+', '[path]', match.group(3))
        errors.append({'line': int(match.group(1)), 'column': int(match.group(2)), 'error': message[:240]})
        if len(errors) == 10:
            break
    return errors


def inspect():
    started = time.monotonic()
    # Commands get 110 seconds total; retain 10 seconds for temporary cleanup
    # and the small JSON write inside the requested 120-second probe budget.
    deadline = started+110
    report = {'schemaVersion': 1, 'status': 'Inspected', 'budgetSeconds': 120,
              'commandBudgetSeconds': 110, 'architecture': platform.machine(),
              'operatingSystem': platform.system(), 'macOSVersion': platform.mac_ver()[0] or None,
              'commandPresence': {name: shutil.which(name) is not None for name in TOOLS},
              'hypervisorFramework': {'status': 'Notexecuted', 'supported': None},
              'virtualizationFramework': {'status': 'Notexecuted', 'supported': None},
              'isolationValidated': False, 'virtualMachineStarted': False,
              'containerStarted': False, 'servicesStarted': False,
              'credentialsCreated': False, 'networkOrSocketTestsStarted': False,
              'toolsInstalled': False, 'commands': [],
              'probeSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    if report['operatingSystem'] != 'Darwin':
        report['status'] = 'Unsupported-host'
        report['elapsedSeconds'] = round(time.monotonic()-started, 3)
        return report
    trace = report['commands']
    hv = run_command('sysctl-kern-hv-support', ['/usr/sbin/sysctl', '-n', 'kern.hv_support'], 10, deadline, trace)
    report['hypervisorFramework'] = hypervisor_result(hv)
    xcrun = shutil.which('xcrun')
    if xcrun is None:
        report['virtualizationFramework'] = {'status': 'Compiler-unavailable', 'supported': None}
    else:
        located = run_command('find-installed-swift-compiler', [xcrun, '--find', 'swiftc'], 10, deadline, trace)
        if located is None or located.returncode != 0 or not Path(located.stdout.strip()).is_file():
            report['virtualizationFramework'] = {'status': 'Compiler-unavailable', 'supported': None}
        else:
            with tempfile.TemporaryDirectory(prefix='nidaa-host-capability-') as temporary:
                source = Path(temporary)/'Capability.swift'
                binary = Path(temporary)/'capability'
                source.write_text(SWIFT, encoding='utf-8')
                built = run_command('compile-public-VZ-query', [located.stdout.strip(), str(source), '-o', str(binary)], 60, deadline, trace)
                if built is None or built.returncode != 0:
                    report['virtualizationFramework'] = {'status': 'Compile-unavailable', 'supported': None}
                    if built is not None:
                        report['virtualizationFramework']['compileErrors'] = compile_errors(built.stderr)
                else:
                    queried = run_command('query-public-VZ-support', [str(binary)], 10, deadline, trace)
                    report['virtualizationFramework'] = virtualization_result(queried)
    report['elapsedSeconds'] = round(time.monotonic()-started, 3)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('artifacts/intel-host-capability/report.json'))
    args = parser.parse_args()
    report = inspect()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8')
    print(json.dumps(report, sort_keys=True))
    return 0 if report['status'] == 'Inspected' else 3


if __name__ == '__main__':
    raise SystemExit(main())
