"""Loopback-isolated trial HTTP boundary; all notifications remain fake."""
import json
import os
import urllib.error
import urllib.request
from uuid import UUID

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from starlette.concurrency import run_in_threadpool

from .domain import Domain, RuleError, connect, validate

app = FastAPI(docs_url=None,redoc_url=None,openapi_url=None)
ERROR_STATUS = {'invalid_request':400,'unauthenticated':401,'not_found':404,'conflict':409,
                'expired':410,'rate_limited':429,'reauthentication_required':403,'forbidden':403}


@app.middleware('http')
async def headers_and_limits(request, call_next):
    # Enforce actual received size too, not merely the untrusted Content-Length.
    if request.method in ('POST','PUT','PATCH'):
        size=0; chunks=[]
        async for chunk in request.stream():
            size+=len(chunk)
            if size>16384:
                return JSONResponse({'error':'invalid_request'},status_code=400,headers={'Cache-Control':'no-store'})
            chunks.append(chunk)
        request._body=b''.join(chunks)
    response=await call_next(request)
    response.headers['Cache-Control']='no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    return response


def bearer(request):
    value=request.headers.get('authorization','')
    if not value.startswith('Bearer ') or len(value)>8192:
        raise RuleError('unauthenticated')
    return value[7:]


def error_response(exc):
    return JSONResponse({'error':exc.code},status_code=ERROR_STATUS.get(exc.code,400))


def invoke(request, function, kind=None):
    try:
        token=bearer(request)
        with connect() as conn:
            domain=Domain(conn)
            try:
                session=domain.principal(token)
                domain.expire()
                result=function(domain,session)
                if kind: validate(kind,result)
            except RuleError as exc:
                # Commit benign expiry/rate accounting even when transport validation fails.
                return error_response(exc)
        return JSONResponse(result)
    except RuleError as exc:
        return error_response(exc)
    except Exception:
        # No exception repr/traceback, tokens, SQL parameters or bodies in logs/artifacts.
        # No receipt means unknown outcome. Empty 503 is deliberately not a rejection receipt.
        return Response(status_code=503)


@app.get('/health')
def health():
    try:
        with connect() as conn:
            conn.execute('SELECT 1 FROM nidaa.accounts LIMIT 1')
        return {'status':'ok','delivery_adapter':'fake'}
    except Exception:
        return Response(status_code=503)


@app.post('/v1/commands')
async def commands(request:Request):
    try:
        body=await request.json()
        validate('Command',body)
    except (ValueError,RuleError,UnicodeDecodeError):
        return JSONResponse({'error':'invalid_request'},status_code=400)
    # Concurrent clients reach independent transactions; PostgreSQL serializes them.
    return await run_in_threadpool(invoke,request,lambda d,s:d.execute(s,body),'Receipt')


def valid_uuid(value):
    try: return str(UUID(value))
    except ValueError: raise RuleError('not_found') from None


@app.get('/v1/operations/{operation_id}')
def operation(operation_id:str,request:Request):
    return invoke(request,lambda d,s:d.receipt(s['user_id'],valid_uuid(operation_id)),'Receipt')


@app.get('/v1/alerts/{alert_id}')
def alert(alert_id:str,request:Request):
    return invoke(request,lambda d,s:d.view(s['user_id'],valid_uuid(alert_id)),'Alert')


@app.get('/v1/me')
def me(request:Request):
    return invoke(request,lambda d,s:d.account(s),'Account')


@app.get('/v1/relationships')
def relationships(request:Request):
    return invoke(request,lambda d,s:d.relationships(s),'Relationships')


@app.get('/v1/sync')
def sync(request:Request):
    return invoke(request,lambda d,s:d.sync(s),'Sync')


def provider_logout(token,all_devices):
    """Best effort AFTER durable domain barrier; no administrative credentials."""
    url=os.environ['AUTH_URL'].rstrip('/')+'/logout?scope='+('global' if all_devices else 'local')
    req=urllib.request.Request(url,data=b'',method='POST',headers={'Authorization':'Bearer '+token})
    try:
        with urllib.request.urlopen(req,timeout=5) as response:
            return response.status in (200,204)
    except (urllib.error.URLError,TimeoutError):
        return False


def logout_transaction(request,all_devices):
    try:
        token=bearer(request)
        with connect() as conn:
            d=Domain(conn)
            s=d.principal(token)
            d.revoke(s,all_devices)
        # Whether provider cleanup succeeds or not, expired/revoked session cannot call domain.
        provider_logout(token,all_devices)
        return Response(status_code=204)
    except RuleError as exc:
        if exc.code=='unauthenticated':
            return Response(status_code=204)  # Safe repeated logout, no session reinstatement.
        return error_response(exc)
    except (ValueError,UnicodeDecodeError):
        return error_response(RuleError('invalid_request'))
    except Exception:
        return Response(status_code=503)


@app.post('/v1/session/logout')
async def logout(request:Request):
    return await logout_impl(request,False)


@app.post('/v1/session/revoke-all')
async def revoke_all(request:Request):
    return await logout_impl(request,True)


async def logout_impl(request,all_devices):
    try:
        if await request.json()!={}: raise RuleError('invalid_request')
    except (ValueError,UnicodeDecodeError,RuleError):
        return error_response(RuleError('invalid_request'))
    return await run_in_threadpool(logout_transaction,request,all_devices)
