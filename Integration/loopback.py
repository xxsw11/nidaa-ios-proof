"""Loopback HTTP bridge through docker-exec stdin; no container egress/network added.

Docker internal-only networks may omit published-port bindings. This bridge also
works where Docker Desktop container IPs are not directly host-addressable.
Credentials never appear in child command arguments or request logs.
"""
import base64
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parent
ENV = ROOT / '.runtime.env'
COMPOSE = ['docker','compose','--project-name','nidaa-integration','--env-file',str(ENV),'-f',str(ROOT/'compose.yml')]


def main():
    values = dict(line.split('=',1) for line in ENV.read_text().splitlines() if '=' in line)
    control = values['RELAY_CONTROL_KEY']
    stopped = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def handle_one_request(self):
            try:
                super().handle_one_request()
            except (BrokenPipeError, ConnectionResetError, TimeoutError):
                pass

        def respond(self, status, body=b'', headers=None):
            self.send_response(status)
            for key,value in (headers or {}).items():
                self.send_header(key,value)
            self.send_header('Cache-Control','no-store')
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def proxy(self):
            self.connection.settimeout(25)
            if self.path == '/__nidaa_relay':
                authorized = hmac.compare_digest(self.headers.get('X-Nidaa-Control',''), control)
                self.respond(204 if authorized else 404)
                if authorized and self.command == 'DELETE':
                    stopped.set()
                return
            if self.headers.get('Transfer-Encoding'):
                self.respond(400)
                return
            try:
                length = int(self.headers.get('Content-Length','0'))
            except ValueError:
                self.respond(400)
                return
            if length < 0 or length > 16384:
                self.respond(413)
                return
            headers = {k:v for k,v in self.headers.items() if k.lower() in ('authorization','content-type','apikey','x-client-info','x-supabase-api-version')}
            payload = {'method':self.command,'path':self.path,'headers':headers,
                       'body':base64.b64encode(self.rfile.read(length)).decode()}
            try:
                hop = subprocess.run(COMPOSE + ['exec','-T','gateway','python','-m','Integration.relay_hop',self.server.destination],
                                     input=json.dumps(payload),text=True,capture_output=True,timeout=22)
                if hop.returncode != 0:
                    raise ValueError('hop unavailable')
                result = json.loads(hop.stdout)
                self.respond(result['status'],base64.b64decode(result['body']),result['headers'])
            except Exception:
                self.respond(503)

        do_GET = do_POST = do_PUT = do_DELETE = proxy

    servers = []
    running = []
    try:
        for port,destination in ((55421,'gateway'),(55424,'mail')):
            server = ThreadingHTTPServer(('127.0.0.1',port),Handler)
            server.destination = destination
            servers.append(server)
        for server in servers:
            threading.Thread(target=server.serve_forever,daemon=True).start()
            running.append(server)
        stopped.wait()
    finally:
        for server in servers:
            if server in running:
                server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
