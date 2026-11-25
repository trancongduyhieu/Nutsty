#!/usr/bin/env python3
"""Tidal login and status routes, through the same dispatch_request the Rust daemon calls.
tidal_source is faked: no tidalapi, no network. Run: python scripts/test_tidal_routes.py"""
import json
import os
import sys
import types
import unittest
from unittest import mock

BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

import route_dispatcher as rd


def fake_tidal(**overrides):
    m = types.ModuleType("tidal_source")
    m.calls = []
    m.status = lambda: {"logged_in": True, "account": "duy", "subscription": "HiFi Plus",
                        "can_hires": True, "can_lossless": True, "needs_relogin": False}
    m.login_start = lambda: {"url": "https://link.tidal.com/ABCDE", "code": "ABCDE", "expires_in": 300}
    m.login_poll = lambda: {"state": "pending", "account": "", "subscription": ""}
    m.logout = lambda: m.calls.append("logout")
    for k, v in overrides.items():
        setattr(m, k, v)
    return m


def call(method, path, mod):
    with mock.patch.dict(sys.modules, {"tidal_source": mod}):
        res = rd.dispatch_request(method, path, {}, "")
    return res


def body(res):
    # dispatch_request returns the handler or a dict, depending on the caller; read both
    if isinstance(res, dict):
        return res.get("status_code", res.get("status")), json.loads(res.get("body") or res.get("response_body"))
    return res.status_code, json.loads(res.response_body)


def boom(*a, **k):
    raise RuntimeError("tidal is down")


class TidalRoutesTest(unittest.TestCase):
    def test_status(self):
        code, data = body(call("GET", "/api/tidal/status", fake_tidal()))
        self.assertEqual(code, 200)
        self.assertTrue(data["logged_in"])
        self.assertEqual(data["subscription"], "HiFi Plus")

    def test_login_start(self):
        code, data = body(call("POST", "/api/tidal/login/start", fake_tidal()))
        self.assertEqual(code, 200)
        self.assertEqual(data, {"url": "https://link.tidal.com/ABCDE", "code": "ABCDE", "expires_in": 300})

    def test_login_poll(self):
        code, data = body(call("GET", "/api/tidal/login/poll", fake_tidal()))
        self.assertEqual(code, 200)
        self.assertEqual(data["state"], "pending")

    def test_logout(self):
        mod = fake_tidal()
        code, data = body(call("POST", "/api/tidal/logout", mod))
        self.assertEqual((code, data), (200, {"success": True}))
        self.assertEqual(mod.calls, ["logout"])

    def test_errors_do_not_crash(self):
        mod = fake_tidal(status=boom, login_start=boom, login_poll=boom, logout=boom)
        self.assertEqual(body(call("GET", "/api/tidal/status", mod))[1]["logged_in"], False)
        for method, path in (("POST", "/api/tidal/login/start"), ("GET", "/api/tidal/login/poll"),
                             ("GET", "/api/tidal/status"), ("POST", "/api/tidal/logout")):
            code, data = body(call(method, path, mod))
            self.assertEqual(code, 200, path)
            self.assertEqual(data["state"], "error", path)
            self.assertNotIn("tidal is down", json.dumps(data), "exception text stays out of the response")


if __name__ == "__main__":
    unittest.main()
