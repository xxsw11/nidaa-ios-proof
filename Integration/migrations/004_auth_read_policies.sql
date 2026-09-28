-- GoTrue enables RLS on its tables. A SELECT grant alone returns no rows to
-- a non-owner service; narrowly allow its verified-identity/session checks.
-- Keep writes, ownership and BYPASSRLS forbidden. Do not grant password/token reads.
REVOKE SELECT ON auth.users,auth.sessions FROM nidaa_service;
GRANT SELECT(id,email,email_confirmed_at,deleted_at,banned_until) ON auth.users TO nidaa_service;
GRANT SELECT(id,user_id,created_at,not_after) ON auth.sessions TO nidaa_service;
CREATE POLICY nidaa_identity_read ON auth.users FOR SELECT TO nidaa_service USING(true);
CREATE POLICY nidaa_session_read ON auth.sessions FOR SELECT TO nidaa_service USING(true);
