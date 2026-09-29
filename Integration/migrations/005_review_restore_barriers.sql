-- Additive review migration. Existing migration hashes remain unchanged.
ALTER TABLE nidaa.accounts ADD COLUMN snapshot_digest text;
CREATE TABLE nidaa.maintenance_state (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 quiesced boolean NOT NULL DEFAULT false, export_id uuid,
 restored_export_id uuid, CHECK(NOT quiesced OR export_id IS NOT NULL)
);
INSERT INTO nidaa.maintenance_state(singleton) VALUES(true);
CREATE TABLE nidaa.session_revocations (
 ledger_id uuid PRIMARY KEY,user_id uuid NOT NULL,session_id uuid,
 all_devices boolean NOT NULL,revoked_before bigint NOT NULL,
 CHECK((all_devices AND session_id IS NULL) OR (NOT all_devices AND session_id IS NOT NULL))
);
CREATE INDEX session_revocations_owner ON nidaa.session_revocations(user_id);
DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['maintenance_state','session_revocations'] LOOP
  EXECUTE format('ALTER TABLE nidaa.%I ENABLE ROW LEVEL SECURITY',table_name);
  EXECUTE format('ALTER TABLE nidaa.%I FORCE ROW LEVEL SECURITY',table_name);
  EXECUTE format('REVOKE ALL ON nidaa.%I FROM PUBLIC,anon,authenticated',table_name);
  EXECUTE format('GRANT SELECT ON nidaa.%I TO authenticated',table_name);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON nidaa.%I TO nidaa_service',table_name);
  EXECUTE format('CREATE POLICY service_only ON nidaa.%I TO nidaa_service USING(true) WITH CHECK(true)',table_name);
 END LOOP;
END $$;
