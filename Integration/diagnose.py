"""Fail-fast verified Auth/domain preflight; outputs only booleans/error class/line.

No credentials, JWT claim values, database rows or provider error bodies are logged.
"""
import json
import os
import traceback
import jwt
from Integration.tests.harness import LocalAccount
from Integration.service.domain import Domain, connect


def main():
    account = LocalAccount('Sara').signup()
    try:
        token = account.session['access_token']
        try:
            claims = jwt.decode(token,os.environ['JWT_SECRET'],algorithms=['HS256'],
                                audience='authenticated',issuer=os.environ['AUTH_ISSUER'],
                                options={'require':['exp','iat','sub','session_id','aud','iss']})
            print(json.dumps({'jwt_validation':True,'role_matches':claims.get('role')=='authenticated',
                              'anonymous':bool(claims.get('is_anonymous',False)),'has_amr':bool(claims.get('amr'))}))
        except jwt.PyJWTError as error:
            print(json.dumps({'jwt_validation':False,'error_class':type(error).__name__}))
            raise SystemExit(1) from None
        try:
            with connect() as connection:
                Domain(connection).principal(token)
        except Exception as error:
            frames = traceback.extract_tb(error.__traceback__)
            print(json.dumps({'domain_principal':False,'error_class':type(error).__name__,
                              'frames':[{'function':frame.name,'line':frame.lineno} for frame in frames]}))
            raise SystemExit(1) from None
        account.me()
        print('Real inbox-verified Auth session accepted by domain over HTTP.')
    finally:
        account.close()


if __name__ == '__main__':
    main()
