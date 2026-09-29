"""Own one native, loopback-only trial lifetime. Runtime logs and secrets stay private."""
from pathlib import Path
import argparse
import base64
import errno
import hashlib
import html
import json
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROFILE = HERE/'loopback.sb'
BASE = 'http://127.0.0.1:55421'
MAIL = 'http://127.0.0.1:55424'


class TrialFailure(Exception):
    """Only static/coarse labels may be used as exception text."""


class Runtime:
    def __init__(self):
        self.stage = 'platform'
        self.processes = []
        self.logs = []
        self.private = None
        self.checks = {}
        self.report = {'kind': 'Actual native process health and isolation trial', 'checks': self.checks,
                       'notifications': 'Fake database sink only; no APNs or audio',
                       'nativeUI': 'Not executed by health probe', 'physicalDevice': 'Not tested'}
        self.evidence = ROOT/'artifacts/native-environment'
        self.evidence.mkdir(parents=True, exist_ok=True)

    def clean_env(self):
        # Do not let ambient SMTP, provider, proxy, database or CI-token variables
        # configure the services. Tools were downloaded before this boundary.
        return {key: value for key, value in os.environ.items()
                if key in ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'SYSTEMROOT')}

    def invoke(self, role, args, env, cwd=ROOT):
        self.stage = role
        log = open(self.private/(role+'.log'), 'ab')
        self.logs.append(log)
        result = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(PROFILE), *map(str,args)],
                                cwd=cwd, env=env, stdout=log, stderr=log, timeout=120)
        if result.returncode:
            raise TrialFailure(role+'_failed')

    def start(self, role, args, env, cwd=ROOT):
        self.stage = role
        log = open(self.private/(role+'.log'), 'ab')
        self.logs.append(log)
        process = subprocess.Popen(['/usr/bin/sandbox-exec', '-f', str(PROFILE), *map(str,args)],
                                   cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=log,
                                   stderr=log, start_new_session=True)
        self.processes.append((role, process))
        return process

    def alive(self):
        if any(process.poll() is not None for _, process in self.processes):
            raise TrialFailure('runtime_process_exited')

    def wait_http(self, url, timeout=40):
        import httpx
        end = time.monotonic()+timeout
        with httpx.Client(timeout=2, trust_env=False, follow_redirects=False) as client:
            while time.monotonic()<end:
                self.alive()
                try:
                    if client.get(url).status_code == 200:
                        return
                except httpx.HTTPError:
                    pass
                time.sleep(.25)
        raise TrialFailure('health_timeout')

    def setup(self):
        if platform.system()!='Darwin' or not Path('/usr/bin/sandbox-exec').is_file():
            raise TrialFailure('macOS_sandbox_unavailable')
        os.umask(0o077)
        base = Path(os.environ.get('RUNNER_TEMP', tempfile.gettempdir())).resolve()
        self.private = Path(tempfile.mkdtemp(prefix='nidaa-native-runtime-', dir=base)).resolve()
        self.private_parent = base
        tools = Path(os.environ.get('NIDAA_NATIVE_TOOLS', str(base/'nidaa-native-tools'))).resolve()
        self.python = tools/'venv/bin/python'
        pg = Path((tools/'postgresql-prefix.txt').read_text().strip())/'bin'
        for binary in [self.python, pg/'postgres', pg/'initdb', tools/'auth', tools/'mailpit']:
            if not binary.is_file():
                raise TrialFailure('prepared_binary_missing')
        self.stage = 'reserved_ports'
        for port in range(55421,55429):
            with socket.socket() as sock:
                try:
                    sock.bind(('127.0.0.1',port))
                except OSError:
                    raise TrialFailure('required_loopback_port_occupied') from None
        env = self.clean_env()
        self.stage = 'sandbox_policy_probe'
        probe = subprocess.run(['/usr/bin/sandbox-exec','-f',str(PROFILE),str(self.python),str(HERE/'isolation_probe.py')],
                               env=env, capture_output=True, text=True, timeout=10)
        # This probe runs before credential generation or service startup and has
        # only static socket operations. Its bounded stderr is safe to diagnose
        # profile compilation/exec errors; service stderr stays private below.
        self.report['sandboxProbeExitCode'] = probe.returncode
        diagnostic = probe.stderr.strip()
        for path,label in [(str(tools),'[NATIVE_TOOLS]'),(str(ROOT),'[REPOSITORY]'),
                           (str(self.private),'[PRIVATE_RUNTIME]'),(str(Path.home()),'[HOME]')]:
            diagnostic = diagnostic.replace(path,label)
        self.report['sandboxProbePrecredentialStderr'] = diagnostic[:8192]
        self.report['sandboxProbeStderrTruncated'] = len(diagnostic)>8192
        self.report['sandboxProbeDiagnosticScope'] = 'Static isolation probe before credentials/services; runtime service logs excluded'
        categories = {'syntax error':'profile_syntax_error','unbound variable':'profile_symbol_error',
                      'invalid':'profile_or_argument_invalid','sandbox_init':'sandbox_initialization_error',
                      'operation not permitted':'policy_denied','no such file':'probe_executable_missing'}
        self.report['sandboxProbeDiagnosticCategories'] = sorted({code for phrase,code in categories.items() if phrase in diagnostic.lower()})
        try:
            observed = json.loads(probe.stdout)
            if isinstance(observed,dict) and all(isinstance(value,bool) for value in observed.values()):
                self.report['sandboxProbeChecks'] = observed
        except (ValueError,TypeError):
            pass
        if probe.returncode:
            raise TrialFailure('sandbox_policy_not_verified')
        policy = json.loads(probe.stdout)
        expected = {'externalTCPDeniedByPolicy','externalUDPDeniedByPolicy',
                    'wildcardIPv4BindDeniedByPolicy','wildcardIPv6BindDeniedByPolicy','loopbackTCPPermitted'}
        if set(policy)!=expected or not all(value is True for value in policy.values()):
            raise TrialFailure('sandbox_policy_not_verified')
        self.checks.update(policy)
        self.report['sandboxProfileSHA256'] = hashlib.sha256(PROFILE.read_bytes()).hexdigest()
        password, auth_password, service_password = (secrets.token_hex(24) for _ in range(3))
        jwt_secret = secrets.token_hex(32)
        admin_url = f'postgresql://postgres:{password}@127.0.0.1:55422/postgres?sslmode=disable'
        auth_url = f'postgresql://supabase_auth_admin:{auth_password}@127.0.0.1:55422/postgres?sslmode=disable&search_path=auth'
        service_url = f'postgresql://nidaa_service:{service_password}@127.0.0.1:55422/postgres?sslmode=disable'
        self.admin_url = admin_url
        password_file = self.private/'postgres-password'
        password_file.write_text(password+'\n')
        data = self.private/'pgdata'
        self.invoke('initdb',[pg/'initdb','-D',data,'-U','postgres','--pwfile='+str(password_file),
                             '--auth-host=scram-sha-256','--auth-local=scram-sha-256','--encoding=UTF8','--locale=C'],env)
        password_file.unlink()
        self.start('postgres',[pg/'postgres','-D',data,'-p','55422','-h','127.0.0.1',
                               '-c','unix_socket_directories=','-c','log_statement=none',
                               '-c','log_min_error_statement=panic'],env)
        import psycopg
        from psycopg import sql
        end = time.monotonic()+30
        while True:
            self.alive()
            try:
                connection = psycopg.connect(admin_url,connect_timeout=2,autocommit=True)
                break
            except psycopg.Error:
                if time.monotonic()>=end:
                    raise TrialFailure('postgres_health_timeout') from None
                time.sleep(.2)
        with connection:
            connection.execute(sql.SQL('CREATE ROLE supabase_auth_admin LOGIN PASSWORD {}').format(sql.Literal(auth_password)))
            connection.execute('CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin')
            connection.execute('ALTER ROLE supabase_auth_admin SET search_path=auth,public')
            self.report['postgresVersion'] = connection.execute('SHOW server_version').fetchone()[0]
        self.checks['postgresNativeReady'] = True
        mail_env = env | {'MP_UI_BIND_ADDR':'127.0.0.1:55424','MP_SMTP_BIND_ADDR':'127.0.0.1:55426',
                          'MP_DATABASE':str(self.private/'mailpit.db'),'MP_MAX_MESSAGES':'1000',
                          'MP_DISABLE_VERSION_CHECK':'true','MP_QUIET':'true',
                          'MP_SMTP_AUTH_ACCEPT_ANY':'false','MP_SMTP_AUTH_ALLOW_INSECURE':'false'}
        self.start('mailpit',[tools/'mailpit'],mail_env)
        self.wait_http(MAIL+'/api/v1/messages')
        self.checks['mailpitNativeReady'] = True
        auth_env = env | {'GOTRUE_API_HOST':'127.0.0.1','GOTRUE_API_PORT':'55423','PORT':'55423',
            'API_EXTERNAL_URL':BASE+'/auth/v1','GOTRUE_SITE_URL':BASE+'/verified',
            'GOTRUE_URI_ALLOW_LIST':BASE+'/verified','GOTRUE_DB_DRIVER':'postgres',
            'GOTRUE_DB_DATABASE_URL':auth_url,'DATABASE_URL':auth_url,'GOTRUE_DB_NAMESPACE':'auth',
            'GOTRUE_JWT_SECRET':jwt_secret,'GOTRUE_JWT_ISSUER':BASE+'/auth/v1',
            'GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated',
            'GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_JWT_EXP':'3600',
            'GOTRUE_EXTERNAL_EMAIL_ENABLED':'true','GOTRUE_EXTERNAL_PHONE_ENABLED':'false',
            'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED':'false','GOTRUE_DISABLE_SIGNUP':'false',
            'GOTRUE_MAILER_AUTOCONFIRM':'false','GOTRUE_MAILER_OTP_EXP':'300',
            'GOTRUE_SMTP_HOST':'127.0.0.1','GOTRUE_SMTP_PORT':'55426',
            'GOTRUE_SMTP_ADMIN_EMAIL':'noreply@example.invalid','GOTRUE_SMTP_SENDER_NAME':'NIDAA native trial',
            'GOTRUE_SMTP_MAX_FREQUENCY':'1s','GOTRUE_LOG_LEVEL':'error','LOG_LEVEL':'error',
            'OTEL_SDK_DISABLED':'true'}
        for key in ['EMAIL_SENT','VERIFY','TOKEN_REFRESH','SIGN_IN_SIGN_UP','OTP']:
            auth_env['GOTRUE_RATE_LIMIT_'+key]='1000'
        for key in ['CONFIRMATION','RECOVERY','EMAIL_CHANGE']:
            auth_env['GOTRUE_MAILER_URLPATHS_'+key]='/auth/v1/verify'
        self.start('auth',[tools/'auth'],auth_env,cwd=tools/'auth-source')
        self.wait_http('http://127.0.0.1:55423/health',60)
        self.checks['realSupabaseAuthReady'] = True
        self.service_env = env | {'DATABASE_URL':service_url,'AUTH_URL':'http://127.0.0.1:55423',
            'AUTH_ISSUER':BASE+'/auth/v1','JWT_SECRET':jwt_secret,
            'RECEIPT_KEY':base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(),
            'PYTHONPATH':str(ROOT),'PYTHONUNBUFFERED':'1'}
        bootstrap_env = self.service_env | {'DATABASE_ADMIN_URL':admin_url,'SERVICE_DB_PASSWORD':service_password}
        self.invoke('migrations',[self.python,'-m','Integration.bootstrap'],bootstrap_env)
        self.start('domain',[self.python,'-m','uvicorn','Integration.service.main:app',
                            '--host','127.0.0.1','--port','55427','--no-access-log','--log-level','error'],self.service_env)
        self.start('gateway',[self.python,'-m','uvicorn','Integration.gateway:app','--host','127.0.0.1',
                             '--port','55421','--no-access-log','--log-level','error'],env|{'NIDAA_NATIVE_LOOPBACK':'1','PYTHONPATH':str(ROOT)})
        self.wait_http(BASE+'/health')
        self.wait_http(BASE+'/auth/v1/health')
        self.checks['gatewayAndDomainReady'] = True
        self.stage = 'real_auth_mail_smoke'
        self.smoke()
        self.stage = 'bound_listener_audit'
        # Inspect only owned processes; never export command lines/environment.
        listeners=[]
        for role, process in self.processes:
            result=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(process.pid),'-iTCP','-sTCP:LISTEN','-Fn'],capture_output=True,text=True)
            addresses=[line[1:] for line in result.stdout.splitlines() if line.startswith('n')]
            if result.returncode or not addresses or any(not address.startswith('127.0.0.1:') for address in addresses):
                raise TrialFailure('owned_listener_not_loopback')
            listeners.append({'role':role,'addresses':addresses})
        self.report['listeners']=listeners
        self.checks['allOwnedTCPListenersLoopback'] = True
        self.stage = 'ready'
        self.report['status'] = 'Passed'
        self.write_report()
        print('PASS native PostgreSQL + Supabase Auth + local mailbox + API health and network policy',flush=True)

    def smoke(self):
        import httpx
        email='native-health-'+uuid4().hex+'@example.invalid'
        password='Nidaa!'+uuid4().hex
        with httpx.Client(timeout=5,trust_env=False,follow_redirects=False) as client:
            reply=client.post(BASE+'/auth/v1/signup',json={'email':email,'password':password,'data':{'display_name':'Sara'}})
            if reply.status_code not in (200,201) or reply.json().get('access_token'):
                raise TrialFailure('signup_verification_boundary_failed')
            query=None
            end=time.monotonic()+20
            while time.monotonic()<end and query is None:
                listing=client.get(MAIL+'/api/v1/messages')
                if listing.status_code!=200:
                    raise TrialFailure('local_inbox_unavailable')
                for item in listing.json().get('messages',[]):
                    if not any(address.get('Address','').lower()==email for address in item.get('To',[])):
                        continue
                    message=client.get(MAIL+'/api/v1/message/'+item['ID']).json()
                    body=html.unescape(message.get('HTML','')+'\n'+message.get('Text',''))
                    for link in re.findall(r'https?://[^\s<>"\']+',body):
                        candidate=parse_qs(urlsplit(link).query)
                        if candidate.get('type')==['signup'] and 'token' in candidate:
                            query={'token_hash':candidate['token'][0],'type':'signup'}
                            break
                if query is None:
                    time.sleep(.2)
            if query is None:
                raise TrialFailure('local_verification_mail_missing')
            # Consume the token through a fixed local API, never follow email URLs.
            if client.post(BASE+'/auth/v1/verify',json=query).status_code!=200:
                raise TrialFailure('actual_provider_verification_failed')
            reply=client.post(BASE+'/auth/v1/token',params={'grant_type':'password'},json={'email':email,'password':password})
            if reply.status_code!=200 or not reply.json().get('access_token'):
                raise TrialFailure('actual_provider_login_failed')
            headers={'Authorization':'Bearer '+reply.json()['access_token']}
            account=client.get(BASE+'/v1/me',headers=headers)
            if account.status_code!=200 or not account.json().get('email_verified'):
                raise TrialFailure('real_verified_domain_identity_failed')
            if client.post(BASE+'/v1/session/logout',headers=headers,json={}).status_code!=204:
                raise TrialFailure('provider_logout_failed')
            if client.get(BASE+'/v1/me',headers=headers).status_code!=401:
                raise TrialFailure('revoked_session_still_accepted')
        self.checks.update(realSignupRequiresVerification=True,realLocalMailConsumed=True,
                           actualPasswordLoginAndDomainIdentity=True,revokedSessionDenied=True)

    def run_child(self, fixture, command):
        env=os.environ.copy()
        env.update(NIDAA_BASE_URL=BASE,NIDAA_MAIL_URL=MAIL)
        if fixture:
            path=(ROOT/fixture).resolve()
            if not path.is_relative_to((ROOT/'QA/NativeReview').resolve()) or not path.is_file():
                raise TrialFailure('fixture_script_outside_authorized_directory')
            capability=secrets.token_urlsafe(32)
            fixture_env=self.service_env|{'DATABASE_ADMIN_URL':self.admin_url,'BASE_URL':BASE,'MAIL_URL':MAIL,
                                        'NIDAA_FIXTURE_CAPABILITY':capability}
            self.start('test_fixture',[self.python,path],fixture_env)
            env.update(NIDAA_FIXTURE_CAPABILITY=capability,NIDAA_FIXTURE_URL='http://127.0.0.1:55425',
                       NIDAA_FAULT_BASE_URL='http://127.0.0.1:55428')
        if command:
            self.stage='caller_command'
            # The Xcode runner may resolve dependencies. Backend descendants remain
            # sandboxed. No backend credentials are added to this caller environment.
            child=subprocess.Popen(command,cwd=ROOT,env=env,start_new_session=True)
            self.processes.append(('caller_command',child))
            result=child.wait()
            self.report['callerCommandExitCode']=result
            self.write_report()
            return result
        return 0

    def write_report(self):
        self.report['stage']=self.stage
        (self.evidence/'native-health.json').write_text(json.dumps(self.report,indent=2)+'\n')

    def failure_categories(self):
        # Allowlisted diagnosis only; never copy raw process logs into evidence.
        known={'permission denied':'permission_denied','operation not permitted':'policy_denied',
               'address already in use':'address_in_use','connection refused':'connection_refused',
               'no such file or directory':'file_missing','password authentication failed':'database_authentication_failed',
               'syntax error':'configuration_syntax_error','unbound variable':'sandbox_profile_symbol_error',
               'migration':'migration_context','fatal':'fatal_process_error'}
        found={}
        if self.private:
            for path in self.private.glob('*.log'):
                text=path.read_text(errors='replace').lower()
                categories=sorted({code for phrase,code in known.items() if phrase in text})
                if categories:
                    found[path.stem]=categories
        return found

    def close(self):
        for role,process in reversed(self.processes):
            if process.poll() is None:
                try:
                    os.killpg(process.pid,signal.SIGINT if role=='postgres' else signal.SIGTERM)
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGKILL)
                    process.wait(timeout=3)
                except ProcessLookupError:
                    pass
        for log in self.logs:
            log.close()
        if self.private and self.private.parent==self.private_parent and self.private.name.startswith('nidaa-native-runtime-'):
            shutil.rmtree(self.private)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['run'])
    parser.add_argument('--fixture')
    options,command=parser.parse_known_args()
    if command and command[0]=='--':
        command=command[1:]
    runtime=Runtime()
    def interrupted(signum,frame):
        raise TrialFailure('runtime_interrupted')
    signal.signal(signal.SIGTERM,interrupted)
    signal.signal(signal.SIGINT,interrupted)
    try:
        runtime.setup()
        return runtime.run_child(options.fixture,command)
    except Exception as error:
        label=str(error) if isinstance(error,TrialFailure) else 'internal_error_redacted'
        runtime.report.update(status='Failed',failure=label,
                              processExitCodes={role:p.poll() for role,p in runtime.processes},
                              diagnosticCategories=runtime.failure_categories())
        runtime.write_report()
        print('FAIL native trial: '+runtime.stage+' / '+label,flush=True)
        return 2
    finally:
        runtime.close()


if __name__=='__main__':
    sys.exit(main())
