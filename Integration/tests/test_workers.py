"""Actual independent worker processes/connections and isolated database restore drill."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from uuid import uuid4

import psycopg
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row

from harness import LocalAccount, admin, check, consent, envelope, mutate, sql
from test_integration import IntegrationCase


def worker(*arguments, expected=0, environment=None):
    result = subprocess.run([sys.executable, "-m", "Integration.service.worker", *arguments],
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if result.returncode != expected:
        raise AssertionError("maintenance worker exit code differs from expected; output redacted")
    return result


class WorkerIntegration(IntegrationCase):
    def test_worker_crash_before_commit_rollback_and_restart(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        worker("dispatch", "--job", job, "--crash-before-commit", expected=71)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 0)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "queued")
        worker("dispatch", "--job", job)
        worker("dispatch", "--job", job)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 1)
        self.assertTrue(self.a.alert(aid)["recipients"][0]["provider_accepted"])
        self.assertFalse(self.a.alert(aid)["recipients"][0]["app_acknowledged"])

    def test_worker_crash_after_commit_restart_does_not_duplicate(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        worker("dispatch", "--job", job, "--crash-after-commit", expected=72)
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "provider_accepted")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 1)

    def test_two_workers_duplicate_claims_have_one_fake_handoff(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        with ThreadPoolExecutor(2) as pool:
            list(pool.map(lambda _: worker("dispatch", "--job", job), range(2)))
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 1)

    def test_block_before_worker_suppresses(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        self.b.accepted("block", user_id=self.a.user_id)
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 0)

    def test_block_after_handoff_does_not_claim_retraction(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        worker("dispatch", "--job", job)
        self.b.accepted("block", user_id=self.a.user_id)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "provider_accepted")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 1)
        check(self.b.request("GET", "/v1/alerts/"+aid), 404, "blocked recipient after prior fake handoff")

    def test_disabled_domain_account_suppresses_queued_work(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        mutate("UPDATE nidaa.accounts SET active=false WHERE user_id=%s", (self.b.user_id,))
        check(self.b.request("GET", "/v1/me"), 401, "domain disabled account")
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")

    def test_provider_ban_suppresses_already_queued_work(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        subject = sql("SELECT subject FROM nidaa.accounts WHERE user_id=%s", (self.b.user_id,))[0]["subject"]
        mutate("UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=%s", (subject,))
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 0)

    def test_provider_email_mismatch_suppresses_before_domain_session_refresh(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        subject = sql("SELECT subject FROM nidaa.accounts WHERE user_id=%s", (self.b.user_id,))[0]["subject"]
        # Explicit admin fixture for an out-of-band provider identity change; not an
        # email-change user journey (that feature is disabled at the trial gateway).
        mutate("UPDATE auth.users SET email=%s WHERE id=%s", (f"nidaa-{uuid4().hex}@example.invalid",subject))
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 0)
        self.b.me()
        check(self.b.request("GET", "/v1/alerts/"+aid), 404, "old grant after provider identity transition")

    def test_worker_block_race_serializes_without_late_authorization(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        with ThreadPoolExecutor(2) as pool:
            dispatch = pool.submit(worker, "dispatch", "--job", job)
            block = pool.submit(self.b.accepted, "block", user_id=self.a.user_id)
            dispatch.result()
            block.result()
        state = self.row("outbox", aid)[0]["state"]
        self.assertIn(state, ("suppressed", "provider_accepted"))
        count = sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"]
        self.assertEqual(count, int(state == "provider_accepted"))
        worker("dispatch", "--job", job)
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], count)
        check(self.b.request("GET", "/v1/alerts/"+aid), 404, "blocked after worker race")

    def test_worker_delete_race_and_provider_cleanup(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        with ThreadPoolExecutor(2) as pool:
            dispatch = pool.submit(worker, "dispatch", "--job", job)
            deletion = pool.submit(self.b.accepted, "delete_account")
            dispatch.result()
            deletion.result()
        self.assertIn(self.row("outbox", aid)[0]["state"], ("suppressed", "provider_accepted"))
        worker("cleanup-auth")
        subject = sql("SELECT subject FROM nidaa.accounts WHERE user_id=%s", (self.b.user_id,))[0]["subject"]
        self.assertEqual(sql("SELECT count(*) AS n FROM auth.users WHERE id=%s", (subject,))[0]["n"], 0)
        self.assertTrue(sql("SELECT provider_completed FROM nidaa.deletion_ledger WHERE user_id=%s", (self.b.user_id,))[0]["provider_completed"])

    def test_retry_excludes_response_and_decline_preserves_deadline_and_limit(self):
        consent(self.a, self.b)
        consent(self.a, self.c)
        deadline = int(time.time())+600
        aid = self.a.accepted("create_alert", recipient_ids=[self.b.user_id,self.c.user_id], expires_at=deadline)["resource_id"]
        for job in self.row("outbox", aid):
            worker("dispatch", "--job", str(job["job_id"]))
        self.b.accepted("respond", alert_id=aid, expected_version=1, response="responding")
        self.assertEqual(self.a.command("retry", alert_id=aid, expected_version=2)["error"], "rate_limited")
        mutate("UPDATE nidaa.outbox SET created_at=%s WHERE alert_id=%s", (int(time.time())-61, aid))
        self.a.accepted("retry", alert_id=aid, expected_version=2)
        jobs = self.row("outbox", aid)
        second = [job for job in jobs if job["ordinal"] == 2]
        self.assertEqual(len(second), 1)
        self.assertEqual(str(second[0]["recipient_id"]), self.c.user_id)
        self.assertEqual(second[0]["deadline"], deadline)
        self.assertEqual(self.a.alert(aid)["expires_at"], deadline)
        self.c.accepted("respond", alert_id=aid, expected_version=3, response="declined")
        self.assertEqual(self.a.command("retry", alert_id=aid, expected_version=4)["error"], "limit_reached")
        worker("dispatch", "--job", str(second[0]["job_id"]))
        self.assertEqual(sql("SELECT state FROM nidaa.outbox WHERE job_id=%s", (second[0]["job_id"],))[0]["state"], "suppressed")

    def test_worker_deadline_recheck_and_original_expiry(self):
        aid = self.create()
        job = str(self.row("outbox", aid)[0]["job_id"])
        mutate("UPDATE nidaa.alerts SET created_at=%s,expires_at=%s WHERE alert_id=%s", (int(time.time())-100,int(time.time())-1,aid))
        worker("dispatch", "--job", job)
        self.assertEqual(self.row("outbox", aid)[0]["state"], "suppressed")
        self.assertEqual(sql("SELECT count(*) AS n FROM nidaa.fake_handoffs WHERE job_id=%s", (job,))[0]["n"], 0)

    def test_retention_purge_and_expired_idempotency_do_not_resend(self):
        aid = self.create()
        self.a.accepted("close_alert", alert_id=aid, expected_version=1, state="cancelled")
        mutate("UPDATE nidaa.alerts SET closed_at=%s WHERE alert_id=%s", (int(time.time())-31*86400,aid))
        check(self.a.request("GET", "/v1/alerts/"+aid), 404, "read-time retention enforcement")
        worker("purge")
        self.assertEqual(len(self.row("alerts", aid)), 0)
        self.assertEqual(len(self.row("outbox", aid)), 0)
        snapshot = self.get(self.a, "/v1/sync")
        self.assertIn(aid, snapshot["removed_ids"])
        stale = envelope("create_alert", recipient_ids=[self.b.user_id], expires_at=int(time.time())+600)
        stale["issued_at"] -= 91*86400
        check(self.a.submit(stale), 410, "aged-out operation cannot be dispatched")

    def test_read_time_retention_publishes_one_new_cursor_before_sweeper(self):
        aid = self.create()
        self.a.accepted("close_alert", alert_id=aid, expected_version=1, state="cancelled")
        before = self.get(self.b, "/v1/sync")
        self.assertIn(aid, {alert["alert_id"] for alert in before["alerts"]})
        mutate("UPDATE nidaa.alerts SET closed_at=%s WHERE alert_id=%s", (int(time.time())-31*86400, aid))
        after = self.get(self.b, "/v1/sync")
        self.assertGreater(after["cursor"], before["cursor"])
        self.assertNotIn(aid, {alert["alert_id"] for alert in after["alerts"]})
        self.assertIn(aid, after["removed_ids"])
        repeat = self.get(self.b, "/v1/sync")
        self.assertEqual(repeat["cursor"], after["cursor"])

    def test_backup_restore_replays_later_deletion_and_revocations_before_access(self):
        aid = self.create()
        d = LocalAccount("Lina")
        self.clients.append(d)
        d.signup()
        d.me()
        consent(self.a, self.c)
        consent(self.a, d)
        self.a.accepted("add_recipients", alert_id=aid, expected_version=1, recipient_ids=[self.c.user_id,d.user_id])
        restore_name = "nidaa_restore_" + uuid4().hex
        source = conninfo_to_dict(os.environ["DATABASE_ADMIN_URL"])
        restored_service = conninfo_to_dict(os.environ["DATABASE_URL"])
        restored_service["dbname"] = restore_name
        # Backup contents/ledger remain temporary, excluded from test artifacts.
        with tempfile.TemporaryDirectory(prefix="nidaa-restore-") as directory:
            backup = str(Path(directory)/"before-deletion.dump")
            ledger = str(Path(directory)/"after-deletion-ledger.json")
            database_env = os.environ.copy()
            database_env["PGPASSWORD"] = source.pop("password", "")
            public_conninfo = make_conninfo(**source)
            dump = subprocess.run(["pg_dump", "--no-owner", "--format=custom", "--file", backup, "--dbname", public_conninfo],
                                  env=database_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            self.assertEqual(dump.returncode, 0, "isolated backup failed; diagnostic output redacted")
            self.b.accepted("delete_account")
            self.c.accepted("withdraw", sender_id=self.a.user_id)
            d.accepted("block", user_id=self.a.user_id)
            worker("export-ledger", "--file", ledger)
            with psycopg.connect(os.environ["DATABASE_ADMIN_URL"], autocommit=True) as connection:
                connection.execute(psycopg.sql.SQL("CREATE DATABASE {}").format(psycopg.sql.Identifier(restore_name)))
            try:
                target = dict(source, dbname=restore_name)
                restore = subprocess.run(["pg_restore", "--no-owner", "--dbname", make_conninfo(**target), backup],
                                         env=database_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
                self.assertEqual(restore.returncode, 0, "isolated restore failed; diagnostic output redacted")
                restore_env = os.environ.copy()
                restore_env["DATABASE_URL"] = make_conninfo(**restored_service)
                # No HTTP service points at this database. Apply newer ledger before reads.
                worker("replay-ledger", "--file", ledger, environment=restore_env)
                worker("replay-ledger", "--file", ledger, environment=restore_env)
                with psycopg.connect(make_conninfo(**restored_service), row_factory=dict_row) as connection:
                    from Integration.service.domain import Domain, RuleError
                    domain = Domain(connection)
                    with self.assertRaises(RuleError) as failure:
                        domain.principal(self.b.session["access_token"])
                    self.assertEqual(failure.exception.code, "unauthenticated")
                    account = connection.execute("SELECT active,email FROM nidaa.accounts WHERE user_id=%s", (self.b.user_id,)).fetchone()
                    self.assertFalse(account["active"])
                    self.assertEqual(account["email"], "")
                    self.assertTrue(all(row["state"] == "suppressed" for row in connection.execute("SELECT state FROM nidaa.outbox WHERE alert_id=%s", (aid,)).fetchall()))
                    for client, expected in ((self.c,"withdrawn"), (d,"blocked")):
                        self.assertEqual(connection.execute("SELECT state FROM nidaa.grants WHERE sender_id=%s AND recipient_id=%s",
                            (self.a.user_id,client.user_id)).fetchone()["state"], expected)
                        session = domain.principal(client.session["access_token"])
                        self.assertFalse(domain.consent(self.a.user_id,session["user_id"]))
                        with self.assertRaises(RuleError) as denied:
                            domain.view(session["user_id"], aid)
                        self.assertEqual(denied.exception.code, "not_found")
                    self.assertTrue(domain.blocked(self.a.user_id,d.user_id))
            finally:
                # Exact test-generated database only, no other project data is touched.
                with psycopg.connect(os.environ["DATABASE_ADMIN_URL"], autocommit=True) as connection:
                    connection.execute(psycopg.sql.SQL("DROP DATABASE {} WITH (FORCE)").format(psycopg.sql.Identifier(restore_name)))


if __name__ == "__main__":
    unittest.main()
