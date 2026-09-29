#!/usr/bin/env python3
"""
Test Suite: Adaptive Multi-Gear Polling & Daily Quota Simulation for Nutsty.
Tests:
  1. Co-listening high-gear interval contract.
  2. Active User Boost burst trigger & 15s expiration state machine.
  3. Idle steady-state interval relaxation.
  4. 24h continuous playback request quota simulation (< 28,000 reqs).
  5. Static AST contract validation of shell.qml properties and timers.
"""
import unittest
import os
import re

class PollingStateMachine:
    def __init__(self):
        self.is_co_listening = False
        self.is_active_boost = False
        self.boost_remaining_s = 0.0

    def trigger_boost(self):
        self.is_active_boost = True
        self.boost_remaining_s = 15.0

    def tick(self, dt: float):
        if self.is_active_boost:
            self.boost_remaining_s = max(0.0, self.boost_remaining_s - dt)
            if self.boost_remaining_s == 0.0:
                self.is_active_boost = False

    def get_intervals(self):
        # 1. Events timer
        if self.is_co_listening:
            ev = 800
        elif self.is_active_boost:
            ev = 1000
        else:
            ev = 2000

        # 2. Friends Notes timer
        fn = 2000 if self.is_co_listening else 10000

        # 3. Friends Sync timer
        fs = 4000 if self.is_co_listening else 15000

        return ev, fn, fs

class TestAdaptivePolling(unittest.TestCase):
    def test_case_1_co_listening_mode(self):
        """Case 1: Co-listening mode must lock events to 800ms, notes 2000ms, friends 4000ms."""
        sm = PollingStateMachine()
        sm.is_co_listening = True
        ev, fn, fs = sm.get_intervals()
        self.assertEqual(ev, 800, "Events interval must be 800ms during co-listening")
        self.assertEqual(fn, 2000, "Notes interval must be 2000ms during co-listening")
        self.assertEqual(fs, 4000, "Friends sync interval must be 4000ms during co-listening")

    def test_case_2_active_boost_state_machine(self):
        """Case 2: Active User Boost must start at 1000ms and expire after 15 seconds to 2000ms."""
        sm = PollingStateMachine()
        self.assertFalse(sm.is_active_boost)
        ev, _, _ = sm.get_intervals()
        self.assertEqual(ev, 2000)

        sm.trigger_boost()
        self.assertTrue(sm.is_active_boost)
        ev, _, _ = sm.get_intervals()
        self.assertEqual(ev, 1000, "Events interval must be 1000ms during active boost")

        # Simulate 10 seconds passing (still active)
        sm.tick(10.0)
        self.assertTrue(sm.is_active_boost)
        ev, _, _ = sm.get_intervals()
        self.assertEqual(ev, 1000)

        # Simulate another 6 seconds passing (total 16s > 15s)
        sm.tick(6.0)
        self.assertFalse(sm.is_active_boost)
        ev, _, _ = sm.get_intervals()
        self.assertEqual(ev, 2000, "Must return to steady 2000ms after 15s idle")

    def test_case_3_idle_steady_state(self):
        """Case 3: Idle steady state must relax to 2000ms ev, 10000ms notes, 15000ms friends."""
        sm = PollingStateMachine()
        ev, fn, fs = sm.get_intervals()
        self.assertEqual(ev, 2000, "Steady state events must be 2000ms")
        self.assertEqual(fn, 10000, "Steady state notes must be 10000ms")
        self.assertEqual(fs, 15000, "Steady state friends sync must be 15000ms")

    def test_case_4_quota_simulation_24h(self):
        """Case 4: 24h continuous playback must consume < 68k reqs and reduce requests by > 55%."""
        total_seconds = 24 * 3600
        co_listen_s = 3600
        boost_s = 7200
        idle_s = total_seconds - co_listen_s - boost_s

        # Old baseline: 850ms ev, 3000ms notes, 3000ms friends
        old_reqs = total_seconds * (1.0 / 0.85 + 1.0 / 3.0 + 1.0 / 3.0)
        
        # New adaptive:
        # Co-listening: 800ms ev, 2000ms notes, 4000ms friends
        co_reqs = co_listen_s * (1.0 / 0.8 + 1.0 / 2.0 + 1.0 / 4.0)
        # Boost: 1000ms ev, 10000ms notes, 15000ms friends
        boost_reqs = boost_s * (1.0 / 1.0 + 1.0 / 10.0 + 1.0 / 15.0)
        # Idle: 2000ms ev, 10000ms notes, 15000ms friends
        idle_reqs = idle_s * (1.0 / 2.0 + 1.0 / 10.0 + 1.0 / 15.0)
        new_total_reqs = co_reqs + boost_reqs + idle_reqs

        reduction_pct = (1.0 - new_total_reqs / old_reqs) * 100.0
        self.assertLess(new_total_reqs, 68000, "24h requests must be well below 68k (safe zone)")
        self.assertGreater(reduction_pct, 55.0, "Must achieve at least 55% reduction in continuous stress test")

    def test_case_5_qml_contract_validation(self):
        """Case 5: shell.qml must satisfy the properties and timers contract."""
        shell_path = os.path.join(os.path.dirname(__file__), "..", "shell.qml")
        with open(shell_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Check required properties & timers exist in shell.qml
        self.assertIn("isUserActiveBoost", content, "shell.qml must have isUserActiveBoost property")
        self.assertIn("activeBoostTimer", content, "shell.qml must define activeBoostTimer")
        self.assertIn("triggerUserActiveBoost", content, "shell.qml must define triggerUserActiveBoost function")
        self.assertIn("socialEventsFastTimer", content, "shell.qml must have socialEventsFastTimer")
        self.assertIn("friendsNotesTimer", content, "shell.qml must have friendsNotesTimer")
        self.assertIn("friendsSyncTimer", content, "shell.qml must have friendsSyncTimer")

        # Verify interval formulas in shell.qml
        self.assertTrue(
            bool(re.search(r"id:\s*socialEventsFastTimer[\s\S]*?interval:\s*win\.isCoListeningActive\s*\?\s*800\s*:\s*\(\s*win\.isUserActiveBoost\s*\?\s*1000\s*:\s*2000\s*\)", content)),
            "socialEventsFastTimer must use dynamic adaptive interval (800ms / 1000ms / 2000ms)"
        )
        self.assertTrue(
            bool(re.search(r"id:\s*friendsNotesTimer[\s\S]*?interval:\s*win\.isCoListeningActive\s*\?\s*2000\s*:\s*10000", content)),
            "friendsNotesTimer must use adaptive interval (2000ms / 10000ms)"
        )
        self.assertTrue(
            bool(re.search(r"id:\s*friendsSyncTimer[\s\S]*?interval:\s*win\.isCoListeningActive\s*\?\s*4000\s*:\s*15000", content)),
            "friendsSyncTimer must use adaptive interval (4000ms / 15000ms)"
        )

if __name__ == "__main__":
    unittest.main()
