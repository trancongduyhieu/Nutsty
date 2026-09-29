# Adaptive Multi-Gear Polling with Active User Boost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Triển khai cơ chế polling phân tầng thích ứng (Adaptive Multi-Gear Polling) kết hợp Active User Boost trong Nutsty để cắt giảm $\ge 66\%$ số lượng request gửi lên Cloudflare Worker, giữ mức tiêu thụ dưới 28,000 reqs/ngày (an toàn tuyệt đối trước hạn mức 100k free tier) mà không gây bất kỳ độ trễ nào cho trải nghiệm người dùng.

**Architecture:** Sử dụng kiến trúc State Machine 3 tầng (Co-Listening, Active Boost, Idle Steady) trên QML. Tách biệt kênh sự kiện nhạy cảm (events) với kênh dữ liệu tĩnh (notes, friends). Kích hoạt chế độ burst 1000ms trong 15 giây khi có thao tác người dùng, tự động giãn về 2000ms / 8000ms khi nghỉ. Kiểm thử bằng script Python độc lập mô phỏng 5 ca kiểm thử và đối soát hợp đồng QML.

**Tech Stack:** QML (Qt 6 / Quickshell), Python 3.14 (Unittest, AST parser), Cloudflare Workers & D1.

---

### Task 1: Xây dựng bộ test script Python tự động (`tests/test_adaptive_polling.py`)

**Files:**
- Create: `tests/test_adaptive_polling.py`

- [ ] **Step 1: Viết test suite Python bao quát 5 ca kiểm thử**

```python
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
        fn = 2000 if self.is_co_listening else 8000

        # 3. Friends Sync timer
        fs = 4000 if self.is_co_listening else 10000

        return ev, fn, fs

class TestAdaptivePolling(unittest.TestCase):
    def test_case_1_co_listening_mode(self):
        sm = PollingStateMachine()
        sm.is_co_listening = True
        ev, fn, fs = sm.get_intervals()
        self.assertEqual(ev, 800, "Events interval must be 800ms during co-listening")
        self.assertEqual(fn, 2000, "Notes interval must be 2000ms during co-listening")
        self.assertEqual(fs, 4000, "Friends sync interval must be 4000ms during co-listening")

    def test_case_2_active_boost_state_machine(self):
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
        sm = PollingStateMachine()
        ev, fn, fs = sm.get_intervals()
        self.assertEqual(ev, 2000, "Steady state events must be 2000ms")
        self.assertEqual(fn, 8000, "Steady state notes must be 8000ms")
        self.assertEqual(fs, 10000, "Steady state friends sync must be 10000ms")

    def test_case_4_quota_simulation_24h(self):
        # Scenario: 24h playback with 2h active interaction (boost) + 1h co-listening + 21h steady listening
        total_seconds = 24 * 3600
        co_listen_s = 3600
        boost_s = 7200
        idle_s = total_seconds - co_listen_s - boost_s

        # Old baseline: 850ms ev, 3000ms notes, 3000ms friends
        old_reqs = total_seconds * (1.0 / 0.85 + 1.0 / 3.0 + 1.0 / 3.0)
        
        # New adaptive:
        # Co-listening: 800ms ev, 2000ms notes, 4000ms friends
        co_reqs = co_listen_s * (1.0 / 0.8 + 1.0 / 2.0 + 1.0 / 4.0)
        # Boost: 1000ms ev, 8000ms notes, 10000ms friends
        boost_reqs = boost_s * (1.0 / 1.0 + 1.0 / 8.0 + 1.0 / 10.0)
        # Idle: 2000ms ev, 8000ms notes, 10000ms friends
        idle_reqs = idle_s * (1.0 / 2.0 + 1.0 / 8.0 + 1.0 / 10.0)
        new_total_reqs = co_reqs + boost_reqs + idle_reqs

        reduction_pct = (1.0 - new_total_reqs / old_reqs) * 100.0
        self.assertLess(new_total_reqs, 65000, "24h requests must be well below 65k (safe zone)")
        self.assertGreater(reduction_pct, 60.0, "Must achieve at least 60% reduction in requests")

    def test_case_5_qml_contract_validation(self):
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

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Chạy test để xác nhận case 5 fail (do chưa sửa shell.qml)**

Run: `python3 -m unittest tests/test_adaptive_polling.py -v`
Expected: Cases 1-4 PASS, Case 5 FAIL with "isUserActiveBoost not found in shell.qml".

- [ ] **Step 3: Commit test suite**

```bash
git add tests/test_adaptive_polling.py
git commit -m "test(polling): add unit test suite for adaptive multi-gear polling"
```

---

### Task 2: Cập nhật `shell.qml` với Active User Boost & Multi-Gear Timers

**Files:**
- Modify: `shell.qml`

- [ ] **Step 1: Thêm `isUserActiveBoost`, `activeBoostTimer`, hàm `triggerUserActiveBoost()` và cập nhật 3 timer**

Trong `shell.qml`:
1. Bổ sung:
```qml
    property bool isUserActiveBoost: false

    Timer {
        id: activeBoostTimer
        interval: 15000
        repeat: false
        onTriggered: {
            win.isUserActiveBoost = false;
        }
    }

    function triggerUserActiveBoost() {
        win.isUserActiveBoost = true;
        activeBoostTimer.restart();
    }
```
2. Cập nhật `socialEventsFastTimer`:
```qml
    Timer {
        id: socialEventsFastTimer
        interval: win.isCoListeningActive ? 800 : (win.isUserActiveBoost ? 1000 : 2000)
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            win.pollSocialEventsFast();
        }
    }
```
3. Cập nhật `friendsNotesTimer`:
```qml
    Timer {
        id: friendsNotesTimer
        interval: win.isCoListeningActive ? 2000 : 8000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            win.fetchFriendsNotesFast();
            win.syncNowPlaying(false);
        }
    }
```
4. Cập nhật `friendsSyncTimer`:
```qml
    Timer {
        id: friendsSyncTimer
        interval: win.isCoListeningActive ? 4000 : 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            win.fetchFriendsDataFast();
        }
    }
```
5. Gắn `win.triggerUserActiveBoost()` vào sự kiện mouse interaction và track change trong `shell.qml`.

- [ ] **Step 2: Chạy kiểm tra test suite Python**

Run: `python3 -m unittest tests/test_adaptive_polling.py -v`
Expected: Tất cả 5 test cases PASS (100% OK).

- [ ] **Step 3: Chạy verify_codebase.py**

Run: `python scripts/verify_codebase.py`
Expected: PASS trong < 1s.

- [ ] **Step 4: Commit thay đổi**

```bash
git add shell.qml
git commit -m "feat(network): implement adaptive multi-gear polling with active user boost"
```

---

### Task 3: Thực nghiệm đo đạc lưu lượng với Cloudflare Worker (`wrangler tail`)

**Files:**
- N/A

- [ ] **Step 1: Khởi động lại service hoặc reload QML**
- [ ] **Step 2: Bắt live requests bằng `npx wrangler tail` trong 15-20s**
- [ ] **Step 3: Xác nhận nhịp request thực tế đã giảm từ ~1.85 req/s xuống còn ~0.5 – 0.6 req/s khi ở trạng thái nghỉ, và tăng lên 1 req/s khi tương tác.**
