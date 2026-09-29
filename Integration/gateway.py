"""Loopback-only trial gateway. Fixed upstreams, no admin/auth URL logging."""
import httpx
import json
import os
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
AUTH_PATHS = {"signup", "token", "verify", "logout", "user", "recover", "resend", "otp", "settings", "health", "reauthenticate"}
# Native trial changes only fixed upstream addresses, never accepts a URL from a caller.
if os.environ.get('NIDAA_NATIVE_LOOPBACK') == '1':
    AUTH_UPSTREAM = 'http://127.0.0.1:55423/'
    DOMAIN_UPSTREAM = 'http://127.0.0.1:55427/'
else:
    AUTH_UPSTREAM = 'http://auth:9999/'
    DOMAIN_UPSTREAM = 'http://service:8000/'


@app.api_route('/{path:path}', methods=['GET', 'POST', 'PUT', 'DELETE'])
async def proxy(path: str, request: Request):
    if path == 'verified':
        return Response('NIDAA local email verification completed. Return to the test app.', media_type='text/plain')
    if path.startswith('auth/v1/') and path[8:] in AUTH_PATHS:
        target = AUTH_UPSTREAM + path[8:]
    elif path.startswith('v1/') or path == 'health':
        target = DOMAIN_UPSTREAM + path
    else:
        return JSONResponse({'error': 'not_found'}, status_code=404)
    body = bytearray()
    async for part in request.stream():
        body.extend(part)
        if len(body) > 16384:
            return JSONResponse({'error': 'invalid_request'}, status_code=413)
    if path == 'auth/v1/user' and request.method == 'PUT':
        try:
            fields = json.loads(body)
            if not isinstance(fields, dict) or 'email' in fields or 'phone' in fields:
                return JSONResponse({'error':'not_enabled'},status_code=403)
        except (ValueError, UnicodeDecodeError):
            return JSONResponse({'error':'invalid_request'},status_code=400)
    headers = {k: v for k, v in request.headers.items() if k.lower() in ('authorization', 'content-type', 'apikey', 'x-client-info', 'x-supabase-api-version')}
    # Never trust client forwarded IP/host or permit an arbitrary proxy destination.
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=False, trust_env=False) as client:
            result = await client.request(request.method, target, params=request.query_params, content=bytes(body), headers=headers)
        safe_headers = {'cache-control': 'no-store'}
        for key in ('content-type', 'location', 'retry-after', 'x-supabase-api-version'):
            if key in result.headers:
                safe_headers[key] = result.headers[key]
        return Response(result.content, status_code=result.status_code, headers=safe_headers)
    except httpx.HTTPError:
        return JSONResponse({'error': 'unavailable'}, status_code=503)
