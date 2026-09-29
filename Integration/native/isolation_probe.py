"""Full IPv4/IPv6 runtime gate; run before credentials under the service policy."""
import json
import sys

if __package__:
    from .isolation_candidate import gate_is_verified, gate_results, probe
else:
    from isolation_candidate import gate_is_verified, gate_results, probe


def main():
    checks = gate_results(probe())
    print(json.dumps(checks, sort_keys=True))
    return 0 if gate_is_verified(checks) else 3


if __name__ == '__main__':
    sys.exit(main())
