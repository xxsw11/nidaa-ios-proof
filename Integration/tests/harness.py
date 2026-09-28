"""Real local HTTP clients; never prints credentials or response bodies on failure."""
import html
import os
import re
import secrets
import time
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

import httpx
import psycopg
from psycopg.rows import dict_row

BASE = os.environ.get("BASE_URL", "http://gateway:8080").rstrip("/")
AUTH = os.environ.get("AUTH_URL", "http://auth:9999").rstrip("/")
MAIL = os.environ.get("MAIL_URL", "http://mail:8025").rstrip("/")


def check(response, expected, label):
    expected = (expected,) if isinstance(expected, int) else expected
    if response.status_code not in expected:
        # Deliberately omit body, URL query, headers, exception repr and credentials.
        raise AssertionError(f"{label}: expected HTTP {expected}, received {response.status_code}")
    return response


def admin():
    return psycopg.connect(os.environ["DATABASE_ADMIN_URL"], row_factory=dict_row)


def sql(statement, params=()):
    with admin() as connection:
        return connection.execute(statement, params).fetchall()


def mutate(statement, params=()):
    with admin() as connection:
        connection.execute(statement, params)


def envelope(command, **payload):
    return {"operation_id": str(uuid4()), "issued_at": int(time.time()),
            "command": command, "payload": payload}


class LocalAccount:
    def __init__(self, name="Sara"):
        self.email = f"nidaa-{uuid4().hex}@example.invalid"
        self.password = "Nidaa!" + secrets.token_urlsafe(24)
        self.http = httpx.Client(timeout=15, follow_redirects=False, trust_env=False)
        self.name = name
        self.user_id = None

    def signup(self, verify=True):
        response = self.http.post(AUTH + "/signup", json={
            "email": self.email, "password": self.password,
            "data": {"display_name": self.name}})
        check(response, (200, 201), "local signup")
        value = response.json()
        if value.get("access_token"):
            raise AssertionError("signup unexpectedly bypassed email verification")
        if verify:
            self.verify_mail("signup")
            self.login()
        return self

    def wait_mail_link(self, kind, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            response = check(self.http.get(MAIL + "/api/v1/messages"), 200, "local inbox listing")
            for message in response.json().get("messages", []):
                if not any(item.get("Address", "").lower() == self.email for item in message.get("To", [])):
                    continue
                full = check(self.http.get(MAIL + "/api/v1/message/" + message["ID"]), 200, "local inbox message").json()
                body = html.unescape(full.get("HTML", "") + "\n" + full.get("Text", ""))
                for candidate in re.findall(r'https?://[^\s<>"\']+', body):
                    parts = urlsplit(candidate)
                    query = parse_qs(parts.query)
                    if query.get("type", [""])[0] == kind and ("token" in query or "token_hash" in query):
                        return query
            time.sleep(.15)
        raise AssertionError("local verification/recovery message was not received before deadline")

    def verify_mail(self, kind):
        query = self.wait_mail_link(kind)
        # Never follow a URL obtained from email; use only the configured local Auth service.
        params = {key: values[0] for key, values in query.items() if key in ("token", "token_hash", "type")}
        response = check(self.http.get(AUTH + "/verify", params=params), (302, 303), "local email verification")
        fragment = parse_qs(urlsplit(response.headers.get("location", "")).fragment)
        if "error" in fragment or "error_code" in fragment:
            raise AssertionError("local email verification returned a provider error")
        return {key: values[0] for key, values in fragment.items()}

    def login(self):
        response = check(self.http.post(AUTH + "/token?grant_type=password", json={
            "email": self.email, "password": self.password}), 200, "verified password login")
        self.session = response.json()
        return self

    def second_session(self):
        other = LocalAccount(self.name)
        other.email, other.password = self.email, self.password
        other.login()
        other.user_id = self.user_id
        return other

    def refresh(self):
        response = self.http.post(AUTH + "/token?grant_type=refresh_token", json={
            "refresh_token": self.session["refresh_token"]})
        check(response, 200, "session refresh")
        self.session = response.json()
        return self

    def request(self, method, path, **kwargs):
        headers = dict(kwargs.pop("headers", {}))
        headers["Authorization"] = "Bearer " + self.session["access_token"]
        return self.http.request(method, BASE + path, headers=headers, **kwargs)

    def me(self):
        response = check(self.request("GET", "/v1/me"), 200, "account provisioning/read")
        self.user_id = response.json()["user_id"]
        return response.json()

    def submit(self, request):
        return self.request("POST", "/v1/commands", json=request)

    def command(self, name, **payload):
        return check(self.submit(envelope(name, **payload)), 200, "domain command " + name).json()

    def accepted(self, name, **payload):
        receipt = self.command(name, **payload)
        if receipt["status"] != "accepted":
            raise AssertionError("domain command " + name + " was rejected with " + str(receipt.get("error")))
        return receipt

    def alert(self, aid):
        return check(self.request("GET", "/v1/alerts/" + aid), 200, "read alert").json()

    def close(self):
        self.http.close()


def consent(sender, recipient):
    invite = sender.accepted("invite", recipient_email=recipient.email)
    recipient.accepted("decide_invite", token=invite["invitation_token"], decision="accepted")
    return invite
