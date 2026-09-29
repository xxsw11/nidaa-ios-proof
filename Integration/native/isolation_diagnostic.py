"""Precredential socket diagnostic, never a replacement for the isolation gate.

Run under the unchanged service sandbox profile. No backend is started, no
credentials are read, and no application payload is transmitted. Wildcard TCP
sockets are closed immediately after the listen attempt; they never accept.
"""
import errno
import json
import socket


def observed(operation):
    try:
        operation()
    except OSError as error:
        return {
            'status': 'policy_denied' if error.errno in (errno.EPERM, errno.EACCES) else 'other_error',
            'errno': error.errno,
        }
    return {'status': 'succeeded', 'errno': None}


def wildcard(family, address):
    result = {'create': None, 'bind': {'status': 'not_attempted'}, 'listen': {'status': 'not_attempted'}}
    try:
        sock = socket.socket(family, socket.SOCK_STREAM)
    except OSError as error:
        result['create'] = {
            'status': 'policy_denied' if error.errno in (errno.EPERM, errno.EACCES) else 'other_error',
            'errno': error.errno,
        }
        return result
    result['create'] = {'status': 'succeeded', 'errno': None}
    with sock:
        sock.settimeout(1)
        result['bind'] = observed(lambda: sock.bind((address, 0)))
        if result['bind']['status'] == 'succeeded':
            result['listen'] = observed(lambda: sock.listen(1))
        # No accepts, connects, or additional work before closing this socket.
    return result


def outbound(kind, operation):
    try:
        with socket.socket(socket.AF_INET, kind) as sock:
            sock.settimeout(1)
            return observed(lambda: operation(sock))
    except OSError as error:
        return {'status': 'other_error', 'errno': error.errno, 'stage': 'socket_setup'}


def loopback():
    def exchange():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
            server.settimeout(1)
            server.bind(('127.0.0.1', 0))
            server.listen(1)
            with socket.create_connection(server.getsockname(), timeout=1):
                connection, _ = server.accept()
                connection.close()
    return observed(exchange)


def main():
    result = {
        'schemaVersion': 1,
        'diagnosticOnly': True,
        'wildcardIPv4': wildcard(socket.AF_INET, '0.0.0.0'),
        'wildcardIPv6': wildcard(socket.AF_INET6, '::'),
        'externalTCP': outbound(socket.SOCK_STREAM, lambda sock: sock.connect(('192.0.2.1', 9))),
        'externalUDP': outbound(socket.SOCK_DGRAM, lambda sock: sock.sendto(b'', ('192.0.2.1', 9))),
        'loopbackTCP': loopback(),
    }
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
