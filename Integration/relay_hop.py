"""Private stdin/stdout hop, executed only inside the isolated gateway container."""
import base64
import json
import sys
import httpx


def main():
    try:
        destination = {'gateway': 'http://127.0.0.1:8080', 'mail': 'http://mail:8025'}[sys.argv[1]]
        data = json.loads(sys.stdin.buffer.read(30000))
        path = data['path']
        if not path.startswith('/') or path.startswith('//') or '\\' in path:
            raise ValueError('invalid path')
        with httpx.Client(timeout=15, follow_redirects=False, trust_env=False) as client:
            reply = client.request(data['method'], destination + path,
                                   headers=data['headers'], content=base64.b64decode(data['body']))
        headers = {k:v for k,v in reply.headers.items() if k.lower() in ('content-type','location','retry-after')}
        result = {'status':reply.status_code,'headers':headers,'body':base64.b64encode(reply.content).decode()}
    except Exception:
        result = {'status':503,'headers':{},'body':''}
    sys.stdout.write(json.dumps(result))


if __name__ == '__main__':
    main()
