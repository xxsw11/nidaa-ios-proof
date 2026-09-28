import importlib.util
from pathlib import Path
from datetime import datetime, timedelta, timezone
import json
import unittest
import uuid

spec = importlib.util.spec_from_file_location("prepare_apns", Path(__file__).resolve().parents[1] / "Scripts/prepare_apns.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class OfflinePayloadTests(unittest.TestCase):
    now = datetime(2030, 1, 1, tzinfo=timezone.utc)

    def make(self, seconds=120):
        return module.prepare("TEST-PHONE", self.now + timedelta(seconds=seconds), self.now)

    def test_ordinary_alert_without_critical_or_background_fields(self):
        payload, _ = self.make()
        self.assertEqual(payload["aps"]["sound"], "default")
        self.assertEqual(payload["aps"]["interruption-level"], "active")
        self.assertNotIn("content-available", payload["aps"])
        self.assertNotIn("mutable-content", payload["aps"])
        self.assertNotIn("critical", json.dumps(payload))

    def test_expiration_bounded_by_window_and_one_minute(self):
        for seconds in [31, 45, 60, 120, 7200]:
            payload, metadata = self.make(seconds)
            self.assertLessEqual(payload["expires_at"], int(self.now.timestamp()) + min(seconds, 60))
            self.assertEqual(str(payload["expires_at"]), metadata["headers"]["apns-expiration"])

    def test_bad_windows_rejected(self):
        for seconds in [-10, 0, 30, 7201]:
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                self.make(seconds)

    def test_naive_time_rejected(self):
        with self.assertRaises(ValueError):
            module.prepare("TEST-PHONE", datetime(2030, 1, 1), self.now)

    def test_aliases_no_personal_name_or_unbounded_input(self):
        for alias in ["", "Sara's iPhone", "A" * 41, "../../device"]:
            with self.subTest(alias=alias), self.assertRaises(ValueError):
                module.prepare(alias, self.now + timedelta(seconds=60), self.now)

    def test_unique_correlated_ids_and_utf8_size(self):
        first, metadata = self.make()
        second, _ = self.make()
        uuid.UUID(first["incident_id"])
        self.assertNotEqual(first["incident_id"], second["incident_id"])
        self.assertEqual(first["incident_id"], metadata["headers"]["apns-id"])
        self.assertLess(len(json.dumps(first, ensure_ascii=False).encode()), 4096)

    def test_no_delivery_claim_or_token_collected(self):
        _, metadata = self.make()
        self.assertTrue(metadata["preparationOnly"])
        for key in ["providerAcceptance", "deviceAcknowledgment", "humanResponse"]:
            self.assertEqual(metadata[key], "Not tested")

    def test_only_sandbox_alert_headers(self):
        _, metadata = self.make()
        self.assertEqual(metadata["endpoint"], "api.sandbox.push.apple.com")
        self.assertEqual(metadata["headers"]["apns-push-type"], "alert")
        self.assertEqual(metadata["headers"]["apns-priority"], "10")


if __name__ == "__main__":
    unittest.main(verbosity=2)
