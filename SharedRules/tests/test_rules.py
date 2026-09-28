"""Rule simulations with A (Sami), B (Sara), C (Noor), and two B devices."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model import Server, LocalReplica, RuleError, command, validate, SCHEMA
from build_contract import SCHEMA as GENERATED_SCHEMA
from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError


class Rules(unittest.TestCase):
    def setUp(self):
        self.s = Server()
        self.a = self.s.fixture_account("sami@example.invalid", "Sami")
        self.b = self.s.fixture_account("sara@example.invalid", "Sara")
        self.c = self.s.fixture_account("noor@example.invalid", "Noor")
        self.sa = self.s.fixture_session(self.a)
        self.sb = self.s.fixture_session(self.b)
        self.sb2 = self.s.fixture_session(self.b)
        self.sc = self.s.fixture_session(self.c)

    def run_command(self, session, name, **payload):
        result = self.s.execute(session, command(self.s, name, **payload))
        validate("Receipt", result)
        return result

    def invite(self, email="sara@example.invalid"):
        return self.run_command(self.sa, "invite", recipient_email=email)

    def grant(self, recipient=None, session=None):
        invite = self.invite(self.s.users[recipient or self.b]["email"])
        result = self.run_command(session or self.sb, "decide_invite", token=invite["invitation_token"], decision="accepted")
        self.assertEqual(result["status"], "accepted")
        return invite

    def alert(self):
        self.grant()
        return self.run_command(self.sa, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 900)["resource_id"]

    def assert_error(self, code, call, *args):
        with self.assertRaises(RuleError) as context:
            call(*args)
        self.assertEqual(context.exception.code, code)
        validate("Error", {"error": code})

    def test_contract_is_valid_and_reproducible(self):
        Draft202012Validator.check_schema(SCHEMA)
        self.assertEqual(SCHEMA, GENERATED_SCHEMA)
        self.assertNotIn('"$ref"', json.dumps(SCHEMA))

    def test_unknown_fields_and_biometric_assertions_rejected(self):
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        req["face_id_success"] = True
        self.assert_error("invalid_request", self.s.execute, self.sa, req)
        req.pop("face_id_success")
        req["payload"]["actor_id"] = self.b
        self.assert_error("invalid_request", self.s.execute, self.sa, req)

    def test_schema_rejects_null_duplicates_bad_uuid_empty_and_enum(self):
        baseline = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        for value in (None, [], [self.b, self.b], ["Sara"]):
            req = deepcopy(baseline)
            req["payload"]["recipient_ids"] = value
            self.assert_error("invalid_request", self.s.execute, self.sa, req)
        req = command(self.s, "decide_invite", token="x" * 43, decision="automatic")
        self.assert_error("invalid_request", self.s.execute, self.sb, req)

    def test_names_do_not_identify_or_verify_accounts(self):
        self.s.users[self.c]["name"] = "Sara"
        i = self.invite()
        self.assertEqual(self.run_command(self.sc, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "not_found")
        unverified = self.s.fixture_session(self.b, verified=False)
        self.assert_error("unauthenticated", self.s.execute, unverified, command(self.s, "decide_invite", token=i["invitation_token"], decision="accepted"))

    def test_sender_cannot_accept_and_consent_is_directional(self):
        i = self.invite()
        self.assertEqual(self.run_command(self.sa, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "not_found")
        self.run_command(self.sb, "decide_invite", token=i["invitation_token"], decision="accepted")
        self.assertTrue(self.s.consent(self.a, self.b))
        self.assertFalse(self.s.consent(self.b, self.a))
        self.assertEqual(self.run_command(self.sb, "create_alert", recipient_ids=[self.a], expires_at=self.s.now + 60)["error"], "consent_required")

    def test_invite_replay_and_duplicate_operation(self):
        i = self.invite()
        req = command(self.s, "decide_invite", token=i["invitation_token"], decision="accepted")
        first = self.s.execute(self.sb, req)
        self.assertEqual(self.s.execute(self.sb2, req), first)
        self.assertEqual(self.run_command(self.sb2, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "conflict")

    def test_expired_invitation(self):
        i = self.invite()
        self.s.advance(self.s.INVITE_TTL)
        self.sb = self.s.fixture_session(self.b)
        self.assertEqual(self.run_command(self.sb, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "expired")
        self.assertFalse(self.s.consent(self.a, self.b))

    def test_declined_and_cancelled_invitations_cannot_accept(self):
        for decision in ("declined", "cancelled"):
            i = self.invite()
            if decision == "declined":
                self.run_command(self.sb, "decide_invite", token=i["invitation_token"], decision="declined")
            else:
                self.run_command(self.sa, "cancel_invite", invitation_id=i["resource_id"])
            self.assertEqual(self.run_command(self.sb, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "conflict")

    def test_invitation_guessing_and_flooding_are_bounded(self):
        for _ in range(5):
            self.run_command(self.sb, "decide_invite", token="x" * 43, decision="accepted")
        self.assert_error("rate_limited", self.s.execute, self.sb, command(self.s, "decide_invite", token="y" * 43, decision="accepted"))
        for _ in range(10):
            self.invite()
        self.assert_error("rate_limited", self.s.execute, self.sa, command(self.s, "invite", recipient_email="sara@example.invalid"))

    def test_acceptance_requires_recent_provider_auth_not_biometric(self):
        i = self.invite()
        self.s.advance(301)
        self.assertEqual(self.run_command(self.sb, "decide_invite", token=i["invitation_token"], decision="accepted")["error"], "reauthentication_required")
        fresh = self.s.fixture_session(self.b)
        self.assertEqual(self.run_command(fresh, "decide_invite", token=i["invitation_token"], decision="accepted")["status"], "accepted")

    def test_withdraw_before_execution_blocks_create(self):
        self.grant()
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        self.run_command(self.sb, "withdraw", sender_id=self.a)
        self.assertEqual(self.s.execute(self.sa, req)["error"], "consent_required")
        self.assertFalse(self.s.alerts)

    def test_withdraw_after_acceptance_suppresses_queue_and_details(self):
        aid = self.alert()
        job = self.s.outbox[0]["id"]
        self.run_command(self.sb, "withdraw", sender_id=self.a)
        self.assertEqual(self.s.dispatch(job), "suppressed")
        self.assert_error("not_found", self.s.view, self.sb, aid)
        self.assertIn(aid, self.s.sync(self.sb)["removed_ids"])
        self.assertEqual(self.s.view(self.sa, aid)["state"], "active")

    def test_block_during_send_and_unblock_does_not_restore(self):
        aid = self.alert()
        self.run_command(self.sb, "block", user_id=self.a)
        self.assertEqual(self.s.dispatch(self.s.outbox[0]["id"]), "suppressed")
        self.run_command(self.sb, "unblock", user_id=self.a)
        self.assertFalse(self.s.consent(self.a, self.b))
        self.assert_error("not_found", self.s.view, self.sb, aid)
        self.grant()
        self.assertTrue(self.s.consent(self.a, self.b))
        self.assert_error("not_found", self.s.view, self.sb, aid)

    def test_provider_handoff_before_block_is_not_retracted_or_delivery(self):
        aid = self.alert()
        job = self.s.outbox[0]["id"]
        self.assertEqual(self.s.dispatch(job), "provider_accepted")
        self.run_command(self.sb, "block", user_id=self.a)
        self.assertEqual(self.s.dispatch(job), "provider_accepted")
        r = self.s.view(self.sa, aid)["recipients"][0]
        self.assertTrue(r["provider_accepted"])
        self.assertFalse(r["app_acknowledged"])
        self.assertFalse(r["opened"])
        self.assertEqual(r["response"], "none")

    def test_lost_reply_queries_same_operation_and_duplicate_never_creates(self):
        self.grant()
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        accepted = self.s.execute(self.sa, req)
        self.assertEqual(self.s.receipt(self.sa, req["operation_id"]), accepted)
        self.assertEqual(self.s.execute(self.sa, req), accepted)
        self.assertEqual(len(self.s.alerts), 1)
        self.assertEqual(len(self.s.outbox), 1)

    def test_same_operation_different_payload_conflicts(self):
        self.grant()
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        self.s.execute(self.sa, req)
        req["payload"]["expires_at"] += 1
        self.assert_error("conflict", self.s.execute, self.sa, req)

    def test_operation_lookup_is_account_scoped(self):
        i = self.invite()
        self.assert_error("not_found", self.s.receipt, self.sc, i["operation_id"])

    def test_offline_never_dispatches_automatically(self):
        replica = LocalReplica()
        replica.switch_account(self.a)
        replica.record_offline(command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60))
        self.assertEqual(replica.pending["state"], "never_left")
        self.assertEqual(replica.reconnect(), "renew_confirmation_and_local_auth")
        self.assertFalse(self.s.alerts)
        replica.mark_attempted()
        self.assertEqual(replica.reconnect(), "query_same_operation")
        self.assertFalse(self.s.alerts)

    def test_stale_offline_command_is_rejected(self):
        self.grant()
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 900)
        self.s.advance(61)
        self.assert_error("expired", self.s.execute, self.sa, req)
        self.assertFalse(self.s.alerts)

    def test_third_account_cannot_read_change_or_forge_response(self):
        aid = self.alert()
        self.assert_error("not_found", self.s.view, self.sc, aid)
        self.assertEqual(self.s.sync(self.sc)["alerts"], [])
        for action, payload in (("respond", {"response": "responding", "expected_version": 1}),
                                ("close_alert", {"state": "resolved", "expected_version": 1}),
                                ("acknowledge", {"kind": "opened", "event_id": str(uuid4())})):
            self.assertEqual(self.run_command(self.sc, action, alert_id=aid, **payload)["error"], "not_found")
        self.assertEqual(self.s.view(self.sa, aid)["version"], 1)

    def test_two_devices_conflicting_responses_first_commit_wins(self):
        aid = self.alert()
        self.assertEqual(self.run_command(self.sb, "respond", alert_id=aid, expected_version=1, response="responding")["status"], "accepted")
        self.assertEqual(self.run_command(self.sb2, "respond", alert_id=aid, expected_version=1, response="declined")["error"], "conflict")
        self.assertEqual(self.run_command(self.sb2, "respond", alert_id=aid, expected_version=2, response="declined")["error"], "conflict")
        self.assertEqual(self.s.view(self.sb2, aid)["recipients"][0]["response"], "responding")

    def test_ack_per_device_duplicate_event_and_account_aggregate(self):
        aid = self.alert()
        event = str(uuid4())
        self.run_command(self.sb, "acknowledge", alert_id=aid, event_id=event, kind="app_acknowledged")
        self.run_command(self.sb, "acknowledge", alert_id=aid, event_id=event, kind="app_acknowledged")
        self.run_command(self.sb2, "acknowledge", alert_id=aid, event_id=str(uuid4()), kind="opened")
        r = self.s.alerts[aid]["recipients"][self.b]
        self.assertEqual(len(r["events"]), 2)
        self.assertEqual(len(r["acks"]), 2)
        observed = self.s.view(self.sa, aid)["recipients"][0]
        self.assertTrue(observed["app_acknowledged"] and observed["opened"])
        self.assertEqual(observed["response"], "none")

    def test_response_does_not_resolve_and_recipient_cannot_close(self):
        aid = self.alert()
        self.run_command(self.sb, "respond", alert_id=aid, expected_version=1, response="responding")
        self.assertEqual(self.s.view(self.sa, aid)["state"], "active")
        self.assertEqual(self.run_command(self.sb, "close_alert", alert_id=aid, expected_version=2, state="resolved")["error"], "forbidden")
        self.assertEqual(self.run_command(self.sa, "respond", alert_id=aid, expected_version=2, response="declined")["error"], "forbidden")

    def test_terminal_alert_rejects_late_events(self):
        aid = self.alert()
        self.run_command(self.sa, "close_alert", alert_id=aid, expected_version=1, state="resolved")
        for name, payload in (("respond", {"expected_version": 2, "response": "responding"}),
                              ("acknowledge", {"event_id": str(uuid4()), "kind": "opened"})):
            self.assertEqual(self.run_command(self.sb, name, alert_id=aid, **payload)["error"], "terminal")
        self.assertEqual(self.s.view(self.sa, aid)["state"], "resolved")

    def test_expiry_uses_server_clock_and_suppresses_worker(self):
        aid = self.alert()
        expiry = self.s.alerts[aid]["expires"]
        self.s.advance(900)
        self.assertEqual(self.s.dispatch(self.s.outbox[0]["id"]), "suppressed")
        self.assertEqual(self.s.view(self.sa, aid)["closed_at"], expiry)
        self.assertEqual(self.run_command(self.sa, "retry", alert_id=aid, expected_version=2)["error"], "terminal")

    def test_retry_bounded_and_expiry_not_extended(self):
        aid = self.alert()
        expiry = self.s.alerts[aid]["expires"]
        self.s.dispatch(self.s.outbox[0]["id"])
        self.assertEqual(self.run_command(self.sa, "retry", alert_id=aid, expected_version=1)["error"], "rate_limited")
        self.s.advance(60)
        self.assertEqual(self.run_command(self.sa, "retry", alert_id=aid, expected_version=1)["status"], "accepted")
        self.s.dispatch(self.s.outbox[1]["id"])
        self.s.advance(60)
        self.assertEqual(self.run_command(self.sa, "retry", alert_id=aid, expected_version=2)["error"], "limit_reached")
        self.assertEqual(self.s.alerts[aid]["expires"], expiry)

    def test_retry_excludes_responders_and_decliners(self):
        for response in ("responding", "declined"):
            with self.subTest(response=response):
                self.setUp()
                aid = self.alert()
                self.s.dispatch(self.s.outbox[0]["id"])
                self.run_command(self.sb, "respond", alert_id=aid, expected_version=1, response=response)
                self.s.advance(60)
                self.assertEqual(self.run_command(self.sa, "retry", alert_id=aid, expected_version=2)["error"], "limit_reached")

    def test_recipient_addition_atomic_and_same_expiry(self):
        aid = self.alert()
        expiry = self.s.alerts[aid]["expires"]
        self.assertEqual(self.run_command(self.sa, "add_recipients", alert_id=aid, expected_version=1, recipient_ids=[self.c])["error"], "consent_required")
        self.assertNotIn(self.c, self.s.alerts[aid]["recipients"])
        self.grant(self.c, self.sc)
        self.assertEqual(self.run_command(self.sa, "add_recipients", alert_id=aid, expected_version=1, recipient_ids=[self.c])["status"], "accepted")
        self.assertEqual(self.s.alerts[aid]["expires"], expiry)
        self.assertEqual(len(self.s.view(self.sb, aid)["recipients"]), 1)
        self.assertEqual(len(self.s.view(self.sa, aid)["recipients"]), 2)

    def test_multirecipient_create_rolls_back_if_any_consent_missing(self):
        self.grant()
        result = self.run_command(self.sa, "create_alert", recipient_ids=[self.b, self.c], expires_at=self.s.now + 60)
        self.assertEqual(result["error"], "consent_required")
        self.assertFalse(self.s.alerts)
        self.assertFalse(self.s.outbox)

    def test_personal_history_hide_does_not_delete_other_copy(self):
        aid = self.alert()
        self.run_command(self.sa, "close_alert", alert_id=aid, expected_version=1, state="cancelled")
        self.run_command(self.sb, "hide_history", alert_id=aid)
        self.assert_error("not_found", self.s.view, self.sb, aid)
        self.assertEqual(self.s.view(self.sa, aid)["state"], "cancelled")

    def test_account_deletion_revokes_all_devices_and_pending_work(self):
        aid = self.alert()
        self.assertEqual(self.run_command(self.sb, "delete_account")["status"], "accepted")
        for session in (self.sb, self.sb2):
            self.assert_error("unauthenticated", self.s.sync, session)
        self.assertEqual(self.s.dispatch(self.s.outbox[0]["id"]), "suppressed")
        self.assertEqual(self.s.users[self.b]["email"], "")
        self.assertEqual(self.s.view(self.sa, aid)["recipients"][0]["access"], "unavailable")

    def test_sender_deletion_cancels_alert_and_removes_recipient_access(self):
        aid = self.alert()
        self.run_command(self.sa, "delete_account")
        self.assertEqual(self.s.alerts[aid]["state"], "cancelled")
        self.assertIn(aid, self.s.sync(self.sb)["removed_ids"])

    def test_logout_one_or_all_sessions(self):
        self.s.revoke_session(self.sb)
        self.assert_error("unauthenticated", self.s.sync, self.sb)
        self.assertEqual(self.s.sync(self.sb2)["alerts"], [])
        self.s.revoke_session(self.sb2, all_devices=True)
        self.assert_error("unauthenticated", self.s.sync, self.sb2)

    def test_account_switch_purges_cache_pending_and_rejects_late_old_sync(self):
        aid = self.alert()
        replica = LocalReplica()
        replica.switch_account(self.b)
        snapshot = self.s.sync(self.sb)
        replica.apply_sync(self.b, snapshot)
        self.assertIn(aid, replica.cache)
        replica.record_offline(command(self.s, "delete_account"))
        replica.switch_account(self.c)
        self.assertFalse(replica.cache)
        self.assertIsNone(replica.pending)
        self.assert_error("forbidden", replica.apply_sync, self.b, snapshot)

    def test_out_of_order_snapshot_cannot_reopen_terminal(self):
        aid = self.alert()
        old = self.s.sync(self.sb)
        self.run_command(self.sa, "close_alert", alert_id=aid, expected_version=1, state="resolved")
        replica = LocalReplica()
        replica.switch_account(self.b)
        replica.apply_sync(self.b, self.s.sync(self.sb))
        replica.apply_sync(self.b, old)
        self.assertEqual(replica.cache[aid]["state"], "resolved")

    def test_retention_purges_details_and_old_replay_cannot_resend(self):
        self.grant()
        req = command(self.s, "create_alert", recipient_ids=[self.b], expires_at=self.s.now + 60)
        aid = self.s.execute(self.sa, req)["resource_id"]
        self.s.advance(60 + self.s.RETENTION - 1)
        self.s.purge()
        self.assertIn(aid, self.s.alerts)
        self.s.advance(1)
        self.s.purge()
        self.assertNotIn(aid, self.s.alerts)
        self.assertFalse(self.s.outbox)
        self.s.advance(self.s.OP_RETENTION)
        self.s.purge()
        session = self.s.fixture_session(self.a)
        self.assert_error("expired", self.s.execute, session, req)
        self.assertFalse(self.s.alerts)

    def test_expired_receipt_no_longer_exposes_invitation_secret(self):
        i = self.invite()
        self.s.advance(self.s.INVITE_TTL)
        session = self.s.fixture_session(self.a)
        self.assertIsNone(self.s.receipt(session, i["operation_id"])["invitation_token"])

    def test_errors_and_empty_sync_are_contract_valid(self):
        validate("Sync", self.s.sync(self.sc))
        with self.assertRaises(ValidationError):
            validate("Receipt", {"status": "accepted"})

    def test_deletion_does_not_disclose_unrelated_accounts(self):
        self.alert()
        self.run_command(self.sb, "delete_account")
        self.assertEqual(self.s.relationships(self.sc), {"invitations": [], "grants": []})

    def test_read_enforces_retention_even_before_sweeper(self):
        aid = self.alert()
        self.s.advance(900 + self.s.RETENTION)
        session = self.s.fixture_session(self.a)
        self.assertIn(aid, self.s.alerts)
        self.assert_error("not_found", self.s.view, session, aid)
        self.assertIn(aid, self.s.sync(session)["removed_ids"])

    def test_concurrent_response_order_has_one_winner(self):
        from concurrent.futures import ThreadPoolExecutor
        aid = self.alert()
        requests = [(self.sb, command(self.s, "respond", alert_id=aid, expected_version=1, response="responding")),
                    (self.sb2, command(self.s, "respond", alert_id=aid, expected_version=1, response="declined"))]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda pair: self.s.execute(*pair), requests))
        self.assertEqual(sorted(r["status"] for r in results), ["accepted", "rejected"])
        self.assertEqual([r["error"] for r in results if r["status"] == "rejected"], ["conflict"])
        self.assertEqual(self.s.alerts[aid]["version"], 2)

    def test_relationships_are_scoped_and_block_reason_redacted(self):
        self.grant()
        self.assertEqual(self.s.account(self.sb)["user_id"], self.b)
        self.assertEqual(self.s.relationships(self.sc), {"invitations": [], "grants": []})
        self.run_command(self.sb, "block", user_id=self.a)
        view = self.s.relationships(self.sa)
        self.assertEqual(view["invitations"][0]["state"], "unavailable")
        self.assertNotIn("sara@example.invalid", json.dumps(view))
        self.assertNotIn("digest", json.dumps(view))

    def test_ack_event_cannot_be_reused_for_different_semantics(self):
        aid = self.alert()
        event = str(uuid4())
        self.run_command(self.sb, "acknowledge", alert_id=aid, event_id=event, kind="app_acknowledged")
        result = self.run_command(self.sb, "acknowledge", alert_id=aid, event_id=event, kind="opened")
        self.assertEqual(result["error"], "conflict")
        self.assertFalse(self.s.view(self.sa, aid)["recipients"][0]["opened"])


if __name__ == "__main__":
    unittest.main()
