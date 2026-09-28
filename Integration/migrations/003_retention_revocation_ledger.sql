-- Additive migration: restore barriers are separate from account deletion.
CREATE TABLE nidaa.revocation_ledger (
 ledger_id uuid PRIMARY KEY, ordinal bigint UNIQUE NOT NULL CHECK(ordinal>0),
 actor_id uuid NOT NULL,target_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN('withdraw','block','unblock')),
 created_at bigint NOT NULL,CHECK(actor_id<>target_id)
);
ALTER TABLE nidaa.revocation_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE nidaa.revocation_ledger FORCE ROW LEVEL SECURITY;
REVOKE ALL ON nidaa.revocation_ledger FROM PUBLIC,anon,authenticated;
GRANT SELECT ON nidaa.revocation_ledger TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON nidaa.revocation_ledger TO nidaa_service;
CREATE POLICY service_only ON nidaa.revocation_ledger TO nidaa_service USING(true) WITH CHECK(true);
CREATE INDEX alerts_retention ON nidaa.alerts(closed_at) WHERE closed_at IS NOT NULL;
