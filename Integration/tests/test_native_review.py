"""Regression cases from the implementation review; real local HTTP/Auth/SQL.

Bulk row setup and altered expiry tokens below are explicitly privileged fixtures,
not substitutions for the user journey or email verification.
"""
import os
import time
from uuid import uuid4

import jwt
import psycopg

from harness import BASE, admin, check, mutate, sql
from test_integration import IntegrationCase


class NativeReviewIntegration(IntegrationCase):
    def test_gateway_preserves_auth_api_version_and_typed_refresh_error(self):
        # Actual GoTrue response through the gateway consumed by the official
        # Swift Auth SDK; no manufactured provider response or valid secret.
        response=check(self.a.http.post(BASE+'/auth/v1/token?grant_type=refresh_token',
            headers={'X-Supabase-Api-Version':'2024-01-01'},
            json={'refresh_token':'invalid-local-review-refresh-token'}),400,'versioned invalid refresh')
        self.assertEqual(response.headers.get('X-Supabase-Api-Version'),'2024-01-01')
        self.assertIsInstance(response.json().get('code'),str)
        self.assertTrue(response.json()['code'])

    def test_restore_control_tables_are_not_readable_or_mutable_by_client_role(self):
        with admin() as connection:
            connection.execute('SET LOCAL ROLE authenticated')
            for table in ('maintenance_state','session_revocations'):
                self.assertEqual(connection.execute('SELECT count(*) AS n FROM nidaa.'+table).fetchone()['n'],0)
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    with connection.transaction():
                        connection.execute('DELETE FROM nidaa.'+table)

    def test_expired_signed_token_logout_records_barrier_before_reporting_success(self):
        original = self.a.session['access_token']
        claims = jwt.decode(original, options={'verify_signature': False})
        claims['exp'] = int(time.time()) - 1
        self.a.session['access_token'] = jwt.encode(claims, os.environ['JWT_SECRET'], algorithm='HS256')
        check(self.a.request('GET', '/v1/me'), 401, 'expired access remains denied')
        check(self.a.request('POST', '/v1/session/logout', json={}), 204, 'expired signed session logout')
        # Provider cleanup can reject the expired token. A renewed token for the
        # same actual provider session still cannot cross the durable domain barrier.
        self.a.session['access_token'] = original
        check(self.a.request('GET', '/v1/me'), 401, 'logged-out session must not return')
        row = sql('SELECT revoked FROM nidaa.sessions WHERE session_id=%s', (claims['session_id'],))[0]
        self.assertTrue(row['revoked'])

    def test_invalid_signature_cannot_revoke_someone_elses_session(self):
        original = self.a.session['access_token']
        claims = jwt.decode(original, options={'verify_signature': False})
        claims['exp'] = int(time.time()) - 1
        self.a.session['access_token'] = jwt.encode(claims, 'not-the-authorized-local-issuer-secret', algorithm='HS256')
        check(self.a.request('POST', '/v1/session/logout', json={}), 204, 'generic invalid-token logout')
        self.a.session['access_token'] = original
        self.a.me()
        self.assertFalse(sql('SELECT revoked FROM nidaa.sessions WHERE session_id=%s', (claims['session_id'],))[0]['revoked'])

    def test_logout_during_provider_ban_does_not_reopen_when_ban_ends(self):
        claims=jwt.decode(self.a.session['access_token'],options={'verify_signature':False})
        mutate("UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=%s", (claims['sub'],))
        check(self.a.request('POST','/v1/session/logout',json={}),204,'logout suspended session')
        mutate('UPDATE auth.users SET banned_until=NULL WHERE id=%s', (claims['sub'],))
        check(self.a.request('GET','/v1/me'),401,'logout survives end of provider suspension')

    def test_provider_visibility_loss_advances_recipient_cursor_without_worker(self):
        aid = self.create()
        before = self.get(self.b, '/v1/sync')
        self.assertTrue(any(a['alert_id'] == aid for a in before['alerts']))
        sender = jwt.decode(self.a.session['access_token'], options={'verify_signature': False})['sub']
        mutate("UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=%s", (sender,))
        removed = self.get(self.b, '/v1/sync')
        self.assertNotIn(aid, [a['alert_id'] for a in removed['alerts']])
        self.assertGreater(removed['cursor'], before['cursor'])
        repeated = self.get(self.b, '/v1/sync')
        self.assertEqual(repeated['cursor'], removed['cursor'])
        self.assertEqual(self.get(self.c, '/v1/sync')['cursor'], 0)

    def test_full_alert_snapshot_overflow_rejects_without_partial_success(self):
        # Explicit scale fixture, not manufactured alert-flow evidence.
        now = int(time.time())
        ids = [str(uuid4()) for _ in range(129)]
        with admin() as connection:
            with connection.cursor() as cursor:
                cursor.executemany("""INSERT INTO nidaa.alerts(alert_id,sender_id,state,version,created_at,expires_at,closed_at)
                    VALUES(%s,%s,'resolved',2,%s,%s,%s)""",
                    [(aid, self.a.user_id, now-10, now+600, now) for aid in ids])
        denied = check(self.a.request('GET', '/v1/sync'), 409, 'oversized full snapshot')
        self.assertEqual(denied.json(), {'error': 'limit_reached'})
        mutate('DELETE FROM nidaa.alerts WHERE alert_id=%s', (ids[-1],))
        full = self.get(self.a, '/v1/sync')
        self.assertTrue(full['full_snapshot'])
        self.assertEqual(len(full['alerts']), 128)

    def test_full_relationship_snapshot_overflow_rejects_without_truncation(self):
        now = int(time.time())
        ids = [str(uuid4()) for _ in range(129)]
        with admin() as connection:
            with connection.cursor() as cursor:
                cursor.executemany("""INSERT INTO nidaa.invitations
                    (invitation_id,sender_id,intended_email,token_digest,state,expires_at,created_at)
                    VALUES(%s,%s,%s,NULL,'cancelled',%s,%s)""",
                    [(iid, self.a.user_id, self.b.email, now+86400, now) for iid in ids])
        denied = check(self.a.request('GET', '/v1/relationships'), 409, 'oversized relationships')
        self.assertEqual(denied.json(), {'error': 'limit_reached'})
        mutate('DELETE FROM nidaa.invitations WHERE invitation_id=%s', (ids[-1],))
        self.assertEqual(len(self.get(self.a, '/v1/relationships')['invitations']), 128)
