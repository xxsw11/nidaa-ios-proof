"""PRIVATE native UI fault fixture. Never a production gateway/admin endpoint.

Started only by Integration/native/runtime.py inside its loopback sandbox.
Ordinary journey state is created through the app. Separate tests may revoke
sessions or age expiry explicitly; this fixture cannot grant consent or respond.
No request values, tokens, credentials, SQL or exception details are logged.
"""
import hmac
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import socket
import threading
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from Integration.service.domain import Domain, LOCK

CAPABILITY = os.environ['NIDAA_FIXTURE_CAPABILITY']
assert len(CAPABILITY) >= 32
mutex = threading.Lock()
state = {'offline': False, 'drop_next': False, 'command_posts': 0, 'dropped_replies': 0}


class QuietHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def reply(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self, maximum=16384):
        size = int(self.headers.get('Content-Length', '0'))
        if size < 0 or size > maximum or self.headers.get('Transfer-Encoding'):
            raise ValueError('invalid fixture body')
        return self.rfile.read(size)


class Control(QuietHandler):
    def authorized(self):
        return hmac.compare_digest(self.headers.get('X-NIDAA-Fixture', ''), CAPABILITY)

    def do_GET(self):
        if not self.authorized() or self.path != '/state':
            return self.reply(404, {'error': 'not_found'})
        try:
            with psycopg.connect(os.environ['DATABASE_ADMIN_URL'], row_factory=dict_row) as conn:
                count = conn.execute('SELECT count(*) AS count FROM nidaa.alerts').fetchone()['count']
                alerts = conn.execute('SELECT alert_id,state FROM nidaa.alerts ORDER BY created_at DESC,alert_id LIMIT 10').fetchall()
            with mutex:
                value = dict(state)
            value.update(alert_count=count, alert_ids=[str(x['alert_id']) for x in reversed(alerts)], alerts=[{'alert_id': str(x['alert_id']), 'state': x['state']} for x in alerts])
            return self.reply(200, value)
        except Exception:
            return self.reply(503, {'error': 'fixture_unavailable'})

    def do_POST(self):
        if not self.authorized() or self.path != '/control':
            return self.reply(404, {'error': 'not_found'})
        try:
            payload = json.loads(self.body(1024))
            action = payload.get('action')
            if action == 'offline' and set(payload) == {'action', 'enabled'} and type(payload['enabled']) is bool:
                with mutex:
                    state['offline'] = payload['enabled']
            elif action == 'drop_next_command_reply' and set(payload) == {'action'}:
                with mutex:
                    state['drop_next'] = True
            elif action == 'revoke' and set(payload) == {'action', 'email'}:
                email = payload['email']
                if not isinstance(email, str) or not email.endswith('.invalid') or len(email) > 254:
                    raise ValueError('fictional account required')
                with psycopg.connect(os.environ['DATABASE_ADMIN_URL']) as conn:
                    conn.execute('SELECT pg_advisory_xact_lock(%s)', (LOCK,))
                    rows = conn.execute('SELECT id FROM auth.users WHERE email=%s', (email,)).fetchall()
                    if len(rows) != 1:
                        raise ValueError('fixture target missing')
                    conn.execute('DELETE FROM auth.sessions WHERE user_id=%s', (rows[0][0],))
                    conn.execute('UPDATE nidaa.sessions SET revoked=true WHERE user_id IN (SELECT user_id FROM nidaa.accounts WHERE subject=%s)', (rows[0][0],))
            elif action == 'expire_alert' and set(payload) == {'action', 'alert_id'}:
                alert_id = UUID(payload['alert_id'])
                with psycopg.connect(os.environ['DATABASE_ADMIN_URL']) as conn:
                    conn.execute('SELECT pg_advisory_xact_lock(%s)', (LOCK,))
                    # Explicit clock-aging fixture; normal app never controls deadlines.
                    changed = conn.execute("UPDATE nidaa.alerts SET created_at=least(created_at,floor(extract(epoch FROM now()))::bigint-120), expires_at=floor(extract(epoch FROM now()))::bigint-1 WHERE alert_id=%s AND state='active'", (alert_id,))
                    if changed.rowcount != 1:
                        raise ValueError('active fixture alert missing')
            elif action == 'dispatch_fake' and set(payload) == {'action'}:
                with psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row) as conn:
                    Domain(conn).dispatch()
            else:
                return self.reply(400, {'error': 'invalid_fixture_action'})
            return self.reply(200, {'fixture_applied': action})
        except (ValueError, TypeError, KeyError):
            return self.reply(400, {'error': 'invalid_fixture_action'})
        except Exception:
            return self.reply(503, {'error': 'fixture_unavailable'})


class Proxy(QuietHandler):
    def do_GET(self): self.proxy()
    def do_POST(self): self.proxy()
    def do_PUT(self): self.proxy()
    def do_DELETE(self): self.proxy()

    def proxy(self):
        connection = None
        try:
            body = self.body()
            with mutex:
                offline = state['offline']
                is_command = self.command == 'POST' and self.path == '/v1/commands'
                drop = is_command and state['drop_next'] and not offline
                if is_command: state['command_posts'] += 1
                if drop: state['drop_next'] = False
            if offline:
                return self.reply(503, {'error': 'unavailable'})
            if not self.path.startswith('/') or self.path.startswith('//'):
                return self.reply(400, {'error': 'invalid_request'})
            connection = http.client.HTTPConnection('127.0.0.1', 55421, timeout=15)
            headers = {key: value for key, value in self.headers.items() if key.lower() in ('authorization', 'content-type', 'apikey', 'x-client-info', 'x-supabase-api-version')}
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read()
            if drop and response.status == 200:
                with mutex: state['dropped_replies'] += 1
                # Upstream committed and returned a receipt; app receives no reply.
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            self.send_response(response.status)
            self.send_header('Content-Type', response.getheader('Content-Type', 'application/json'))
            version = response.getheader('X-Supabase-Api-Version')
            if version:
                self.send_header('X-Supabase-Api-Version', version)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            if not self.close_connection:
                self.reply(503, {'error': 'unavailable'})
        finally:
            if connection: connection.close()


if __name__ == '__main__':
    control = ThreadingHTTPServer(('127.0.0.1', 55425), Control)
    proxy = ThreadingHTTPServer(('127.0.0.1', 55428), Proxy)
    threading.Thread(target=control.serve_forever, daemon=True).start()
    proxy.serve_forever()
