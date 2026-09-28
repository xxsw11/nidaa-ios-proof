#!/bin/bash
set -eu
psql --username postgres --dbname postgres --set=ON_ERROR_STOP=1 --set=auth_password="$AUTH_DB_PASSWORD" <<'SQL'
CREATE ROLE supabase_auth_admin LOGIN PASSWORD :'auth_password';
CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin;
ALTER ROLE supabase_auth_admin SET search_path = auth, public;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
SQL
