"""Internal maintenance CLI. Never expose these commands through an HTTP route."""
import argparse
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

from .domain import Domain, connect


def export_ledger():
    with connect() as conn:
        d=Domain(conn)
        return {'format':1,'deletions':d.all('SELECT * FROM nidaa.deletion_ledger ORDER BY requested_at,ledger_id'),
                'revocations':d.all('SELECT * FROM nidaa.revocation_ledger ORDER BY ordinal')}


def replay_ledger(data):
    if set(data) not in ({'format','deletions'},{'format','deletions','revocations'}) or data['format']!=1:
        raise ValueError('invalid_ledger')
    with connect() as conn:
        d=Domain(conn)
        for entry in sorted(data.get('revocations',[]),key=lambda e:e['ordinal']):
            d.replay_revocation(entry)
        for entry in data['deletions']:
            # Ledger is trusted, administrator-owned backup input, not client-controlled.
            d.delete_account(entry['user_id'],entry['subject'],entry['requested_at'])
            d.run('''INSERT INTO nidaa.deletion_ledger(ledger_id,user_id,subject,requested_at,provider_completed)
              VALUES(%s,%s,%s,%s,false) ON CONFLICT(user_id) DO UPDATE SET provider_completed=false''',
              (entry['ledger_id'],entry['user_id'],entry['subject'],entry['requested_at']))
        d.erase_tokens()
        return {'replayed':len(data['deletions']),'revocations_replayed':len(data.get('revocations',[]))}


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
    parser.add_argument('action',choices=['dispatch','purge','export-ledger','replay-ledger','cleanup-auth'])
    parser.add_argument('--job')
    parser.add_argument('--file')
    parser.add_argument('--crash-before-commit',action='store_true')
    parser.add_argument('--crash-after-commit',action='store_true')
    args=parser.parse_args()
    if args.action=='export-ledger':
        if not args.file: parser.error('--file required; ledger is never printed to logs')
        Path(args.file).write_text(json.dumps(export_ledger(),indent=2)+'\n',encoding='utf-8')
        result={'exported':True}
    elif args.action=='replay-ledger':
        if not args.file: parser.error('--file required')
        result=replay_ledger(json.loads(Path(args.file).read_text(encoding='utf-8')))
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
