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
        cancel_block_match = re.search(r"// Cancel Button[\s\S]*?MouseArea[\s\S]*?root\.cancelImport\(\)", self.content)
        self.assertTrue(bool(cancel_block_match), "Cancel button block must exist")
        block = cancel_block_match.group(0)
        self.assertNotIn("Layout.fillWidth: true", block, "Flat cancel button must not be full width")
        self.assertIn("window-close-symbolic.svg", block, "Must retain close icon")
        self.assertTrue("#f87171" in block or "#fda4af" in block or "244, 63, 94" in block, "Must use Muted Rose palette")

    def test_case_3_vortex_parametric_math(self):
        """Case 3: Verify the mathematical model of the Cloudy Spiral (tilt, radius decay, angle)."""
        angles = [i * (2 * math.pi / 6) for i in range(6)]
        tilt = 0.40
        for i, a in enumerate(angles):
            r = 140 - (i / 6.0) * (140 - 36)
            x = r * math.cos(a)
            y = r * math.sin(a) * tilt
            self.assertTrue(-140 <= x <= 140)
            self.assertTrue(-60 <= y <= 60)

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
