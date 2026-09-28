"""Deterministic local schema construction; no remote references or generation services."""
import json
from pathlib import Path

ROOT = Path(__file__).parent


def obj(properties, required=None):
    return {"type": "object", "properties": properties,
            "required": list(properties) if required is None else required,
            "additionalProperties": False}


ID = {"type": "string", "format": "uuid"}
TIME = {"type": "integer", "minimum": 0}
VERSION = {"type": "integer", "minimum": 1}
ENUM = lambda *values: {"enum": list(values)}
IDS = {"type": "array", "items": ID, "minItems": 1, "maxItems": 5, "uniqueItems": True}
TOKEN = {"type": "string", "minLength": 32, "maxLength": 128, "pattern": "^[A-Za-z0-9_-]+$"}

COMMANDS = {
    "invite": obj({"recipient_email": {"type": "string", "format": "email", "maxLength": 254}}),
    "decide_invite": obj({"token": TOKEN, "decision": ENUM("accepted", "declined")}),
    "cancel_invite": obj({"invitation_id": ID}),
    "withdraw": obj({"sender_id": ID}),
    "block": obj({"user_id": ID}),
    "unblock": obj({"user_id": ID}),
    "create_alert": obj({"recipient_ids": IDS, "expires_at": TIME}),
    "retry": obj({"alert_id": ID, "expected_version": VERSION}),
    "add_recipients": obj({"alert_id": ID, "expected_version": VERSION, "recipient_ids": IDS}),
    "respond": obj({"alert_id": ID, "expected_version": VERSION, "response": ENUM("responding", "declined")}),
    "acknowledge": obj({"alert_id": ID, "event_id": ID, "kind": ENUM("app_acknowledged", "opened")}),
    "close_alert": obj({"alert_id": ID, "expected_version": VERSION, "state": ENUM("cancelled", "resolved")}),
    "hide_history": obj({"alert_id": ID}),
    "delete_account": obj({}),
}

RECIPIENT = obj({"user_id": ID, "response": ENUM("none", "responding", "declined"),
                 "response_version": {"type": "integer", "minimum": 0},
                 "access": ENUM("active", "unavailable"),
                 "provider_accepted": {"type": "boolean"}, "app_acknowledged": {"type": "boolean"},
                 "opened": {"type": "boolean"}})
ALERT = obj({"alert_id": ID, "sender_id": ID, "state": ENUM("active", "cancelled", "resolved", "expired"),
             "version": VERSION, "expires_at": TIME, "closed_at": {"type": ["integer", "null"], "minimum": 0},
             "recipients": {"type": "array", "items": RECIPIENT, "maxItems": 5}})
ERROR_CODES = ["invalid_request", "unauthenticated", "not_found", "forbidden", "conflict", "expired",
               "rate_limited", "consent_required", "terminal", "limit_reached", "reauthentication_required"]
RECEIPT = obj({"operation_id": ID, "status": ENUM("accepted", "rejected"),
               "resource_id": {"type": ["string", "null"], "format": "uuid"},
               "error": {"enum": [None] + ERROR_CODES}, "server_time": TIME,
               "invitation_token": {"type": ["string", "null"]}})
RECEIPT["allOf"] = [
    {"if": {"properties": {"status": {"const": "accepted"}}}, "then": {"properties": {"error": {"type": "null"}}},
     "else": {"properties": {"error": {"enum": ERROR_CODES}, "resource_id": {"type": "null"}, "invitation_token": {"type": "null"}}}}
]
SCHEMA = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "urn:nidaa:shared-rules:v1",
          "title": "NIDAA shared rules contract (design, no live service)",
          "$defs": {"Command": {"oneOf": [obj({"operation_id": ID, "issued_at": TIME,
                                                "command": {"const": name}, "payload": payload})
                                             for name, payload in COMMANDS.items()]},
                    "Receipt": RECEIPT, "Alert": ALERT,
                    "Error": obj({"error": {"enum": ERROR_CODES}}),
                    "Account": obj({"user_id": ID, "display_name": {"type": "string", "maxLength": 80}, "email_verified": {"const": True}}),
                    "Relationships": obj({"invitations": {"type": "array", "items": obj({"invitation_id": ID, "sender_id": ID,
                        "direction": ENUM("incoming", "outgoing"), "state": ENUM("pending", "accepted", "declined", "expired", "cancelled", "blocked", "withdrawn", "unavailable"), "expires_at": TIME})},
                        "grants": {"type": "array", "items": obj({"sender_id": ID, "recipient_id": ID, "state": ENUM("accepted", "unavailable")})}}),
                    "Sync": obj({"cursor": TIME, "alerts": {"type": "array", "items": ALERT},
                                 "removed_ids": {"type": "array", "items": ID, "uniqueItems": True},
                                 "full_snapshot": {"const": True}})}}

if __name__ == "__main__":
    (ROOT / "contract.schema.json").write_text(json.dumps(SCHEMA, indent=2) + "\n", encoding="utf-8")
