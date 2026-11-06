import unittest
from unittest.mock import patch

import benchmark_host as host
import benchmark_smoke as smoke


class Response:
    def __init__(self, status, body="", location=None):
        self.status, self.body, self.location = status, body.encode(), location

    def read(self, limit):
        return self.body[:limit]

    def getheader(self, key):
        return self.location

    def getheaders(self):
        return [("Set-Cookie", "_instantflow_key=synthetic-cookie; Secure; HttpOnly")]


class SmokeTest(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.responses = [
            Response(200, '<form id="login-form"><input name="_csrf_token" value="csrf"></form>'),
            Response(302, location="/o/example"),
            Response(200, '<meta name="csrf-token" content="renewed"><form id="section-form-request"></form>'),
            Response(302, location="/entrar"), Response(302, location="/entrar"),
        ]

    def connection(self, domain, **options):
        self.assertEqual(domain, host.DOMAIN)
        self.assertTrue(options["context"].check_hostname)
        test = self

        class Connection:
            def request(self, method, path, body, headers):
                self._create_connection(("ignored.example", 443), 15, None)
                test.requests.append((method, path, body, headers))

            def getresponse(self):
                return test.responses.pop(0)

            def close(self):
                pass

        return Connection()

    def run_smoke(self):
        with patch.object(smoke, "credentials", return_value={"email": "synthetic@example.test",
            "password": "synthetic-password", "record_path": "/o/example/processos/1/registros/1"}), \
                patch.object(smoke.http.client, "HTTPSConnection", side_effect=self.connection), \
                patch.object(smoke.socket, "create_connection") as connect:
            result = smoke.smoke()
            for call in connect.call_args_list:
                self.assertEqual(call.args[0], ("127.0.0.1", 443))
            return result

    def test_authentication_record_read_and_logout_use_only_fixed_local_tls_route(self):
        result = self.run_smoke()
        self.assertTrue(result["authenticated_record_read"])
        self.assertIn("_csrf_token=renewed", self.requests[3][2])
        self.assertIn("_instantflow_key=synthetic-cookie", self.requests[2][3]["Cookie"])
        self.assertNotIn("password", str(result))

    def test_auth_failure_external_redirect_and_missing_authorized_record_fail_closed(self):
        for index, response in [(1, Response(422)), (1, Response(302, location="https://elsewhere.example/")),
                                (2, Response(302, location="/entrar")), (2, Response(200, "anonymous page")),
                                (4, Response(200, "still authenticated"))]:
            self.setUp()
            self.responses[index] = response
            with self.assertRaises(host.GuardError):
                self.run_smoke()
