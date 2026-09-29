"""Run inside the same sandbox profile as services. Never sends credentials or payloads."""
import errno
import json
import socket
import sys

checks = {}


def denied(name, family, kind, operation):
    with socket.socket(family, kind) as sock:
        sock.settimeout(1)
        try:
            operation(sock)
        except OSError as error:
            # Refusal/timeouts only show unreachability, not policy enforcement.
            checks[name] = error.errno in (errno.EPERM, errno.EACCES)
        else:
            checks[name] = False


denied('externalTCPDeniedByPolicy', socket.AF_INET, socket.SOCK_STREAM, lambda s: s.connect(('192.0.2.1', 9)))
denied('externalUDPDeniedByPolicy', socket.AF_INET, socket.SOCK_DGRAM, lambda s: s.sendto(b'', ('192.0.2.1', 9)))
denied('wildcardIPv4BindDeniedByPolicy', socket.AF_INET, socket.SOCK_STREAM, lambda s: s.bind(('0.0.0.0', 0)))
denied('wildcardIPv6BindDeniedByPolicy', socket.AF_INET6, socket.SOCK_STREAM, lambda s: s.bind(('::', 0)))
with socket.socket() as server:
    server.bind(('127.0.0.1', 0))
    server.listen(1)
    with socket.create_connection(server.getsockname(), timeout=1):
        connection, _ = server.accept()
        connection.close()
        checks['loopbackTCPPermitted'] = True
print(json.dumps(checks))
sys.exit(0 if all(checks.values()) else 3)
