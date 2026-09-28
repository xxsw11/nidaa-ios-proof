-- Apply AFTER local GoTrue schema migrations. Select only the two revocation sources.
GRANT USAGE ON SCHEMA auth TO nidaa_service;
GRANT SELECT ON auth.users,auth.sessions TO nidaa_service;
