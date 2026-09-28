"""Actual local GoTrue + Mailpit + HTTP + PostgreSQL smoke journey."""
import time
import unittest
from uuid import uuid4

from harness import LocalAccount, check, consent


class RealIntegrationSmoke(unittest.TestCase):
    def test_verified_two_account_flow_and_unauthorized_third(self):
        clients = [LocalAccount(name).signup() for name in ("Sami", "Sara", "Noor")]
        self.addCleanup(lambda: [client.close() for client in clients])
        a, b, c = clients
        for client in clients:
            self.assertTrue(client.me()["email_verified"])
        invite = a.accepted("invite", recipient_email=b.email)
        denied = a.command("create_alert", recipient_ids=[b.user_id], expires_at=int(time.time()) + 600)
        self.assertEqual(denied["error"], "consent_required")
        wrong = c.command("decide_invite", token=invite["invitation_token"], decision="accepted")
        self.assertEqual(wrong["error"], "not_found")
        b.accepted("decide_invite", token=invite["invitation_token"], decision="accepted")
        aid = a.accepted("create_alert", recipient_ids=[b.user_id], expires_at=int(time.time()) + 600)["resource_id"]
        check(c.request("GET", "/v1/alerts/" + aid), 404, "third account alert access")
        self.assertEqual(b.command("create_alert", recipient_ids=[a.user_id], expires_at=int(time.time()) + 600)["error"], "consent_required")
        b.accepted("acknowledge", alert_id=aid, event_id=str(uuid4()), kind="app_acknowledged")
        b.accepted("acknowledge", alert_id=aid, event_id=str(uuid4()), kind="opened")
        b.accepted("respond", alert_id=aid, expected_version=b.alert(aid)["version"], response="responding")
        view = a.alert(aid)
        self.assertEqual(view["state"], "active")
        self.assertEqual(view["recipients"][0]["response"], "responding")
        self.assertTrue(view["recipients"][0]["opened"])
        self.assertTrue(view["recipients"][0]["app_acknowledged"])
        self.assertFalse(view["recipients"][0]["provider_accepted"])


if __name__ == "__main__":
    unittest.main()
