"""Offline payload preparation only. Never connects to APNs or accepts tokens/keys."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import uuid


def prepare(device_alias, window_end, now=None):
    now = now or datetime.now(timezone.utc)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", device_alias):
        raise ValueError("Use a fictional ASCII device alias, such as TEST-PHONE; no personal name.")
    if window_end.tzinfo is None or now.tzinfo is None:
        raise ValueError("Explicit time zone required.")
    remaining = (window_end - now).total_seconds()
    if remaining <= 30 or remaining > 7200:
        raise ValueError("Window must end more than 30 seconds and at most 2 hours from now.")
    incident = str(uuid.uuid4())
    # Both provider TTL and app-side stale-result checks are bounded by the confirmed window.
    expires = min(int(window_end.timestamp()), int(now.timestamp()) + 60)
    payload = {
        "aps": {
            "alert": {"title": "نداء — اختبار APNs فقط", "body": "اختبار على جهاز مخصص؛ لا طلب مساعدة حقيقي."},
            "sound": "default",
            "interruption-level": "active",
        },
        "proof": "nidaa-ios-proof-v01",
        "incident_id": incident,
        "expires_at": expires,
    }
    metadata = {
        "preparationOnly": True,
        "deviceAlias": device_alias,
        "confirmation": "Operator must separately verify explicit device/window authorization before sending.",
        "preparedAt": now.isoformat(),
        "windowEndsAt": window_end.isoformat(),
        "endpoint": "api.sandbox.push.apple.com",
        "headers": {"apns-push-type": "alert", "apns-priority": "10", "apns-expiration": str(expires), "apns-id": incident},
        "topic": "Set your authorized Bundle ID in Apple's console; none invented here.",
        "deviceToken": "Not collected by this offline utility.",
        "providerAcceptance": "Not tested",
        "deviceAcknowledgment": "Not tested",
        "humanResponse": "Not tested",
    }
    return payload, metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-alias", required=True)
    parser.add_argument("--window-end", required=True, help="ISO-8601 with timezone from the user's confirmed window")
    parser.add_argument("--output-dir", type=Path, default=Path("PrivateEvidence"))
    args = parser.parse_args()
    try:
        end = datetime.fromisoformat(args.window_end.replace("Z", "+00:00"))
        payload, metadata = prepare(args.device_alias, end)
    except ValueError as error:
        parser.error(str(error))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    stem = payload["incident_id"]
    for suffix, data in [("payload", payload), ("preparation", metadata)]:
        destination = args.output_dir / f"{stem}-{suffix}.json"
        with destination.open("x", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
    print(f"Prepared {stem}. No network request made. Verify device and window before any send.")


if __name__ == "__main__":
    main()
