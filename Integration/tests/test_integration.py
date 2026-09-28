"""Real HTTP/PostgreSQL authorization and failure tests, using isolated local identities."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import secrets
import socket
import threading
import time
import unittest
from uuid import uuid4

import httpx
import jwt
import psycopg

from harness import AUTH, BASE, LocalAccount, admin, check, consent, envelope, mutate, sql


class IntegrationCase(unittest.TestCase):
    def setUp(self):
        self.clients = []
        self.addCleanup(lambda: [client.close() for client in self.clients])
        for name in ("Sami", "Sara", "Noor"):
            client = LocalAccount(name)
            self.clients.append(client)
            client.signup()
            client.me()
        self.a, self.b, self.c = self.clients

    def b_second(self):
        result = self.b.second_session()
        self.clients.append(result)
        result.me()
        return result

    def create(self):
        consent(self.a, self.b)
        return self.a.accepted("create_alert", recipient_ids=[self.b.user_id],
                               expires_at=int(time.time()) + 600)["resource_id"]

    def get(self, client, path):
        return check(client.request("GET", path), 200, "authenticated view").json()

    def row(self, table, aid):
        return sql("SELECT * FROM nidaa." + table + " WHERE alert_id=%s", (aid,))


class DomainIntegration(IntegrationCase):
    def test_uppercase_swift_uuids_work_and_case_duplicates_reject_atomically(self):
        consent(self.a, self.b)
        aid = self.a.accepted("create_alert", recipient_ids=[self.b.user_id.upper()], expires_at=int(time.time())+600)["resource_id"]
        self.b.accepted("acknowledge", alert_id=aid.upper(), event_id=str(uuid4()).upper(), kind="opened")
        self.b.accepted("respond", alert_id=aid.upper(), expected_version=1, response="responding")
        self.assertEqual(self.a.alert(aid)["recipients"][0]["response"], "responding")
        self.assertEqual(self.a.command("add_recipients", alert_id=aid.upper(), expected_version=2,
                                       recipient_ids=[self.b.user_id.upper()])["error"], "conflict")
        duplicate = self.a.command("create_alert", recipient_ids=[self.b.user_id.lower(),self.b.user_id.upper()],
                                   expires_at=int(time.time())+600)
        self.assertEqual(duplicate["status"], "rejected")
        self.assertEqual(duplicate["error"], "invalid_request")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.alerts WHERE sender_id=%s", (self.a.user_id,))[0]["n"], 1)

    def test_duplicate_operation_and_conflicting_payload(self):
        consent(self.a, self.b)
        request = envelope("create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time()) + 600)
        first = check(self.a.submit(request), 200, "first command").json()
        second = check(self.a.submit(request), 200, "duplicate command").json()
        self.assertEqual(first, second)
        self.assertEqual(len(self.row("alerts", first["resource_id"])), 1)
        self.assertEqual(len(self.row("outbox", first["resource_id"])), 1)
        changed = deepcopy(request)
        changed["payload"]["expires_at"] += 1
        check(self.a.submit(changed), 409, "operation payload conflict")

    def test_lost_response_reconciles_same_receipt(self):
        consent(self.a, self.b)
        request = envelope("create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time()) + 600)
        upstream_status = []

        class DropCommittedResponse(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass  # The test proxy never emits headers, URLs, credentials or bodies.

            def do_POST(self):
                try:
                    body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    with httpx.Client(timeout=15, trust_env=False) as upstream:
                        response = upstream.post(BASE+"/v1/commands", content=body,
                            headers={"Content-Type":"application/json", "Authorization":self.headers.get("Authorization", "")})
                        # API commits its transaction before returning HTTP 200. The proxy
                        # receives that response but sends no status, headers or body onward.
                        upstream_status.append(response.status_code)
                except Exception:
                    upstream_status.append(0)
                finally:
                    self.close_connection = True
                    try:
                        self.connection.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    self.connection.close()

        proxy = ThreadingHTTPServer(("127.0.0.1", 0), DropCommittedResponse)
        thread = threading.Thread(target=proxy.serve_forever, daemon=True)
        thread.start()
        try:
            with httpx.Client(timeout=20, trust_env=False) as downstream:
                with self.assertRaises(httpx.RemoteProtocolError):
                    downstream.post(f"http://127.0.0.1:{proxy.server_port}/v1/commands", json=request,
                        headers={"Authorization":"Bearer "+self.a.session["access_token"]})
        finally:
            proxy.shutdown()
            proxy.server_close()
            thread.join(timeout=5)
        self.assertEqual(upstream_status, [200], "test proxy did not observe committed acceptance")
        result = self.get(self.a, "/v1/operations/" + request["operation_id"])
        self.assertEqual(result["status"], "accepted")
        self.assertEqual(len(self.row("alerts", result["resource_id"])), 1)
        self.assertEqual(len(self.row("outbox", result["resource_id"])), 1)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.alerts WHERE sender_id=%s", (self.a.user_id,))[0]["n"], 1)
        check(self.c.request("GET", "/v1/operations/" + request["operation_id"]), 404, "operation owner scope")
        check(self.a.request("GET", "/v1/operations/" + str(uuid4())), 404, "unknown operation")

    def test_parallel_duplicate_commands_commit_once(self):
        consent(self.a, self.b)
        other = self.a.second_session()
        self.clients.append(other)
        request = envelope("create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time()) + 600)
        with ThreadPoolExecutor(2) as pool:
            responses = list(pool.map(lambda client: check(client.submit(request), 200, "concurrent duplicate").json(), [self.a, other]))
        self.assertEqual(responses[0], responses[1])
        self.assertEqual(len(self.row("outbox", responses[0]["resource_id"])), 1)

    def test_two_sessions_conflicting_responses_first_commit_wins(self):
        aid = self.create()
        b2 = self.b_second()
        actions = [(self.b, "responding"), (b2, "declined")]
        with ThreadPoolExecutor(2) as pool:
            results = list(pool.map(lambda pair: pair[0].command("respond", alert_id=aid,
                expected_version=1, response=pair[1]), actions))
        self.assertEqual(sorted(result["status"] for result in results), ["accepted", "rejected"])
        self.assertEqual(next(result["error"] for result in results if result["status"] == "rejected"), "conflict")
        view = self.a.alert(aid)
        self.assertEqual(view["version"], 2)
        self.assertIn(view["recipients"][0]["response"], ("responding", "declined"))
        self.assertEqual(b2.command("respond", alert_id=aid, expected_version=2, response="declined")["error"], "conflict")

    def test_two_devices_ack_independent_and_event_semantics_immutable(self):
        aid = self.create()
        b2 = self.b_second()
        event = str(uuid4())
        self.b.accepted("acknowledge", alert_id=aid, event_id=event, kind="app_acknowledged")
        self.b.accepted("acknowledge", alert_id=aid, event_id=event, kind="app_acknowledged")
        self.assertEqual(self.b.command("acknowledge", alert_id=aid, event_id=event, kind="opened")["error"], "conflict")
        b2.accepted("acknowledge", alert_id=aid, event_id=event, kind="opened")
        rows = self.row("acknowledgements", aid)
        self.assertEqual(len(rows), 2)
        self.assertEqual(len({str(row["device_id"]) for row in rows}), 2)
        self.assertEqual(self.a.alert(aid)["version"], 1)

    def test_expired_invite_replay_cancel_and_wrong_target(self):
        invite = self.a.accepted("invite", recipient_email=self.b.email)
        self.assertEqual(self.c.command("decide_invite", token=invite["invitation_token"], decision="accepted")["error"], "not_found")
        mutate("UPDATE nidaa.invitations SET expires_at=%s WHERE invitation_id=%s", (int(time.time())-1, invite["resource_id"]))
        self.assertEqual(self.b.command("decide_invite", token=invite["invitation_token"], decision="accepted")["error"], "expired")
        mutate("UPDATE nidaa.invitations SET created_at=%s WHERE invitation_id=%s", (int(time.time())-61, invite["resource_id"]))
        invite = consent(self.a, self.b)
        self.assertEqual(self.b.command("decide_invite", token=invite["invitation_token"], decision="accepted")["error"], "conflict")
        receipt = self.get(self.a, "/v1/operations/" + invite["operation_id"])
        self.assertTrue(receipt["invitation_token"] is None, "used invitation still returned a secret")
        pending = self.a.accepted("invite", recipient_email=self.c.email)
        self.a.accepted("cancel_invite", invitation_id=pending["resource_id"])
        self.assertEqual(self.c.command("decide_invite", token=pending["invitation_token"], decision="accepted")["error"], "conflict")

    def test_invitation_receipt_token_encrypted_and_removed_after_use(self):
        invite = self.a.accepted("invite", recipient_email=self.b.email)
        row = sql("SELECT token_ciphertext FROM nidaa.operations WHERE actor_id=%s AND operation_id=%s",
                  (self.a.user_id, invite["operation_id"]))[0]
        self.assertTrue(row["token_ciphertext"])
        self.assertTrue(row["token_ciphertext"] != invite["invitation_token"], "receipt stored a plaintext invitation token")
        self.b.accepted("decide_invite", token=invite["invitation_token"], decision="accepted")
        self.assertTrue(sql("SELECT token_ciphertext FROM nidaa.operations WHERE actor_id=%s AND operation_id=%s",
                            (self.a.user_id, invite["operation_id"]))[0]["token_ciphertext"] is None, "used token was not erased")

    def test_withdraw_removes_detail_and_never_restores_old_alert(self):
        aid = self.create()
        self.b.accepted("withdraw", sender_id=self.a.user_id)
        check(self.b.request("GET", "/v1/alerts/" + aid), 404, "withdrawn detail")
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(self.a.alert(aid)["recipients"][0]["access"], "unavailable")
        mutate("UPDATE nidaa.invitations SET created_at=%s WHERE sender_id=%s", (int(time.time())-61, self.a.user_id))
        consent(self.a, self.b)
        check(self.b.request("GET", "/v1/alerts/" + aid), 404, "reconsent cannot resurrect old detail")

    def test_block_both_directions_and_unblock_grants_nothing(self):
        aid = self.create()
        consent(self.b, self.a)
        self.b.accepted("block", user_id=self.a.user_id)
        for sender, recipient in ((self.a, self.b), (self.b, self.a)):
            self.assertEqual(sender.command("create_alert", recipient_ids=[recipient.user_id], expires_at=int(time.time())+600)["error"], "consent_required")
        self.b.accepted("unblock", user_id=self.a.user_id)
        self.assertEqual(self.a.command("create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time())+600)["error"], "consent_required")
        check(self.b.request("GET", "/v1/alerts/"+aid), 404, "old blocked detail")

    def test_withdraw_racing_send_has_no_live_queued_delivery_afterward(self):
        consent(self.a, self.b)
        with ThreadPoolExecutor(2) as pool:
            create = pool.submit(self.a.command, "create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time())+600)
            withdraw = pool.submit(self.b.accepted, "withdraw", sender_id=self.a.user_id)
            result = create.result()
            withdraw.result()
        self.assertIn(result["status"], ("accepted", "rejected"))
        if result["status"] == "accepted":
            self.assertEqual(self.row("outbox", result["resource_id"])[0]["state"], "suppressed")
        else:
            self.assertEqual(result["error"], "consent_required")

    def test_multirecipient_rejection_rolls_back_entire_transaction(self):
        consent(self.a, self.b)
        result = self.a.command("create_alert", recipient_ids=[self.b.user_id, self.c.user_id], expires_at=int(time.time())+600)
        self.assertEqual(result["status"], "rejected")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.alerts WHERE sender_id=%s", (self.a.user_id,))[0]["n"], 0)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.outbox o JOIN nidaa.alerts a USING(alert_id) WHERE a.sender_id=%s", (self.a.user_id,))[0]["n"], 0)
        self.assertEqual(self.get(self.a, "/v1/operations/"+result["operation_id"])["status"], "rejected")

    def test_sender_and_third_party_cannot_forge_response_or_global_close(self):
        aid = self.create()
        for client in (self.a, self.c):
            result = client.command("respond", alert_id=aid, expected_version=1, response="responding")
            self.assertEqual(result["status"], "rejected")
        self.assertEqual(self.b.command("close_alert", alert_id=aid, expected_version=1, state="resolved")["error"], "forbidden")
        forged = envelope("respond", alert_id=aid, expected_version=1, response="responding")
        forged["payload"]["user_id"] = self.b.user_id
        check(self.c.submit(forged), 400, "forged response identity")
        self.assertEqual(self.a.alert(aid)["version"], 1)

    def test_expiry_and_late_events_do_not_reopen(self):
        aid = self.create()
        mutate("UPDATE nidaa.alerts SET created_at=%s,expires_at=%s WHERE alert_id=%s", (int(time.time())-100, int(time.time())-1, aid))
        view = self.a.alert(aid)
        self.assertEqual(view["state"], "expired")
        self.assertEqual(self.b.command("respond", alert_id=aid, expected_version=view["version"], response="responding")["error"], "terminal")
        self.assertEqual(self.b.command("acknowledge", alert_id=aid, event_id=str(uuid4()), kind="opened")["error"], "terminal")
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")

    def test_terminal_history_hide_is_personal(self):
        aid = self.create()
        self.assertEqual(self.b.command("hide_history", alert_id=aid)["error"], "conflict")
        self.a.accepted("close_alert", alert_id=aid, expected_version=1, state="resolved")
        self.b.accepted("hide_history", alert_id=aid)
        check(self.b.request("GET", "/v1/alerts/"+aid), 404, "personal hidden history")
        self.assertEqual(self.a.alert(aid)["state"], "resolved")

    def test_stale_request_and_strict_request_size_fields(self):
        request = envelope("invite", recipient_email=self.b.email)
        request["issued_at"] -= 61
        check(self.a.submit(request), 410, "stale offline command")
        request = envelope("invite", recipient_email=self.b.email)
        request["face_id_success"] = True
        check(self.a.submit(request), 400, "client biometric assertion")
        oversized = self.a.request("POST", "/v1/commands", content=b" "*17000, headers={"Content-Type":"application/json"})
        check(oversized, (400, 413), "oversized request")
        self.assertTrue(self.a.email not in oversized.text, "error response exposed an identity")

    def test_invitation_acceptance_and_daily_issuance_limits(self):
        for _ in range(5):
            result = self.c.command("decide_invite", token=secrets.token_urlsafe(32), decision="accepted")
            self.assertEqual(result["error"], "not_found")
        check(self.c.submit(envelope("decide_invite", token=secrets.token_urlsafe(32), decision="accepted")), 429, "invitation guessing limit")
        for _ in range(10):
            self.a.accepted("invite", recipient_email=f"nidaa-{uuid4().hex}@example.invalid")
        check(self.a.submit(envelope("invite", recipient_email=self.b.email)), 429, "daily issuance limit")

    def test_target_cooldown_and_three_pending_invitation_limit(self):
        self.a.accepted("invite", recipient_email=self.b.email)
        self.assertEqual(self.a.command("invite", recipient_email=self.b.email)["error"], "rate_limited")
        for _ in range(2):
            mutate("UPDATE nidaa.invitations SET created_at=%s WHERE sender_id=%s", (int(time.time())-61, self.a.user_id))
            self.a.accepted("invite", recipient_email=self.b.email)
        mutate("UPDATE nidaa.invitations SET created_at=%s WHERE sender_id=%s", (int(time.time())-61, self.a.user_id))
        self.assertEqual(self.a.command("invite", recipient_email=self.b.email)["error"], "limit_reached")

    def test_authenticated_roles_cannot_read_or_directly_write_tables(self):
        aid = self.create()
        # These claims originate in actual local Auth login. Administrator is used only
        # to establish an independent direct-SQL role probe, not for the HTTP journey.
        claims = jwt.decode(self.c.session["access_token"], options={"verify_signature":False})
        with admin() as connection:
            connection.execute("SET LOCAL ROLE authenticated")
            connection.execute("SELECT set_config('request.jwt.claims',%s,true)", (json.dumps(claims),))
            self.assertEqual(connection.execute("SELECT count(*) AS n FROM nidaa.alerts").fetchone()["n"], 0)
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                connection.execute("UPDATE nidaa.alerts SET state='resolved',closed_at=1 WHERE alert_id=%s", (aid,))

    def test_runtime_role_cannot_read_provider_passwords_refresh_tokens_or_full_sessions(self):
        claims = jwt.decode(self.a.session["access_token"], options={"verify_signature":False})
        with psycopg.connect(os.environ["DATABASE_URL"]) as connection:
            verified = connection.execute("""SELECT u.id,s.id FROM auth.users u
                JOIN auth.sessions s ON s.user_id=u.id
                WHERE u.id=%s AND s.id=%s AND u.email_confirmed_at IS NOT NULL""",
                (claims["sub"],claims["session_id"])).fetchone()
            self.assertTrue(verified is not None, "runtime role cannot perform its required identity/session check")
            for statement in ("SELECT encrypted_password FROM auth.users LIMIT 0",
                              "SELECT token FROM auth.refresh_tokens LIMIT 0",
                              "SELECT * FROM auth.sessions LIMIT 0"):
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    with connection.transaction():
                        connection.execute(statement)

    def test_sync_is_account_scoped_ordered_and_tombstones_remove(self):
        aid = self.create()
        first = self.get(self.b, "/v1/sync")
        outsider = self.get(self.c, "/v1/sync")
        self.assertTrue(first["full_snapshot"])
        self.assertIn(aid, {item["alert_id"] for item in first["alerts"]})
        self.b.accepted("acknowledge", alert_id=aid, event_id=str(uuid4()), kind="opened")
        second = self.get(self.b, "/v1/sync")
        self.assertGreater(second["cursor"], first["cursor"])
        self.assertEqual(self.get(self.c, "/v1/sync")["cursor"], outsider["cursor"])
        self.b.accepted("withdraw", sender_id=self.a.user_id)
        removed = self.get(self.b, "/v1/sync")
        self.assertNotIn(aid, {item["alert_id"] for item in removed["alerts"]})
        self.assertIn(aid, removed["removed_ids"])


class AuthenticationIntegration(IntegrationCase):
    def test_unverified_signup_cannot_login(self):
        pending = LocalAccount("Sara")
        self.clients.append(pending)
        pending.signup(verify=False)
        check(pending.http.post(AUTH+"/token?grant_type=password", json={"email":pending.email,"password":pending.password}), (400, 401), "unverified login")

    def test_invalid_expired_wrong_audience_and_issuer_tokens(self):
        original = self.a.session["access_token"]
        payload = jwt.decode(original, options={"verify_signature":False})
        variants = [jwt.encode(payload, "deliberately-wrong-local-test-signing-key", algorithm="HS256")]
        for change in ({"exp":int(time.time())-1}, {"aud":"unrelated"}, {"iss":"https://invalid.example.invalid"}):
            altered = dict(payload, **change)
            variants.append(jwt.encode(altered, os.environ["JWT_SECRET"], algorithm="HS256"))
        for token in variants:
            self.a.session["access_token"] = token
            check(self.a.request("GET", "/v1/me"), 401, "invalid provider token")
        self.a.session["access_token"] = original

    def test_refresh_keeps_account_and_does_not_create_device(self):
        before = sql("SELECT count(*) AS n FROM nidaa.sessions WHERE user_id=%s", (self.a.user_id,))[0]["n"]
        uid = self.a.user_id
        self.a.refresh()
        self.assertEqual(self.a.me()["user_id"], uid)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.sessions WHERE user_id=%s", (uid,))[0]["n"], before)

    def test_logout_current_and_revoke_all_with_two_sessions(self):
        b2 = self.b_second()
        check(self.b.request("POST", "/v1/session/logout", json={}), 204, "session logout")
        check(self.b.request("GET", "/v1/me"), 401, "old token after logout")
        self.assertEqual(b2.me()["user_id"], self.b.user_id)
        b3 = b2.second_session()
        self.clients.append(b3)
        b3.me()
        check(b2.request("POST", "/v1/session/revoke-all", json={}), 204, "all session revocation")
        for client in (b2, b3):
            check(client.request("GET", "/v1/me"), 401, "old token after revoke all")

    def test_actual_local_recovery_email_changes_password(self):
        old = self.a.password
        check(self.a.http.post(AUTH+"/recover", json={"email":self.a.email}), 200, "local recovery request")
        recovered = self.a.verify_mail("recovery")
        self.assertTrue("access_token" in recovered, "recovery did not issue a provider session")
        self.a.password = "Nidaa!" + secrets.token_urlsafe(24)
        check(self.a.http.put(AUTH+"/user", headers={"Authorization":"Bearer "+recovered["access_token"]},
                             json={"password":self.a.password}), 200, "local recovery completion")
        check(self.a.request("GET", "/v1/me"), 401, "old session after recovery password change")
        check(self.a.http.post(AUTH+"/token?grant_type=refresh_token", json={"refresh_token":self.a.session["refresh_token"]}),
              (400, 401), "old refresh token after recovery")
        check(self.a.http.post(AUTH+"/token?grant_type=password", json={"email":self.a.email,"password":old}), (400, 401), "old recovered password")
        self.a.login()
        self.assertTrue(self.a.me()["email_verified"])

    def test_account_deletion_barrier_precedes_provider_cleanup(self):
        aid = self.create()
        b2 = self.b_second()
        unrelated_cursor = self.get(self.c, "/v1/sync")["cursor"]
        self.b.accepted("delete_account")
        for client in (self.b, b2):
            check(client.request("GET", "/v1/me"), 401, "deleted domain account")
        account = sql("SELECT active,email,display_name FROM nidaa.accounts WHERE user_id=%s", (self.b.user_id,))[0]
        self.assertFalse(account["active"])
        self.assertEqual(account["email"], "")
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(self.a.alert(aid)["recipients"][0]["access"], "unavailable")
        self.assertEqual(len(sql("SELECT * FROM nidaa.deletion_ledger WHERE user_id=%s", (self.b.user_id,))), 1)
        self.assertEqual(self.get(self.c, "/v1/sync")["cursor"], unrelated_cursor)

    def test_recent_auth_uses_signed_amr_not_refreshed_iat(self):
        # This is an explicit signing fixture, NOT a user login or verification bypass.
        # The session and identity first came from the real provider journey above.
        invite = self.a.accepted("invite", recipient_email=self.b.email)
        claims = jwt.decode(self.b.session["access_token"], options={"verify_signature":False})
        claims["amr"] = [{"method":"password", "timestamp":int(time.time())-601}]
        claims["iat"] = int(time.time())
        claims["exp"] = int(time.time())+3600
        self.b.session["access_token"] = jwt.encode(claims, os.environ["JWT_SECRET"], algorithm="HS256")
        self.assertEqual(self.b.command("decide_invite", token=invite["invitation_token"], decision="accepted")["error"], "reauthentication_required")
        self.assertEqual(self.b.command("delete_account")["error"], "reauthentication_required")
        check(self.b.request("POST", "/v1/session/revoke-all", json={}), 403, "stale auth revocation")
        claims["amr"] = [{"method":"token_refresh", "timestamp":int(time.time())}]
        self.b.session["access_token"] = jwt.encode(claims, os.environ["JWT_SECRET"], algorithm="HS256")
        self.assertEqual(self.b.command("decide_invite", token=invite["invitation_token"], decision="accepted")["error"], "reauthentication_required")
        self.b.login()
        self.b.accepted("decide_invite", token=invite["invitation_token"], decision="accepted")

    def test_real_provider_refresh_preserves_authentication_evidence(self):
        before = jwt.decode(self.b.session["access_token"], options={"verify_signature":False})
        self.assertTrue(before.get("amr"), "real provider omitted authentication evidence")
        self.b.refresh()
        after = jwt.decode(self.b.session["access_token"], options={"verify_signature":False})
        self.assertEqual(after["session_id"], before["session_id"])
        self.assertEqual(after["amr"], before["amr"])
        self.assertEqual(self.b.me()["user_id"], self.b.user_id)

    def test_provider_session_removal_and_account_disable_are_live_barriers(self):
        claims = jwt.decode(self.b.session["access_token"], options={"verify_signature":False})
        mutate("UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=%s", (claims["sub"],))
        check(self.b.request("GET", "/v1/me"), 401, "provider disabled account")
        mutate("UPDATE auth.users SET banned_until=NULL WHERE id=%s", (claims["sub"],))
        self.b.me()
        mutate("DELETE FROM auth.sessions WHERE id=%s", (claims["session_id"],))
        check(self.b.request("GET", "/v1/me"), 401, "removed provider session with unexpired JWT")

    def test_email_and_phone_changes_are_explicitly_disabled_at_trial_gateway(self):
        for update in ({"email":f"nidaa-{uuid4().hex}@example.invalid"}, {"phone":""}):
            check(self.a.request("PUT", "/auth/v1/user", json=update), 403, "deferred identity-attribute changes")
        subject = jwt.decode(self.a.session["access_token"], options={"verify_signature":False})["sub"]
        self.assertTrue(sql("SELECT email FROM auth.users WHERE id=%s", (subject,))[0]["email"] == self.a.email,
                        "gateway changed a deferred identity attribute")


if __name__ == "__main__":
    unittest.main()
