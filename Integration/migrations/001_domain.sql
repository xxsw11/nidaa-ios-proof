-- Run with bootstrap administrator. Runtime API never owns tables or bypasses RLS.
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='nidaa_service') THEN CREATE ROLE nidaa_service NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS nidaa;
REVOKE ALL ON SCHEMA nidaa FROM PUBLIC;
GRANT USAGE ON SCHEMA nidaa TO nidaa_service,anon,authenticated;
CREATE TABLE nidaa.accounts (
 user_id uuid PRIMARY KEY, subject uuid UNIQUE NOT NULL, active boolean NOT NULL DEFAULT true,
 email text NOT NULL, display_name varchar(80) NOT NULL, created_at bigint NOT NULL,
 cursor bigint NOT NULL DEFAULT 0, revoked_before bigint NOT NULL DEFAULT 0
);
CREATE TABLE nidaa.sessions (
 session_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES nidaa.accounts,
 device_id uuid UNIQUE NOT NULL, auth_at bigint NOT NULL, revoked boolean NOT NULL DEFAULT false
);
CREATE TABLE nidaa.invitations (
 invitation_id uuid PRIMARY KEY, sender_id uuid NOT NULL REFERENCES nidaa.accounts,
 intended_email text NOT NULL, token_digest text UNIQUE, state text NOT NULL
 CHECK(state IN('pending','accepted','declined','expired','cancelled','blocked','withdrawn','deleted')),
 expires_at bigint NOT NULL, created_at bigint NOT NULL, accepted_by uuid REFERENCES nidaa.accounts
);
CREATE INDEX invitations_target ON nidaa.invitations(intended_email,state);
CREATE TABLE nidaa.grants (
 sender_id uuid REFERENCES nidaa.accounts, recipient_id uuid REFERENCES nidaa.accounts,
 state text NOT NULL CHECK(state IN('accepted','withdrawn','blocked','deleted')),
 invitation_id uuid REFERENCES nidaa.invitations ON DELETE SET NULL, version integer NOT NULL DEFAULT 1,
 PRIMARY KEY(sender_id,recipient_id), CHECK(sender_id<>recipient_id)
);
CREATE TABLE nidaa.blocks (
 blocker_id uuid REFERENCES nidaa.accounts,target_id uuid REFERENCES nidaa.accounts,
 created_at bigint NOT NULL, PRIMARY KEY(blocker_id,target_id),CHECK(blocker_id<>target_id)
);
CREATE TABLE nidaa.alerts (
 alert_id uuid PRIMARY KEY,sender_id uuid NOT NULL REFERENCES nidaa.accounts,
 state text NOT NULL CHECK(state IN('active','cancelled','resolved','expired')),
 version integer NOT NULL CHECK(version>0),created_at bigint NOT NULL,expires_at bigint NOT NULL,
 closed_at bigint, CHECK((state='active')=(closed_at IS NULL)),CHECK(expires_at>created_at)
);
CREATE INDEX alerts_expiry ON nidaa.alerts(expires_at) WHERE state='active';
CREATE TABLE nidaa.recipients (
 alert_id uuid REFERENCES nidaa.alerts ON DELETE CASCADE,user_id uuid REFERENCES nidaa.accounts,
 response text NOT NULL DEFAULT 'none' CHECK(response IN('none','responding','declined')),
 response_version integer NOT NULL DEFAULT 0,access text NOT NULL DEFAULT 'active'
 CHECK(access IN('active','withdrawn','blocked','deleted')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 2),
 provider_accepted boolean NOT NULL DEFAULT false,PRIMARY KEY(alert_id,user_id)
);
CREATE INDEX recipients_owner ON nidaa.recipients(user_id,alert_id);
CREATE TABLE nidaa.acknowledgements (
 alert_id uuid,user_id uuid,device_id uuid NOT NULL,event_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('app_acknowledged','opened')),created_at bigint NOT NULL,
 PRIMARY KEY(alert_id,user_id,device_id,event_id),
 FOREIGN KEY(alert_id,user_id) REFERENCES nidaa.recipients ON DELETE CASCADE
);
CREATE TABLE nidaa.operations (
 actor_id uuid REFERENCES nidaa.accounts,operation_id uuid,fingerprint text NOT NULL,
 status text NOT NULL CHECK(status IN('accepted','rejected')),resource_id uuid,error text,
 created_at bigint NOT NULL,token_ciphertext text,PRIMARY KEY(actor_id,operation_id)
);
CREATE TABLE nidaa.outbox (
 job_id uuid PRIMARY KEY,alert_id uuid,recipient_id uuid,ordinal integer NOT NULL,
 state text NOT NULL DEFAULT 'queued' CHECK(state IN('queued','suppressed','provider_accepted')),
 created_at bigint NOT NULL,deadline bigint NOT NULL,UNIQUE(alert_id,recipient_id,ordinal),
 FOREIGN KEY(alert_id,recipient_id) REFERENCES nidaa.recipients ON DELETE CASCADE
);
CREATE INDEX outbox_queued ON nidaa.outbox(created_at) WHERE state='queued';
CREATE TABLE nidaa.fake_handoffs (
 job_id uuid PRIMARY KEY REFERENCES nidaa.outbox ON DELETE CASCADE,accepted_at bigint NOT NULL,
 adapter text NOT NULL DEFAULT 'fake' CHECK(adapter='fake')
);
CREATE TABLE nidaa.history_hides (
 user_id uuid REFERENCES nidaa.accounts,alert_id uuid REFERENCES nidaa.alerts ON DELETE CASCADE,
 created_at bigint NOT NULL,PRIMARY KEY(user_id,alert_id)
);
CREATE TABLE nidaa.removals (
 user_id uuid REFERENCES nidaa.accounts,alert_id uuid,created_at bigint NOT NULL,PRIMARY KEY(user_id,alert_id)
);
CREATE TABLE nidaa.rate_events (
 user_id uuid REFERENCES nidaa.accounts,command text NOT NULL,created_at bigint NOT NULL
);
CREATE INDEX rate_events_lookup ON nidaa.rate_events(user_id,command,created_at);
-- Ledger is exported independently of backups; replay before service can access a restore.
CREATE TABLE nidaa.deletion_ledger (
 ledger_id uuid PRIMARY KEY,user_id uuid NOT NULL,subject uuid NOT NULL,requested_at bigint NOT NULL,
 provider_completed boolean NOT NULL DEFAULT false, UNIQUE(user_id)
);
DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='nidaa' LOOP
  EXECUTE format('ALTER TABLE nidaa.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('ALTER TABLE nidaa.%I FORCE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('REVOKE ALL ON nidaa.%I FROM PUBLIC,anon,authenticated',t.tablename);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON nidaa.%I TO nidaa_service',t.tablename);
  EXECUTE format('CREATE POLICY service_only ON nidaa.%I TO nidaa_service USING(true) WITH CHECK(true)',t.tablename);
  -- Authenticated clients can test direct SELECT with real claims; no policy gives rows.
  EXECUTE format('GRANT SELECT ON nidaa.%I TO authenticated',t.tablename);
 END LOOP;
END $$;
-- No ownership, DDL, role switching, auth mutation or RLS bypass for API credentials.
