"""In-memory RULE SIMULATION. No HTTP, production authentication, email, database or push.

Fixture sessions represent an already verified provider identity. The serialized lock
models transaction ordering; it does NOT prove a database implementation is atomic.
"""
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path
import secrets
from threading import RLock
from uuid import uuid4

from jsonschema import Draft202012Validator, FormatChecker

SCHEMA = json.loads((Path(__file__).parent / "contract.schema.json").read_text(encoding="utf-8"))


def validate(kind, value):
    Draft202012Validator(SCHEMA["$defs"][kind], format_checker=FormatChecker()).validate(value)


class RuleError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def require(condition, code):
    if not condition:
        raise RuleError(code)


class Server:
    INVITE_TTL = 86400
    RETENTION = 30 * 86400
    OP_RETENTION = 90 * 86400

    def __init__(self):
        self.now = 1_800_000_000
        self.users, self.sessions, self.invites, self.grants = {}, {}, {}, {}
        self.blocks, self.alerts, self.operations, self.outbox = set(), {}, {}, []
        self.hidden, self.removed, self.attempts = set(), {}, {}
        self.sequence = 0
        self.lock = RLock()

    def fixture_account(self, email, name="Sara"):
        """Test-only provisioned VERIFIED email; not an authentication endpoint."""
        uid = str(uuid4())
        self.users[uid] = {"email": email.strip().lower(), "name": name, "active": True}
        return uid

    def fixture_session(self, uid, device=None, verified=True):
        token = str(uuid4())
        self.sessions[token] = {"uid": uid, "device": device or str(uuid4()), "verified": verified,
                                "revoked": False, "auth_at": self.now, "expires": self.now + 3600}
        return token

    def principal(self, session):
        s = self.sessions.get(session)
        require(s and not s["revoked"] and s["verified"] and self.now < s["expires"]
                and self.users[s["uid"]]["active"], "unauthenticated")
        return s

    def revoke_session(self, session, all_devices=False):
        with self.lock:
            s = self.principal(session)
            for key, candidate in self.sessions.items():
                if key == session or (all_devices and candidate["uid"] == s["uid"]):
                    candidate["revoked"] = True

    def advance(self, seconds):
        require(seconds >= 0, "invalid_request")
        with self.lock:
            self.now += seconds
            self.expire()

    def expire(self):
        for invitation in self.invites.values():
            if invitation["state"] == "pending" and self.now >= invitation["expires"]:
                invitation["state"] = "expired"
        for alert in self.alerts.values():
            if alert["state"] == "active" and self.now >= alert["expires"]:
                self.finish(alert, "expired", alert["expires"])
        self.erase_unusable_invitation_tokens()

    def erase_unusable_invitation_tokens(self):
        for operation in self.operations.values():
            receipt = operation["receipt"]
            if receipt["invitation_token"] is not None:
                invitation = self.invites.get(receipt["resource_id"])
                if not invitation or invitation["state"] != "pending":
                    receipt["invitation_token"] = None

    def finish(self, alert, state, when=None):
        alert["state"], alert["closed"] = state, self.now if when is None else when
        alert["version"] += 1
        self.sequence += 1
        for job in self.outbox:
            if job["alert"] == alert["id"] and job["state"] == "queued":
                job["state"] = "suppressed"

    def blocked(self, a, b):
        return (a, b) in self.blocks or (b, a) in self.blocks

    def consent(self, sender, recipient):
        return (sender != recipient and self.users.get(sender, {}).get("active", False)
                and self.users.get(recipient, {}).get("active", False)
                and self.grants.get((sender, recipient)) == "accepted" and not self.blocked(sender, recipient))

    def throttle(self, uid, command):
        # Production additionally needs IP/device/network abuse controls; not modeled.
        if command not in ("invite", "decide_invite", "create_alert"):
            return
        window, limit = (86400, 10) if command == "invite" else (60, 5)
        key = (uid, command)
        recent = [t for t in self.attempts.get(key, []) if self.now - t < window]
        require(len(recent) < limit, "rate_limited")
        self.attempts[key] = recent + [self.now]

    def execute(self, session, request):
        """Command boundary. Rejections are receipts; transport/auth/schema errors are exceptions."""
        from jsonschema.exceptions import ValidationError
        try:
            validate("Command", request)
        except ValidationError:
            raise RuleError("invalid_request") from None
        with self.lock:
            s = self.principal(session)
            uid, op = s["uid"], request["operation_id"]
            self.expire()
            fingerprint = sha256(json.dumps(request, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            key = (uid, op)
            if key in self.operations:
                require(self.operations[key]["fingerprint"] == fingerprint, "conflict")
                return self.receipt(session, op)
            require(0 <= self.now - request["issued_at"] <= 60, "expired")
            self.throttle(uid, request["command"])
            # Atomic rollback for multi-recipient and account changes on rejected commands.
            fields = ("users", "sessions", "invites", "grants", "blocks", "alerts", "outbox", "hidden", "removed", "sequence")
            before = {name: deepcopy(getattr(self, name)) for name in fields}
            result = {"operation_id": op, "status": "accepted", "resource_id": None,
                      "error": None, "server_time": self.now, "invitation_token": None}
            try:
                resource, token = self.apply(s, request["command"], request["payload"])
                result.update(resource_id=resource, invitation_token=token)
                self.sequence += 1
            except RuleError as error:
                for name, value in before.items():
                    setattr(self, name, value)
                result.update(status="rejected", error=error.code)
            self.operations[key] = {"fingerprint": fingerprint, "receipt": deepcopy(result), "created": self.now}
            self.erase_unusable_invitation_tokens()
            validate("Receipt", result)
            return result

    def receipt(self, session, op):
        with self.lock:
            uid = self.principal(session)["uid"]
            value = self.operations.get((uid, op))
            require(value is not None, "not_found")
            result = deepcopy(value["receipt"])
            # Never return an expired invitation secret from a long-lived operation receipt.
            if self.now - value["created"] >= self.INVITE_TTL:
                result["invitation_token"] = None
            validate("Receipt", result)
            return result

    def invitation_for(self, token):
        digest = sha256(token.encode()).hexdigest()
        return next((i for i in self.invites.values() if i["digest"] == digest), None)

    def alert_for(self, uid, aid, sender=False, active=False, version=None):
        a = self.alerts.get(aid)
        require(a and (a["sender"] == uid or uid in a["recipients"]), "not_found")
        if sender:
            require(a["sender"] == uid, "forbidden")
        if active:
            require(a["state"] == "active", "terminal")
        if version is not None:
            require(a["version"] == version, "conflict")
        return a

    def restrict_pair(self, sender, recipient, state):
        known = ((sender, recipient) in self.grants or
                 any(i["sender"] == sender and i["email"] == self.users[recipient]["email"] for i in self.invites.values()) or
                 any(a["sender"] == sender and recipient in a["recipients"] for a in self.alerts.values()))
        if not known:
            return
        self.grants[(sender, recipient)] = state
        for invitation in self.invites.values():
            if invitation["sender"] == sender and invitation["email"] == self.users[recipient]["email"]:
                if invitation["state"] in ("pending", "accepted"):
                    invitation["state"] = state
        for a in self.alerts.values():
            if a["sender"] == sender and recipient in a["recipients"]:
                a["recipients"][recipient]["access"] = state
                a["version"] += 1
                for job in self.outbox:
                    if job["alert"] == a["id"] and job["recipient"] == recipient and job["state"] == "queued":
                        job["state"] = "suppressed"

    def queue(self, a, recipient):
        r = a["recipients"][recipient]
        require(r["response"] == "none" and r["attempts"] < 2, "limit_reached")
        require(self.consent(a["sender"], recipient) and r["access"] == "active", "consent_required")
        require(not any(j["alert"] == a["id"] and j["recipient"] == recipient and j["state"] == "queued"
                        for j in self.outbox), "conflict")
        r["attempts"] += 1
        self.outbox.append({"id": str(uuid4()), "alert": a["id"], "recipient": recipient,
                            "state": "queued", "created": self.now})

    def add(self, a, recipients):
        require(len(set(a["recipients"]) | set(recipients)) <= 5, "limit_reached")
        require(all(r not in a["recipients"] for r in recipients), "conflict")
        require(all(self.consent(a["sender"], r) for r in recipients), "consent_required")
        for recipient in recipients:
            a["recipients"][recipient] = {"response": "none", "response_version": 0, "access": "active",
                                           "attempts": 0, "provider": False, "acks": {}, "events": {}}
            self.queue(a, recipient)

    def apply(self, session, command, p):
        uid = session["uid"]
        if command in ("decide_invite", "delete_account"):
            require(self.now - session["auth_at"] <= 300, "reauthentication_required")
        if command == "invite":
            email = p["recipient_email"].strip().lower()
            require(email != self.users[uid]["email"], "forbidden")
            # Generic issuance outcome does not reveal whether this email has an account.
            iid, token = str(uuid4()), secrets.token_urlsafe(32)
            self.invites[iid] = {"id": iid, "sender": uid, "email": email, "digest": sha256(token.encode()).hexdigest(),
                                  "state": "pending", "expires": self.now + self.INVITE_TTL}
            return iid, token
        if command == "decide_invite":
            i = self.invitation_for(p["token"])
            require(i and i["email"] == self.users[uid]["email"] and i["sender"] != uid, "not_found")
            require(i["state"] != "expired", "expired")
            require(i["state"] == "pending", "conflict")
            require(not self.blocked(uid, i["sender"]) and self.users[i["sender"]]["active"], "forbidden")
            i["state"] = p["decision"]
            if p["decision"] == "accepted":
                self.grants[(i["sender"], uid)] = "accepted"
            return i["id"], None
        if command == "cancel_invite":
            i = self.invites.get(p["invitation_id"])
            require(i and i["sender"] == uid, "not_found")
            require(i["state"] == "pending", "conflict")
            i["state"] = "cancelled"
            return i["id"], None
        if command == "withdraw":
            sender = p["sender_id"]
            require(self.grants.get((sender, uid)) == "accepted", "not_found")
            self.restrict_pair(sender, uid, "withdrawn")
            return None, None
        if command in ("block", "unblock"):
            target = p["user_id"]
            # Block requires a known relationship/invitation participant; no public ID search.
            known = ((uid, target) in self.grants or (target, uid) in self.grants or
                     any(i["sender"] == target and i["email"] == self.users[uid]["email"] for i in self.invites.values()))
            require(target != uid and target in self.users and known, "not_found")
            if command == "block":
                self.blocks.add((uid, target))
                self.restrict_pair(uid, target, "blocked")
                self.restrict_pair(target, uid, "blocked")
            else:
                self.blocks.discard((uid, target))
                # Unblocking deliberately does not restore grants or historical access.
            return None, None
        if command == "create_alert":
            require(0 < p["expires_at"] - self.now <= 900, "expired")
            aid = str(uuid4())
            a = {"id": aid, "sender": uid, "state": "active", "version": 1,
                 "expires": p["expires_at"], "closed": None, "recipients": {}}
            self.alerts[aid] = a
            self.add(a, p["recipient_ids"])
            return aid, None
        if command == "delete_account":
            for other in list(self.users):
                if other != uid:
                    self.restrict_pair(uid, other, "deleted")
                    self.restrict_pair(other, uid, "deleted")
            for a in self.alerts.values():
                if a["sender"] == uid and a["state"] == "active":
                    self.finish(a, "cancelled")
            for i in self.invites.values():
                if i["sender"] == uid or i["email"] == self.users[uid]["email"]:
                    i["email"], i["digest"], i["state"] = "", "", "cancelled"
            for s in self.sessions.values():
                if s["uid"] == uid:
                    s["revoked"] = True
            self.users[uid] = {"email": "", "name": "Deleted account", "active": False}
            # Retain only non-secret idempotency tombstones for deletion safety.
            for (owner, _), operation in self.operations.items():
                if owner == uid:
                    operation["receipt"]["invitation_token"] = None
            return uid, None
        a = self.alert_for(uid, p["alert_id"])
        if command == "hide_history":
            require(a["state"] != "active", "conflict")
            self.hidden.add((uid, a["id"]))
            return a["id"], None
        if command in ("retry", "add_recipients", "close_alert"):
            self.alert_for(uid, a["id"], sender=True, active=True, version=p["expected_version"])
            if command == "close_alert":
                self.finish(a, p["state"])
            elif command == "add_recipients":
                self.add(a, p["recipient_ids"])
                a["version"] += 1
            else:
                candidates = [r for r, v in a["recipients"].items() if v["response"] == "none"
                              and v["access"] == "active" and self.consent(uid, r) and v["attempts"] < 2
                              and not any(j["alert"] == a["id"] and j["recipient"] == r and j["state"] == "queued" for j in self.outbox)]
                require(candidates, "limit_reached")
                require(all(self.now - max(j["created"] for j in self.outbox if j["alert"] == a["id"]
                                          and j["recipient"] == r) >= 60 for r in candidates), "rate_limited")
                for r in candidates:
                    self.queue(a, r)
                a["version"] += 1
            return a["id"], None
        require(uid in a["recipients"], "forbidden")
        r = a["recipients"][uid]
        require(r["access"] == "active" and self.consent(a["sender"], uid), "consent_required")
        require(a["state"] == "active", "terminal")
        if command == "respond":
            require(a["version"] == p["expected_version"] and r["response"] == "none", "conflict")
            r["response"], r["response_version"] = p["response"], a["version"] + 1
            a["version"] += 1
            for job in self.outbox:
                if job["alert"] == a["id"] and job["recipient"] == uid and job["state"] == "queued":
                    job["state"] = "suppressed"
        elif command == "acknowledge":
            event = (session["device"], p["event_id"])
            require(event not in r["events"] or r["events"][event] == p["kind"], "conflict")
            if event not in r["events"]:
                r["events"][event] = p["kind"]
                r["acks"].setdefault(session["device"], set()).add(p["kind"])
        else:
            raise RuleError("invalid_request")
        return a["id"], None

    def dispatch(self, job_id):
        """SIMULATED provider handoff, never sends anything. Recheck at linearization point."""
        with self.lock:
            self.expire()
            job = next(j for j in self.outbox if j["id"] == job_id)
            if job["state"] != "queued":
                return job["state"]
            a = self.alerts.get(job["alert"])
            r = a["recipients"][job["recipient"]] if a else None
            if not a or a["state"] != "active" or not self.consent(a["sender"], job["recipient"]) or r["access"] != "active" or r["response"] != "none":
                job["state"] = "suppressed"
            else:
                job["state"], r["provider"] = "provider_accepted", True
                self.sequence += 1
            return job["state"]

    def view(self, session, aid):
        with self.lock:
            uid = self.principal(session)["uid"]
            self.expire()
            a = self.alert_for(uid, aid)
            require(a["closed"] is None or self.now - a["closed"] < self.RETENTION, "not_found")
            require((uid, aid) not in self.hidden, "not_found")
            if uid != a["sender"]:
                require(a["recipients"][uid]["access"] == "active", "not_found")
            recipients = []
            for user, r in a["recipients"].items():
                if uid != a["sender"] and uid != user:
                    continue
                kinds = set().union(*r["acks"].values()) if r["acks"] else set()
                recipients.append({"user_id": user, "response": r["response"], "response_version": r["response_version"],
                                   "access": "active" if r["access"] == "active" else "unavailable", "provider_accepted": r["provider"],
                                   "app_acknowledged": bool(kinds), "opened": "opened" in kinds})
            value = {"alert_id": aid, "sender_id": a["sender"], "state": a["state"], "version": a["version"],
                     "expires_at": a["expires"], "closed_at": a["closed"], "recipients": recipients}
            validate("Alert", value)
            return value

    def account(self, session):
        with self.lock:
            uid = self.principal(session)["uid"]
            value = {"user_id": uid, "display_name": self.users[uid]["name"], "email_verified": True}
            validate("Account", value)
            return value

    def relationships(self, session):
        with self.lock:
            uid = self.principal(session)["uid"]
            self.expire()
            invites = []
            for i in self.invites.values():
                outgoing = i["sender"] == uid
                if outgoing or i["email"] == self.users[uid]["email"]:
                    state = i["state"]
                    if state == "deleted" or (outgoing and state in ("blocked", "withdrawn")):
                        state = "unavailable"
                    invites.append({"invitation_id": i["id"], "sender_id": i["sender"], "direction": "outgoing" if outgoing else "incoming",
                                    "state": state, "expires_at": i["expires"]})
            grants = [{"sender_id": a, "recipient_id": b, "state": "accepted" if state == "accepted" else "unavailable"}
                      for (a, b), state in self.grants.items() if uid in (a, b)]
            result = {"invitations": invites, "grants": grants}
            validate("Relationships", result)
            return result

    def sync(self, session):
        with self.lock:
            uid = self.principal(session)["uid"]
            self.expire()
            alerts, removed = [], list(self.removed.get(uid, set()))
            for aid, a in self.alerts.items():
                if a["sender"] == uid or uid in a["recipients"]:
                    try:
                        alerts.append(self.view(session, aid))
                    except RuleError as error:
                        if error.code != "not_found":
                            raise
                        removed.append(aid)
            result = {"cursor": self.sequence, "alerts": alerts, "removed_ids": sorted(set(removed)), "full_snapshot": True}
            validate("Sync", result)
            return result

    def purge(self):
        with self.lock:
            self.expire()
            for aid, a in list(self.alerts.items()):
                if a["closed"] is not None and self.now - a["closed"] >= self.RETENTION:
                    for uid in {a["sender"], *a["recipients"]}:
                        self.removed.setdefault(uid, set()).add(aid)
                    del self.alerts[aid]
                    self.outbox = [j for j in self.outbox if j["alert"] != aid]
                    self.hidden = {(u, i) for u, i in self.hidden if i != aid}
                    self.sequence += 1
            for key, operation in list(self.operations.items()):
                age = self.now - operation["created"]
                if age >= self.INVITE_TTL:
                    operation["receipt"]["invitation_token"] = None
                if age >= self.OP_RETENTION:
                    del self.operations[key]
            self.invites = {k: i for k, i in self.invites.items() if self.now < i["expires"] + self.RETENTION}


class LocalReplica:
    """Account-bound cache and explicit offline uncertainty; no background send mechanism."""
    def __init__(self):
        self.owner, self.cache, self.pending = None, {}, None
        self.cursor = -1
        self.generation = 0

    def switch_account(self, uid):
        self.owner, self.cache, self.pending, self.cursor = uid, {}, None, -1
        self.generation += 1

    def record_offline(self, request):
        self.pending = {"request": deepcopy(request), "state": "never_left"}

    def mark_attempted(self):
        require(self.pending is not None, "not_found")
        self.pending["state"] = "outcome_unknown"

    def reconnect(self):
        return "query_same_operation" if self.pending and self.pending["state"] == "outcome_unknown" else "renew_confirmation_and_local_auth"

    def apply_sync(self, owner, snapshot, generation):
        validate("Sync", snapshot)
        require(owner == self.owner, "forbidden")
        require(generation == self.generation, "conflict")
        if snapshot["cursor"] <= self.cursor:
            return
        self.cache = {a["alert_id"]: deepcopy(a) for a in snapshot["alerts"]}
        self.cursor = snapshot["cursor"]


def command(server, name, **payload):
    return {"operation_id": str(uuid4()), "issued_at": server.now, "command": name, "payload": payload}
