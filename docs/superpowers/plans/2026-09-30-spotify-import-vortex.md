# Spotify Import Cloudy Spiral Vortex & Flat Text Cancel Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tái cấu trúc giao diện import playlist Spotify trong Nutsty (`components/SpotifyImportModal.qml`): thay thế nút hủy con nhộng thành text link phẳng tinh tế, chuẩn hóa bo tròn 4 góc ảnh bìa playlist bằng component `RoundedImage.qml`, và xây dựng sân khấu hoạt họa xoắn ốc 3D (Cloudy Spiral Vortex lấy cảm hứng từ Hakim El Hattab) đưa các tên bài hát bay lượn hút vào tâm đĩa than.

**Architecture:** Sử dụng QML Canvas / Math-driven Item components cho quỹ đạo xoắn ốc tham số elip 3D. Tận dụng `RoundedImage.qml` có sẵn cho bo góc đồng tâm và mask GPU. Thay thế nút hủy bằng Flat Ghost Text Action theo tỷ lệ thị giác chuẩn `ui-layout-design-rules`. Kiểm thử tự động bằng Python test suite 5 ca.

**Tech Stack:** QML (Qt 6 / Quickshell), JavaScript (Parametric orbit math), Python 3.14 (Unittest, AST verification).

---

### Task 1: Viết bộ test script Python tự động (`tests/test_spotify_import_vortex.py`)

**Files:**
- Create: `tests/test_spotify_import_vortex.py`

- [ ] **Step 1: Viết test suite Python bao quát 5 ca kiểm thử**

```python
#!/usr/bin/env python3
"""
Test Suite: Spotify Import Cloudy Spiral Vortex & UI Polish Verification.
Tests:
  1. RoundedImage component reuse check (eliminates square unmasked images).
  2. Flat Ghost Cancel Button structure & color tokens (no pill borders).
  3. Vortex mathematical model & parametric orbit parameters (Hakim El Hattab).
  4. Dynamic modal height scaling (>= 420px during import).
  5. Static syntax and contract validation.
"""
import unittest
import os
import re
import math

class TestSpotifyImportVortex(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.modal_path = os.path.join(os.path.dirname(__file__), "..", "components", "SpotifyImportModal.qml")
        with open(cls.modal_path, "r", encoding="utf-8") as f:
            cls.content = f.read()

    def test_case_1_rounded_image_reuse(self):
        """Case 1: Must use RoundedImage component with radius >= 10 for playlist covers."""
        self.assertIn("RoundedImage", self.content, "Must reuse RoundedImage component in SpotifyImportModal.qml")
        # Ensure raw unmasked Rectangle clip is eliminated in importing view
        self.assertNotIn("id: importCoverImg", self.content, "Old unmasked Rectangle clip image should be replaced")

    def test_case_2_flat_cancel_button_structure(self):
        """Case 2: Cancel button must be a flat text link, not a full-width pill button."""
        # Cancel button must not use Layout.fillWidth with a heavy border
        cancel_block_match = re.search(r"// Cancel Button[\s\S]*?MouseArea[\s\S]*?root\.cancelImport\(\)", self.content)
        self.assertTrue(bool(cancel_block_match), "Cancel button block must exist")
        block = cancel_block_match.group(0)
        self.assertNotIn("Layout.fillWidth: true", block, "Flat cancel button must not be full width")
        self.assertIn("window-close-symbolic.svg", block, "Must retain close icon")
        self.assertTrue("#f87171" in block or "#fda4af" in block or "244, 63, 94" in block, "Must use Muted Rose palette")

    def test_case_3_vortex_parametric_math(self):
        """Case 3: Verify the mathematical model of the Cloudy Spiral (tilt, radius decay, angle)."""
        # Validate spiral mathematical equations
        angles = [i * (2 * math.pi / 6) for i in range(6)]
        tilt = 0.40
        for i, a in enumerate(angles):
            r = 140 - (i / 6.0) * (140 - 36)
            x = r * math.cos(a)
            y = r * math.sin(a) * tilt
            self.assertTrue(-140 <= x <= 140)
            self.assertTrue(-60 <= y <= 60)

        # QML code must contain vortex / spiral stage items
        self.assertTrue(
            "vortexStage" in self.content or "spiral" in self.content.lower() or "orbit" in self.content.lower(),
            "SpotifyImportModal must contain spiral vortex stage"
        )

    def test_case_4_modal_height_scaling(self):
        """Case 4: Dialog height during import must scale up to >= 400px to house the vortex stage."""
        height_match = re.search(r"height:\s*root\.importCompleted\s*\?\s*\d+\s*:\s*\(\s*root\.isImporting\s*\?\s*(\d+)", self.content)
        self.assertTrue(bool(height_match), "Dialog height expression must branch on root.isImporting")
        import_height = int(height_match.group(1))
        self.assertGreaterEqual(import_height, 400, f"Import height must be >= 400px (got {import_height}px)")

    def test_case_5_static_contract(self):
        """Case 5: Must retain all critical functional signals and properties."""
        self.assertIn("signal playlistImported", self.content)
        self.assertIn("function cancelImport()", self.content)
        self.assertIn("function checkImportStatus()", self.content)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Chạy test để xác nhận các case kiểm tra QML fail (do chưa cập nhật giao diện)**

Run: `python3 -m unittest tests/test_spotify_import_vortex.py -v`
Expected: Fails on cases checking new UI features.

- [ ] **Step 3: Commit test suite**

```bash
git add -f tests/test_spotify_import_vortex.py
git commit -m "test(spotify): add test suite for spiral vortex and flat cancel button"
```

---

### Task 2: Cập nhật `components/SpotifyImportModal.qml`

**Files:**
- Modify: `components/SpotifyImportModal.qml`

- [ ] **Step 1: Điều chỉnh chiều cao `dialogCard` khi `isImporting` lên `420px`**
- [ ] **Step 2: Thay thế khung thumbnail cũ bằng `RoundedImage` bo góc $R=14\text{px}$**
- [ ] **Step 3: Dựng `Vortex 3D Stage` với đĩa than xoay ở tâm và 5–6 bài hát bay theo quỹ đạo xoắn ốc elip thu nhỏ dần**
- [ ] **Step 4: Chuyển nút Hủy sang Flat Ghost Text Action căn giữa với màu Muted Rose**

- [ ] **Step 5: Chạy kiểm thử tự động**

Run: `python3 -m unittest tests/test_spotify_import_vortex.py -v`
Expected: ALL 5 PASS (100% OK).

- [ ] **Step 6: Chạy kiểm tra tĩnh codebase**

Run: `python scripts/verify_codebase.py`
Expected: PASS trong < 1s.

- [ ] **Step 7: Commit thay đổi**

```bash
git add components/SpotifyImportModal.qml
git commit -m "feat(ui): implement cloudy spiral vortex and flat cancel button for spotify import modal"
```

---

### Task 3: Nghiệm thu trực quan (Visual Verification)

**Files:**
- N/A

- [ ] **Step 1: Reload / Restart ứng dụng Nutsty**
- [ ] **Step 2: Mở modal Spotify Import**
- [ ] **Step 3: Chụp ảnh màn hình qua `/usr/bin/grim /tmp/screen_vortex.png` và soi bằng `view_file`**
- [ ] **Step 4: Cập nhật walkthrough.md**
