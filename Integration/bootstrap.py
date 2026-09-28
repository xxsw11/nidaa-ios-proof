"""Migration-only privileged process; never an HTTP route."""
import os
import hashlib
from pathlib import Path
import psycopg
from psycopg import sql

with psycopg.connect(os.environ['DATABASE_ADMIN_URL'], autocommit=True) as conn:
    conn.execute('CREATE TABLE IF NOT EXISTS public.nidaa_migrations(name text PRIMARY KEY, sha256 text NOT NULL)')
    conn.execute('REVOKE ALL ON public.nidaa_migrations FROM PUBLIC')
    for path in sorted((Path(__file__).parent / 'migrations').glob('*.sql')):
        source = path.read_text()
        fingerprint = hashlib.sha256(source.encode()).hexdigest()
        prior = conn.execute('SELECT sha256 FROM public.nidaa_migrations WHERE name=%s', (path.name,)).fetchone()
        if prior:
            if prior[0] != fingerprint:
                raise SystemExit('Applied NIDAA migration changed; use a new migration or explicitly reset this trial.')
            continue
        with conn.transaction():
            conn.execute(source)
            conn.execute('INSERT INTO public.nidaa_migrations VALUES(%s,%s)', (path.name, fingerprint))
    conn.execute(sql.SQL('ALTER ROLE nidaa_service LOGIN PASSWORD {}').format(sql.Literal(os.environ['SERVICE_DB_PASSWORD'])))
print('NIDAA migrations applied; no credentials printed.')
