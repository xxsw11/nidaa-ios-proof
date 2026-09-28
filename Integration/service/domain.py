"""PostgreSQL authority. Each public call uses its own connection/transaction.

The trial-wide advisory transaction lock deliberately serializes mutations, reads,
revocation and fake handoff. This proves ordering, not production throughput.
"""
import hashlib
import json
import os
import secrets
import time
from pathlib import Path
from uuid import UUID, uuid4

import jwt
import psycopg
from cryptography.fernet import Fernet
from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import ValidationError
from psycopg.rows import dict_row

SCHEMA = json.loads((Path(__file__).resolve().parents[2] / 'SharedRules/contract.schema.json').read_text())
LOCK = 790182453


class RuleError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def require(ok, code):
    if not ok:
        raise RuleError(code)


def clean(value):
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, list):
        return [clean(v) for v in value]
    return value


def validate(kind, value):
    try:
        Draft202012Validator(SCHEMA['$defs'][kind], format_checker=FormatChecker()).validate(value)
    except ValidationError:
        raise RuleError('invalid_request') from None


def connect():
    return psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row)


class Domain:
    def __init__(self, conn):
        self.conn = conn
        conn.execute('SELECT pg_advisory_xact_lock(%s)', (LOCK,))
        self.now = int(conn.execute('SELECT floor(extract(epoch FROM clock_timestamp()))::bigint AS now').fetchone()['now'])

    def one(self, sql, params=()):
        row = self.conn.execute(sql, params).fetchone()
        return clean(row) if row else None

    def all(self, sql, params=()):
        return clean(self.conn.execute(sql, params).fetchall())

    def run(self, sql, params=()):
        return self.conn.execute(sql, params)

    def touch(self, *users):
        ids = list(set(u for u in users if u))
        if ids:
            self.run('UPDATE nidaa.accounts SET cursor=cursor+1 WHERE user_id=ANY(%s::uuid[])', (ids,))

    def touch_alert(self, aid):
        a = self.one('SELECT sender_id FROM nidaa.alerts WHERE alert_id=%s', (aid,))
        if a:
            self.touch(a['sender_id'], *[r['user_id'] for r in self.all('SELECT user_id FROM nidaa.recipients WHERE alert_id=%s', (aid,))])

    def principal(self, token):
        try:
            claims = jwt.decode(token, os.environ['JWT_SECRET'], algorithms=['HS256'],
                                audience='authenticated', issuer=os.environ.get('AUTH_ISSUER', os.environ.get('JWT_ISSUER')),
                                options={'require': ['exp', 'iat', 'sub', 'session_id', 'aud', 'iss']})
            subject, sid = str(UUID(claims['sub'])), str(UUID(claims['session_id']))
        except (jwt.PyJWTError, ValueError, TypeError, KeyError):
            raise RuleError('unauthenticated') from None
        require(claims.get('role')=='authenticated' and not claims.get('is_anonymous',False),'unauthenticated')
        provider = self.one('''SELECT u.email,u.email_confirmed_at,u.deleted_at,u.banned_until,
            floor(extract(epoch FROM s.created_at))::bigint AS session_created
            FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
            WHERE u.id=%s AND s.id=%s AND (s.not_after IS NULL OR s.not_after>now())''', (subject, sid))
        require(provider and provider['email_confirmed_at'] and not provider['deleted_at'] and
                (not provider['banned_until'] or provider['banned_until'].timestamp() <= self.now), 'unauthenticated')
        require(not self.one('SELECT 1 FROM nidaa.deletion_ledger WHERE subject=%s', (subject,)), 'unauthenticated')
        account = self.one('SELECT * FROM nidaa.accounts WHERE subject=%s', (subject,))
        if not account:
            uid = str(uuid4())
            self.run('INSERT INTO nidaa.accounts(user_id,subject,email,display_name,created_at) VALUES(%s,%s,%s,%s,%s)',
                     (uid, subject, provider['email'].strip().lower(), 'حساب تجريبي', self.now))
            account = self.one('SELECT * FROM nidaa.accounts WHERE user_id=%s', (uid,))
        require(account['active'] and provider['session_created'] > account['revoked_before'], 'unauthenticated')
        # A verified mailbox change invalidates old target-bound invitations/grants.
        email = provider['email'].strip().lower()
        if email != account['email']:
            self.restrict_account(account['user_id'], 'withdrawn')
            self.run("UPDATE nidaa.invitations SET state='cancelled',intended_email='',token_digest=NULL WHERE intended_email=%s", (account['email'],))
            self.run('UPDATE nidaa.accounts SET email=%s WHERE user_id=%s', (email, account['user_id']))
            account['email'] = email
        methods = {'password', 'otp', 'magiclink', 'email', 'email/signup'}
        evidence = [a.get('timestamp', 0) for a in claims.get('amr', []) if a.get('method') in methods]
        auth_at = max((v for v in evidence if isinstance(v, int) and 0 <= v <= self.now), default=0)
        session = self.one('SELECT * FROM nidaa.sessions WHERE session_id=%s', (sid,))
        if not session:
            self.run('INSERT INTO nidaa.sessions(session_id,user_id,device_id,auth_at) VALUES(%s,%s,%s,%s)',
                     (sid, account['user_id'], str(uuid4()), auth_at))
            session = self.one('SELECT * FROM nidaa.sessions WHERE session_id=%s', (sid,))
        require(not session['revoked'] and session['user_id'] == account['user_id'], 'unauthenticated')
        # Signed provider AMR is authoritative; refresh iat must never refresh this timestamp.
        session.update(email=email, auth_at=auth_at, subject=subject, display_name=account['display_name'])
        return session

    def recent(self, s):
        require(0 <= self.now - s['auth_at'] <= 300 and s['auth_at'] > 0, 'reauthentication_required')

    def blocked(self, a, b):
        return bool(self.one('SELECT 1 FROM nidaa.blocks WHERE (blocker_id=%s AND target_id=%s) OR (blocker_id=%s AND target_id=%s)', (a,b,b,a)))

    def consent(self, a, b):
        return a != b and not self.blocked(a,b) and bool(self.one('''SELECT 1 FROM nidaa.grants g
          JOIN nidaa.accounts a ON a.user_id=g.sender_id JOIN nidaa.accounts b ON b.user_id=g.recipient_id
          JOIN auth.users pa ON pa.id=a.subject JOIN auth.users pb ON pb.id=b.subject
          WHERE g.sender_id=%s AND g.recipient_id=%s AND g.state='accepted' AND a.active AND b.active
          AND pa.email_confirmed_at IS NOT NULL AND pb.email_confirmed_at IS NOT NULL
          AND pa.deleted_at IS NULL AND pb.deleted_at IS NULL
          AND (pa.banned_until IS NULL OR pa.banned_until<=to_timestamp(%s))
          AND (pb.banned_until IS NULL OR pb.banned_until<=to_timestamp(%s))''', (a,b,self.now,self.now)))

    def erase_tokens(self):
        self.run('''UPDATE nidaa.operations o SET token_ciphertext=NULL WHERE token_ciphertext IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM nidaa.invitations i WHERE i.invitation_id=o.resource_id
          AND i.state='pending' AND i.expires_at>%s)''', (self.now,))

    def expire(self):
        invites = self.all("UPDATE nidaa.invitations SET state='expired' WHERE state='pending' AND expires_at<=%s RETURNING sender_id,intended_email", (self.now,))
        for i in invites:
            target = self.one('SELECT user_id FROM nidaa.accounts WHERE email=%s AND active', (i['intended_email'],))
            self.touch(i['sender_id'], target['user_id'] if target else None)
        for a in self.all("SELECT alert_id,expires_at FROM nidaa.alerts WHERE state='active' AND expires_at<=%s", (self.now,)):
            self.finish(a['alert_id'], 'expired', a['expires_at'])
        self.erase_tokens()

    def finish(self, aid, state, when=None):
        self.run('UPDATE nidaa.alerts SET state=%s,closed_at=%s,version=version+1 WHERE alert_id=%s', (state, self.now if when is None else when, aid))
        self.run("UPDATE nidaa.outbox SET state='suppressed' WHERE alert_id=%s AND state='queued'", (aid,))
        self.touch_alert(aid)

    def receipt(self, uid, op):
        o = self.one('SELECT * FROM nidaa.operations WHERE actor_id=%s AND operation_id=%s', (uid,op))
        require(o, 'not_found')
        token = None
        if o['token_ciphertext'] and self.now-o['created_at'] < 86400:
            token = Fernet(os.environ['RECEIPT_KEY'].encode()).decrypt(o['token_ciphertext'].encode()).decode()
        result = dict(operation_id=op,status=o['status'],resource_id=o['resource_id'],error=o['error'],server_time=o['created_at'],invitation_token=token)
        validate('Receipt', result)
        return result

    def throttle(self, uid, name):
        if name not in ('invite','decide_invite','create_alert'):
            return
        window, limit = (86400,10) if name=='invite' else (60,5)
        count = self.one('SELECT count(*) AS n FROM nidaa.rate_events WHERE user_id=%s AND command=%s AND created_at>%s', (uid,name,self.now-window))['n']
        require(count < limit, 'rate_limited')
        self.run('INSERT INTO nidaa.rate_events VALUES(%s,%s,%s)', (uid,name,self.now))

    def execute(self, s, request):
        validate('Command', request)
        self.expire()
        uid, op = s['user_id'], request['operation_id']
        fingerprint = hashlib.sha256(json.dumps(request,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        old = self.one('SELECT fingerprint FROM nidaa.operations WHERE actor_id=%s AND operation_id=%s', (uid,op))
        if old:
            require(old['fingerprint']==fingerprint, 'conflict')
            return self.receipt(uid,op)
        require(0 <= self.now-request['issued_at'] <= 60, 'expired')
        self.throttle(uid,request['command'])
        status, error, resource, token = 'accepted', None, None, None
        try:
            # Nested transaction is a SAVEPOINT: rejected commands roll back all changes,
            # while their durable receipt and rate accounting remain in the outer transaction.
            with self.conn.transaction():
                resource, token = self.apply(s,request['command'],request['payload'])
        except RuleError as exc:
            status,error = 'rejected',exc.code
        encrypted = Fernet(os.environ['RECEIPT_KEY'].encode()).encrypt(token.encode()).decode() if token else None
        self.run('''INSERT INTO nidaa.operations(actor_id,operation_id,fingerprint,status,resource_id,error,created_at,token_ciphertext)
          VALUES(%s,%s,%s,%s,%s,%s,%s,%s)''', (uid,op,fingerprint,status,resource,error,self.now,encrypted))
        self.erase_tokens()
        return self.receipt(uid,op)

    def restrict_pair(self, sender, recipient, state):
        known=self.one('''SELECT 1 FROM nidaa.grants WHERE sender_id=%s AND recipient_id=%s
          UNION ALL SELECT 1 FROM nidaa.invitations WHERE sender_id=%s
            AND intended_email=(SELECT email FROM nidaa.accounts WHERE user_id=%s)
          UNION ALL SELECT 1 FROM nidaa.alerts a JOIN nidaa.recipients r ON r.alert_id=a.alert_id
            WHERE a.sender_id=%s AND r.user_id=%s LIMIT 1''', (sender,recipient,sender,recipient,sender,recipient))
        if not known:
            return
        self.run('UPDATE nidaa.grants SET state=%s,version=version+1 WHERE sender_id=%s AND recipient_id=%s', (state,sender,recipient))
        self.run("UPDATE nidaa.invitations SET state=%s WHERE sender_id=%s AND intended_email=(SELECT email FROM nidaa.accounts WHERE user_id=%s) AND state IN('pending','accepted')", (state,sender,recipient))
        affected = self.all('''UPDATE nidaa.recipients r SET access=%s FROM nidaa.alerts a
          WHERE r.alert_id=a.alert_id AND a.sender_id=%s AND r.user_id=%s AND r.access='active' RETURNING r.alert_id''', (state,sender,recipient))
        for r in affected:
            self.run('UPDATE nidaa.alerts SET version=version+1 WHERE alert_id=%s', (r['alert_id'],))
            self.run("UPDATE nidaa.outbox SET state='suppressed' WHERE alert_id=%s AND recipient_id=%s AND state='queued'", (r['alert_id'],recipient))
            self.touch_alert(r['alert_id'])
        self.touch(sender,recipient)

    def restrict_account(self, uid, state):
        others = self.all('SELECT user_id FROM nidaa.accounts WHERE user_id<>%s', (uid,))
        for other in others:
            self.restrict_pair(uid,other['user_id'],state)
            self.restrict_pair(other['user_id'],uid,state)

    def delete_account(self, uid, subject=None, requested_at=None):
        a = self.one('SELECT * FROM nidaa.accounts WHERE user_id=%s', (uid,))
        if not a:
            return
        self.restrict_account(uid,'deleted')
        for alert in self.all("SELECT alert_id FROM nidaa.alerts WHERE sender_id=%s AND state='active'", (uid,)):
            self.finish(alert['alert_id'],'cancelled')
        self.run("UPDATE nidaa.invitations SET state='cancelled',intended_email='',token_digest=NULL WHERE sender_id=%s OR intended_email=%s", (uid,a['email']))
        self.run("UPDATE nidaa.accounts SET active=false,email='',display_name='Deleted account',cursor=cursor+1 WHERE user_id=%s", (uid,))
        self.run('UPDATE nidaa.sessions SET revoked=true WHERE user_id=%s', (uid,))
        self.run('UPDATE nidaa.operations SET token_ciphertext=NULL WHERE actor_id=%s', (uid,))
        self.run('''INSERT INTO nidaa.deletion_ledger(ledger_id,user_id,subject,requested_at) VALUES(%s,%s,%s,%s)
          ON CONFLICT(user_id) DO NOTHING''', (str(uuid4()),uid,subject or a['subject'],requested_at or self.now))

    def alert_for(self, uid, aid, sender=False, active=False, version=None):
        a = self.one('SELECT * FROM nidaa.alerts WHERE alert_id=%s', (aid,))
        require(a and (a['sender_id']==uid or self.one('SELECT 1 FROM nidaa.recipients WHERE alert_id=%s AND user_id=%s', (aid,uid))), 'not_found')
        if sender:
            require(a['sender_id']==uid,'forbidden')
        if active:
            require(a['state']=='active','terminal')
        if version is not None:
            require(a['version']==version,'conflict')
        return a

    def queue(self, a, recipient):
        r = self.one('SELECT * FROM nidaa.recipients WHERE alert_id=%s AND user_id=%s', (a['alert_id'],recipient))
        require(r['response']=='none' and r['attempts']<2,'limit_reached')
        require(r['access']=='active' and self.consent(a['sender_id'],recipient),'consent_required')
        require(not self.one("SELECT 1 FROM nidaa.outbox WHERE alert_id=%s AND recipient_id=%s AND state='queued'", (a['alert_id'],recipient)), 'conflict')
        self.run('UPDATE nidaa.recipients SET attempts=attempts+1 WHERE alert_id=%s AND user_id=%s', (a['alert_id'],recipient))
        self.run('INSERT INTO nidaa.outbox(job_id,alert_id,recipient_id,ordinal,created_at,deadline) VALUES(%s,%s,%s,%s,%s,%s)', (str(uuid4()),a['alert_id'],recipient,r['attempts']+1,self.now,a['expires_at']))

    def add(self, a, recipients):
        existing = {r['user_id'] for r in self.all('SELECT user_id FROM nidaa.recipients WHERE alert_id=%s', (a['alert_id'],))}
        require(len(existing | set(recipients))<=5,'limit_reached')
        require(not existing.intersection(recipients),'conflict')
        require(all(self.consent(a['sender_id'],r) for r in recipients),'consent_required')
        for r in recipients:
            self.run('INSERT INTO nidaa.recipients(alert_id,user_id) VALUES(%s,%s)', (a['alert_id'],r))
            self.queue(a,r)
        self.touch_alert(a['alert_id'])

    def apply(self, s, name, p):
        uid = s['user_id']
        if name in ('decide_invite','delete_account'):
            self.recent(s)
        if name=='invite':
            email = p['recipient_email'].strip().lower()
            require(email!=s['email'],'forbidden')
            active = self.one("SELECT count(*) AS n FROM nidaa.invitations WHERE sender_id=%s AND intended_email=%s AND state='pending'", (uid,email))['n']
            require(active<3,'limit_reached')
            # Generic issuance regardless of target existence; per-target cooling off.
            last = self.one('SELECT max(created_at) AS t FROM nidaa.invitations WHERE sender_id=%s AND intended_email=%s', (uid,email))['t']
            require(last is None or self.now-last>=60,'rate_limited')
            iid, token = str(uuid4()), secrets.token_urlsafe(32)
            self.run("INSERT INTO nidaa.invitations(invitation_id,sender_id,intended_email,token_digest,state,expires_at,created_at) VALUES(%s,%s,%s,%s,'pending',%s,%s)", (iid,uid,email,hashlib.sha256(token.encode()).hexdigest(),self.now+86400,self.now))
            target = self.one('SELECT user_id FROM nidaa.accounts WHERE email=%s AND active', (email,))
            self.touch(uid,target['user_id'] if target else None)
            return iid,token
        if name=='decide_invite':
            i = self.one('SELECT * FROM nidaa.invitations WHERE token_digest=%s', (hashlib.sha256(p['token'].encode()).hexdigest(),))
            require(i and i['intended_email']==s['email'] and i['sender_id']!=uid,'not_found')
            require(i['state']!='expired','expired')
            require(i['state']=='pending','conflict')
            require(not self.blocked(uid,i['sender_id']) and self.one('SELECT 1 FROM nidaa.accounts WHERE user_id=%s AND active', (i['sender_id'],)), 'forbidden')
            self.run('UPDATE nidaa.invitations SET state=%s,accepted_by=%s WHERE invitation_id=%s', (p['decision'],uid,i['invitation_id']))
            if p['decision']=='accepted':
                self.run("""INSERT INTO nidaa.grants(sender_id,recipient_id,state,invitation_id) VALUES(%s,%s,'accepted',%s)
                 ON CONFLICT(sender_id,recipient_id) DO UPDATE SET state='accepted',invitation_id=excluded.invitation_id,version=nidaa.grants.version+1""", (i['sender_id'],uid,i['invitation_id']))
            self.touch(uid,i['sender_id'])
            return i['invitation_id'],None
        if name=='cancel_invite':
            i = self.one('SELECT * FROM nidaa.invitations WHERE invitation_id=%s AND sender_id=%s', (p['invitation_id'],uid))
            require(i,'not_found'); require(i['state']=='pending','conflict')
            self.run("UPDATE nidaa.invitations SET state='cancelled' WHERE invitation_id=%s", (i['invitation_id'],))
            self.touch(uid)
            return i['invitation_id'],None
        if name=='withdraw':
            require(self.one("SELECT 1 FROM nidaa.grants WHERE sender_id=%s AND recipient_id=%s AND state='accepted'", (p['sender_id'],uid)),'not_found')
            self.restrict_pair(p['sender_id'],uid,'withdrawn')
            return None,None
        if name in ('block','unblock'):
            target = p['user_id']
            known = self.one('''SELECT 1 FROM nidaa.grants WHERE (sender_id=%s AND recipient_id=%s) OR (sender_id=%s AND recipient_id=%s)
             UNION ALL SELECT 1 FROM nidaa.invitations WHERE sender_id=%s AND intended_email=%s''', (uid,target,target,uid,target,s['email']))
            require(target!=uid and known,'not_found')
            if name=='block':
                self.run('INSERT INTO nidaa.blocks VALUES(%s,%s,%s) ON CONFLICT DO NOTHING', (uid,target,self.now))
                self.restrict_pair(uid,target,'blocked'); self.restrict_pair(target,uid,'blocked')
            else:
                self.run('DELETE FROM nidaa.blocks WHERE blocker_id=%s AND target_id=%s', (uid,target))
                self.touch(uid,target)
            return None,None
        if name=='create_alert':
            require(0<p['expires_at']-self.now<=900,'expired')
            aid = str(uuid4())
            self.run("INSERT INTO nidaa.alerts(alert_id,sender_id,state,version,created_at,expires_at) VALUES(%s,%s,'active',1,%s,%s)", (aid,uid,self.now,p['expires_at']))
            a = self.one('SELECT * FROM nidaa.alerts WHERE alert_id=%s', (aid,))
            self.add(a,p['recipient_ids'])
            return aid,None
        if name=='delete_account':
            self.delete_account(uid)
            return uid,None
        a = self.alert_for(uid,p['alert_id'])
        aid = a['alert_id']
        if name=='hide_history':
            require(a['state']!='active','conflict')
            self.run('INSERT INTO nidaa.history_hides VALUES(%s,%s,%s) ON CONFLICT DO NOTHING', (uid,aid,self.now))
            self.touch(uid)
            return aid,None
        if name in ('retry','add_recipients','close_alert'):
            self.alert_for(uid,aid,sender=True,active=True,version=p['expected_version'])
            if name=='close_alert':
                self.finish(aid,p['state'])
            elif name=='add_recipients':
                self.add(a,p['recipient_ids'])
                self.run('UPDATE nidaa.alerts SET version=version+1 WHERE alert_id=%s', (aid,))
            else:
                candidates = [r for r in self.all("SELECT * FROM nidaa.recipients WHERE alert_id=%s AND response='none' AND access='active' AND attempts<2", (aid,)) if self.consent(uid,r['user_id']) and not self.one("SELECT 1 FROM nidaa.outbox WHERE alert_id=%s AND recipient_id=%s AND state='queued'", (aid,r['user_id']))]
                require(candidates,'limit_reached')
                for r in candidates:
                    last = self.one('SELECT max(created_at) AS t FROM nidaa.outbox WHERE alert_id=%s AND recipient_id=%s', (aid,r['user_id']))['t']
                    require(last is not None and self.now-last>=60,'rate_limited')
                for r in candidates:
                    self.queue(a,r['user_id'])
                self.run('UPDATE nidaa.alerts SET version=version+1 WHERE alert_id=%s', (aid,))
            self.touch_alert(aid)
            return aid,None
        r = self.one('SELECT * FROM nidaa.recipients WHERE alert_id=%s AND user_id=%s', (aid,uid))
        require(r,'forbidden')
        require(r['access']=='active' and self.consent(a['sender_id'],uid),'consent_required')
        require(a['state']=='active','terminal')
        if name=='respond':
            require(a['version']==p['expected_version'] and r['response']=='none','conflict')
            self.run('UPDATE nidaa.recipients SET response=%s,response_version=%s WHERE alert_id=%s AND user_id=%s', (p['response'],a['version']+1,aid,uid))
            self.run('UPDATE nidaa.alerts SET version=version+1 WHERE alert_id=%s', (aid,))
            self.run("UPDATE nidaa.outbox SET state='suppressed' WHERE alert_id=%s AND recipient_id=%s AND state='queued'", (aid,uid))
        elif name=='acknowledge':
            old = self.one('SELECT kind FROM nidaa.acknowledgements WHERE alert_id=%s AND user_id=%s AND device_id=%s AND event_id=%s', (aid,uid,s['device_id'],p['event_id']))
            require(not old or old['kind']==p['kind'],'conflict')
            self.run('INSERT INTO nidaa.acknowledgements VALUES(%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING', (aid,uid,s['device_id'],p['event_id'],p['kind'],self.now))
        else:
            raise RuleError('invalid_request')
        self.touch_alert(aid)
        return aid,None

    def view(self, uid, aid):
        a = self.alert_for(uid,aid)
        require(a['closed_at'] is None or self.now-a['closed_at']<30*86400,'not_found')
        require(not self.one('SELECT 1 FROM nidaa.history_hides WHERE user_id=%s AND alert_id=%s', (uid,aid)),'not_found')
        recipients = []
        for r in self.all('SELECT * FROM nidaa.recipients WHERE alert_id=%s ORDER BY user_id', (aid,)):
            if uid!=a['sender_id'] and uid!=r['user_id']:
                continue
            if uid!=a['sender_id']:
                require(r['access']=='active' and self.consent(a['sender_id'],uid),'not_found')
            kinds = {v['kind'] for v in self.all('SELECT kind FROM nidaa.acknowledgements WHERE alert_id=%s AND user_id=%s', (aid,r['user_id']))}
            recipients.append(dict(user_id=r['user_id'],response=r['response'],response_version=r['response_version'],access='active' if r['access']=='active' else 'unavailable',provider_accepted=r['provider_accepted'],app_acknowledged=bool(kinds),opened='opened' in kinds))
        result = {k:a[k] for k in ('alert_id','sender_id','state','version','expires_at','closed_at')}
        result['recipients']=recipients
        validate('Alert',result)
        return result

    def account(self, s):
        return dict(user_id=s['user_id'],display_name=s['display_name'],email_verified=True)

    def relationships(self, s):
        uid=s['user_id']; invitations=[]
        for i in self.all('SELECT * FROM nidaa.invitations WHERE sender_id=%s OR intended_email=%s ORDER BY created_at,invitation_id', (uid,s['email'])):
            outgoing=i['sender_id']==uid; state=i['state']
            if state=='deleted' or (outgoing and state in ('blocked','withdrawn')):
                state='unavailable'
            invitations.append(dict(invitation_id=i['invitation_id'],sender_id=i['sender_id'],direction='outgoing' if outgoing else 'incoming',state=state,expires_at=i['expires_at']))
        grants=[dict(sender_id=g['sender_id'],recipient_id=g['recipient_id'],state='accepted' if g['state']=='accepted' else 'unavailable') for g in self.all('SELECT * FROM nidaa.grants WHERE sender_id=%s OR recipient_id=%s ORDER BY sender_id,recipient_id', (uid,uid))]
        return dict(invitations=invitations,grants=grants)

    def sync(self, s):
        uid=s['user_id']; alerts=[]
        removed={r['alert_id'] for r in self.all('SELECT alert_id FROM nidaa.removals WHERE user_id=%s', (uid,))}
        for a in self.all('''SELECT DISTINCT a.alert_id FROM nidaa.alerts a LEFT JOIN nidaa.recipients r ON r.alert_id=a.alert_id
          WHERE a.sender_id=%s OR r.user_id=%s ORDER BY a.alert_id''', (uid,uid)):
            try:
                alerts.append(self.view(uid,a['alert_id']))
            except RuleError as e:
                if e.code!='not_found': raise
                removed.add(a['alert_id'])
        cursor=self.one('SELECT cursor FROM nidaa.accounts WHERE user_id=%s', (uid,))['cursor']
        return dict(cursor=cursor,full_snapshot=True,alerts=alerts,removed_ids=sorted(removed))

    def revoke(self, s, all_devices=False):
        if all_devices:
            self.recent(s)
            self.run('UPDATE nidaa.accounts SET revoked_before=%s WHERE user_id=%s', (self.now,s['user_id']))
            self.run('UPDATE nidaa.sessions SET revoked=true WHERE user_id=%s', (s['user_id'],))
        else:
            self.run('UPDATE nidaa.sessions SET revoked=true WHERE session_id=%s', (s['session_id'],))

    def dispatch(self, job_id=None, crash=False):
        self.expire()
        jobs=self.all("SELECT * FROM nidaa.outbox WHERE state='queued' ORDER BY created_at,job_id") if job_id is None else self.all('SELECT * FROM nidaa.outbox WHERE job_id=%s', (job_id,))
        results=[]
        for j in jobs:
            if j['state']!='queued':
                results.append(dict(job_id=j['job_id'],state=j['state']));continue
            a=self.one('SELECT * FROM nidaa.alerts WHERE alert_id=%s', (j['alert_id'],))
            r=self.one('SELECT * FROM nidaa.recipients WHERE alert_id=%s AND user_id=%s', (j['alert_id'],j['recipient_id']))
            valid=a and r and a['state']=='active' and self.now<min(a['expires_at'],j['deadline']) and r['response']=='none' and r['access']=='active' and self.consent(a['sender_id'],j['recipient_id'])
            state='provider_accepted' if valid else 'suppressed'
            if valid:
                self.run('INSERT INTO nidaa.fake_handoffs(job_id,accepted_at) VALUES(%s,%s) ON CONFLICT DO NOTHING', (j['job_id'],self.now))
                # Internal CLI/test-only crash, after fake acceptance insert but before commit.
                if crash: raise RuntimeError('injected_worker_rollback')
                self.run('UPDATE nidaa.recipients SET provider_accepted=true WHERE alert_id=%s AND user_id=%s', (j['alert_id'],j['recipient_id']))
            self.run('UPDATE nidaa.outbox SET state=%s WHERE job_id=%s', (state,j['job_id']))
            self.touch_alert(j['alert_id'])
            results.append(dict(job_id=j['job_id'],state=state))
        return results

    def purge(self):
        self.expire()
        expired=self.all('SELECT alert_id,sender_id FROM nidaa.alerts WHERE closed_at<=%s', (self.now-30*86400,))
        for a in expired:
            users={a['sender_id']}|{r['user_id'] for r in self.all('SELECT user_id FROM nidaa.recipients WHERE alert_id=%s', (a['alert_id'],))}
            for uid in users:
                self.run('INSERT INTO nidaa.removals VALUES(%s,%s,%s) ON CONFLICT DO NOTHING', (uid,a['alert_id'],self.now))
            self.touch(*users)
            self.run('DELETE FROM nidaa.alerts WHERE alert_id=%s', (a['alert_id'],))
        self.run('DELETE FROM nidaa.operations WHERE created_at<=%s', (self.now-90*86400,))
        self.run('DELETE FROM nidaa.invitations WHERE expires_at<=%s', (self.now-30*86400,))
        self.run('DELETE FROM nidaa.rate_events WHERE created_at<=%s', (self.now-86400,))
        self.run('DELETE FROM nidaa.removals WHERE created_at<=%s', (self.now-90*86400,))
        return dict(purged_alerts=len(expired))
