"""Internal maintenance CLI. Never expose these commands through an HTTP route."""
import argparse
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
from uuid import UUID, uuid4

import psycopg
from psycopg.rows import dict_row

from .domain import Domain, connect


def export_ledger():
    with connect() as conn:
        d=Domain(conn,maintenance=True)
        export_id=str(uuid4())
        d.run('UPDATE nidaa.maintenance_state SET quiesced=true,export_id=%s WHERE singleton', (export_id,))
        return {'format':2,'export_id':export_id,'source_database':d.one('SELECT current_database() AS name')['name'],
                'quiesced':True,'cursor_watermark':d.one('SELECT coalesce(max(cursor),0) AS value FROM nidaa.accounts')['value'],
                'deletions':d.all('SELECT * FROM nidaa.deletion_ledger ORDER BY requested_at,ledger_id'),
                'revocations':d.all('SELECT * FROM nidaa.revocation_ledger ORDER BY ordinal'),
                'session_revocations':d.all('SELECT * FROM nidaa.session_revocations ORDER BY revoked_before,ledger_id')}


def validate_ledger(data):
    expected={'format','export_id','source_database','quiesced','cursor_watermark','deletions','revocations','session_revocations'}
    if (not isinstance(data,dict) or set(data)!=expected or data['format']!=2 or data['quiesced'] is not True
        or type(data['cursor_watermark']) is not int or not 0<=data['cursor_watermark']<2**63-1
        or not isinstance(data['source_database'],str)
        or not all(isinstance(data[key],list) for key in ('deletions','revocations','session_revocations'))):
        raise ValueError('incomplete_restore_barriers')
    UUID(data['export_id'])


def resume_source(data):
    validate_ledger(data)
    with connect() as conn:
        d=Domain(conn,maintenance=True)
        state=d.one('SELECT export_id,quiesced FROM nidaa.maintenance_state WHERE singleton')
        if d.one('SELECT current_database() AS name')['name']!=data['source_database'] or str(state['export_id'])!=data['export_id']:
            raise ValueError('source_export_mismatch')
        d.run('UPDATE nidaa.maintenance_state SET quiesced=false WHERE singleton')
    return {'source_resumed':True}


def replay_ledger(data):
    validate_ledger(data)
    # This local drill requires a live, independently quiesced source. It is not
    # a claim that a stale file can establish freshness after a disaster.
    source_url=os.environ.get('RESTORE_SOURCE_DATABASE_URL')
    if not source_url:
        raise ValueError('quiesced_source_required')
    with psycopg.connect(source_url,row_factory=dict_row) as source, connect() as conn:
        original=Domain(source,maintenance=True)
        state=original.one('SELECT export_id,quiesced FROM nidaa.maintenance_state WHERE singleton')
        watermark=original.one('SELECT coalesce(max(cursor),0) AS value FROM nidaa.accounts')['value']
        if (not state['quiesced'] or str(state['export_id'])!=data['export_id'] or watermark!=data['cursor_watermark']
            or original.one('SELECT current_database() AS name')['name']!=data['source_database']):
            raise ValueError('stale_or_unquiesced_source')
        for key,query in (
            ('deletions','SELECT * FROM nidaa.deletion_ledger ORDER BY requested_at,ledger_id'),
            ('revocations','SELECT * FROM nidaa.revocation_ledger ORDER BY ordinal'),
            ('session_revocations','SELECT * FROM nidaa.session_revocations ORDER BY revoked_before,ledger_id')):
            if original.all(query)!=data[key]:
                raise ValueError('incomplete_or_changed_ledger')
        # Check before acquiring a second advisory lock, avoiding a same-database
        # self-deadlock when an operator accidentally points both URLs at source.
        if conn.execute('SELECT current_database() AS name').fetchone()['name']==data['source_database']:
            raise ValueError('isolated_destination_required')
        d=Domain(conn,maintenance=True)
        for entry in sorted(data.get('revocations',[]),key=lambda e:e['ordinal']):
            d.replay_revocation(entry)
        for entry in data['deletions']:
            # Ledger is trusted, administrator-owned backup input, not client-controlled.
            d.delete_account(entry['user_id'],entry['subject'],entry['requested_at'])
            d.run('''INSERT INTO nidaa.deletion_ledger(ledger_id,user_id,subject,requested_at,provider_completed)
              VALUES(%s,%s,%s,%s,false) ON CONFLICT(user_id) DO UPDATE SET provider_completed=false''',
              (entry['ledger_id'],entry['user_id'],entry['subject'],entry['requested_at']))
        for entry in data['session_revocations']:
            d.run('''INSERT INTO nidaa.session_revocations(ledger_id,user_id,session_id,all_devices,revoked_before)
              VALUES(%s,%s,%s,%s,%s) ON CONFLICT(ledger_id) DO NOTHING''',
              (entry['ledger_id'],entry['user_id'],entry['session_id'],entry['all_devices'],entry['revoked_before']))
            if entry['all_devices']:
                d.run('UPDATE nidaa.accounts SET revoked_before=greatest(revoked_before,%s) WHERE user_id=%s',
                      (entry['revoked_before'],entry['user_id']))
                d.run('UPDATE nidaa.sessions SET revoked=true WHERE user_id=%s', (entry['user_id'],))
            else:
                d.run('UPDATE nidaa.sessions SET revoked=true WHERE session_id=%s', (entry['session_id'],))
        # Export captured the maximum after domain writes were quiesced. Every
        # pre-export client cursor is <= this value; no clock assumption is used.
        d.run('UPDATE nidaa.accounts SET cursor=greatest(cursor,%s)+1,snapshot_digest=NULL', (data['cursor_watermark'],))
        d.run('UPDATE nidaa.maintenance_state SET quiesced=false,restored_export_id=%s WHERE singleton', (data['export_id'],))
        d.erase_tokens()
        return {'replayed':len(data['deletions']),'revocations_replayed':len(data['revocations']),
                'sessions_replayed':len(data['session_revocations']),'cursor_reset':True}


def cleanup_auth():
    """Separate privileged process uses GoTrue Admin API, never SQL auth writes.

    DB/domain barrier already committed. Failure leaves ledger pending for retry.
    Avoid holding SQL locks during network calls; no application/provider token output.
    """
    with connect() as conn:
        pending=Domain(conn).all('SELECT user_id,subject FROM nidaa.deletion_ledger WHERE NOT provider_completed')
    completed=0
    for item in pending:
        url=os.environ['AUTH_URL'].rstrip('/')+'/admin/users/'+item['subject']
        req=urllib.request.Request(url,method='DELETE',headers={'Authorization':'Bearer '+os.environ['AUTH_ADMIN_TOKEN']})
        accepted=False
        try:
            with urllib.request.urlopen(req,timeout=5) as response:
                accepted=response.status in (200,204)
        except urllib.error.HTTPError as exc:
            accepted=exc.code==404
        except (urllib.error.URLError,TimeoutError):
            pass
        if accepted:
            with connect() as conn:
                Domain(conn).run('UPDATE nidaa.deletion_ledger SET provider_completed=true WHERE user_id=%s', (item['user_id'],))
            completed+=1
    return {'completed':completed,'pending':len(pending)-completed}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['dispatch','purge','export-ledger','replay-ledger','resume-source','cleanup-auth'])
    parser.add_argument('--job')
    parser.add_argument('--file')
    parser.add_argument('--crash-before-commit',action='store_true')
    parser.add_argument('--crash-after-commit',action='store_true')
    args=parser.parse_args()
    if args.action=='export-ledger':
        if not args.file: parser.error('--file required; ledger is never printed to logs')
        Path(args.file).write_text(json.dumps(export_ledger(),indent=2)+'\n',encoding='utf-8')
        result={'exported':True}
    elif args.action in ('replay-ledger','resume-source'):
        if not args.file: parser.error('--file required')
        ledger=json.loads(Path(args.file).read_text(encoding='utf-8'))
        result=replay_ledger(ledger) if args.action=='replay-ledger' else resume_source(ledger)
    elif args.action=='cleanup-auth':
        result=cleanup_auth()
    else:
        try:
            with connect() as conn:
                d=Domain(conn)
                result=d.dispatch(args.job,crash=args.crash_before_commit) if args.action=='dispatch' else d.purge()
        except RuntimeError as exc:
            if str(exc)=='injected_worker_rollback':
                raise SystemExit(71) from None
            raise
        if args.crash_after_commit:
            os._exit(72)
    print(json.dumps(result))


if __name__=='__main__':
    main()
