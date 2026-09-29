"""Fail-closed gate tests with explicit observations, never real socket activity."""
from copy import deepcopy
import errno
import io
from contextlib import redirect_stdout
import json
import unittest
from unittest.mock import patch

from Integration.native import isolation_candidate as gate
from Integration.native import isolation_probe


def observations():
    denied = {'status': 'policy_denied', 'errno': errno.EPERM, 'stage': 'operation'}
    allowed = {'status': 'succeeded', 'errno': None, 'stage': 'operation'}
    item = {key: deepcopy(denied) for key in ('externalTCP', 'externalUDP', 'wildcardUDPBind', 'implicitWildcardListen')}
    item['wildcardTCP'] = {'bind': {'status': 'policy_denied', 'errno': errno.EPERM}, 'listen': {'status': 'not_attempted'}}
    item.update({key: deepcopy(allowed) for key in ('loopbackTCP', 'loopbackUDP')})
    return {'IPv4': deepcopy(item), 'IPv6': deepcopy(item)}


class IsolationGateTests(unittest.TestCase):
    def test_complete_matrix_and_wire_contract(self):
        checks = gate.gate_results(observations())
        self.assertEqual(len(checks), 14)
        self.assertTrue(gate.gate_is_verified(checks))
        for key in checks:
            missing = checks.copy(); missing.pop(key)
            self.assertFalse(gate.gate_is_verified(missing))
        self.assertFalse(gate.gate_is_verified(dict(checks, extra=True)))
        checks['externalIPv6UDPDeniedByPolicy'] = 1
        self.assertFalse(gate.gate_is_verified(checks))

    def test_actual_candidate_wildcard_success_never_passes(self):
        for family in ('IPv4', 'IPv6'):
            for operation in ('wildcardUDPBind', 'implicitWildcardListen'):
                values = observations()
                values[family][operation] = {'status': 'succeeded', 'errno': None, 'stage': 'operation'}
                self.assertFalse(gate.passed(values))
            values = observations()
            values[family]['wildcardTCP'] = {'bind': {'status': 'succeeded', 'errno': None},
                                           'listen': {'status': 'policy_denied', 'errno': errno.EPERM}}
            self.assertFalse(gate.passed(values), 'Even a later listen denial cannot excuse successful wildcard bind')

    def test_unreachability_and_socket_creation_denial_are_not_operation_proof(self):
        for family in ('IPv4', 'IPv6'):
            for code in (None, errno.ETIMEDOUT, errno.ECONNREFUSED, errno.ENETUNREACH):
                values = observations(); values[family]['externalUDP']['errno'] = code
                self.assertFalse(gate.passed(values))
            values = observations(); values[family]['externalTCP']['stage'] = 'create'
            self.assertFalse(gate.passed(values))

    def test_missing_family_or_malformed_observation_fails_closed(self):
        for values in (None, {}, {'IPv4': observations()['IPv4']}, {'IPv4': None, 'IPv6': {}}):
            checks = gate.gate_results(values)
            self.assertEqual(set(checks), gate.GATE_KEYS)
            self.assertFalse(gate.gate_is_verified(checks))

    def test_deny_everything_is_only_a_control_not_a_working_runtime(self):
        values = observations()
        for family in values.values():
            for protocol in ('TCP', 'UDP'):
                family['loopback'+protocol] = {'status': 'policy_denied', 'errno': errno.EACCES, 'stage': 'operation'}
        self.assertTrue(gate.passed(values, control=True))
        self.assertFalse(gate.passed(values))

    def test_runtime_probe_reports_failed_full_matrix_without_network_calls(self):
        values = observations(); values['IPv6']['implicitWildcardListen']['status'] = 'succeeded'
        with patch.object(isolation_probe, 'probe', return_value=values), redirect_stdout(io.StringIO()) as output:
            result = isolation_probe.main()
        self.assertEqual(result, 3)
        report = json.loads(output.getvalue())
        self.assertEqual(set(report), gate.GATE_KEYS)
        self.assertFalse(report['wildcardIPv6ImplicitListenDeniedByPolicy'])


if __name__ == '__main__':
    unittest.main()
