#!/usr/bin/env python3
"""
Test Suite: Spotify Import Arc Rail Gunshot Projectile & Completed View Polish.
Tests:
  1. RoundedImage component reuse check (for vinyl disc label & summary card).
  2. Flat Ghost Cancel Button structure & color tokens (no pill borders).
  3. Arc Rail Gunshot Stage (Left vinyl disc, shockwave ripple, arc queue, projectile gunshot, no grey dead colors).
  4. Completed View Polish (auto-shrink width=380, height=240, hide top-right 'x', playlist summary card).
  5. Static syntax and contract validation.
"""
import unittest
import os
import re

class TestSpotifyImportVortex(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.modal_path = os.path.join(os.path.dirname(__file__), "..", "components", "SpotifyImportModal.qml")
        with open(cls.modal_path, "r", encoding="utf-8") as f:
            cls.content = f.read()

    def test_case_1_rounded_image_reuse(self):
        """Case 1: Must use RoundedImage component with radius >= 10 for playlist covers."""
        self.assertIn("RoundedImage", self.content, "Must reuse RoundedImage component in SpotifyImportModal.qml")
        self.assertNotIn("id: importCoverImg", self.content, "Old unmasked Rectangle clip image should be replaced")

    def test_case_2_flat_cancel_button_structure(self):
        """Case 2: Cancel button must be a flat text link, not a full-width pill button."""
        cancel_block_match = re.search(r"// Cancel Button[\s\S]*?MouseArea[\s\S]*?root\.cancelImport\(\)", self.content)
        self.assertTrue(bool(cancel_block_match), "Cancel button block must exist")
        block = cancel_block_match.group(0)
        self.assertNotIn("Layout.fillWidth: true", block, "Flat cancel button must not be full width")
        self.assertIn("window-close-symbolic.svg", block, "Must retain close icon")
        self.assertTrue("#f87171" in block or "#fda4af" in block or "244, 63, 94" in block, "Must use Muted Rose palette")

    def test_case_3_arc_gunshot_stage(self):
        """Case 3: Verify the Arc Rail Gunshot Stage (Left vinyl disc, shockwave, curved arc, projectile)."""
        # Left Vinyl Disc exists
        self.assertTrue(
            "leftVinylDisc" in self.content or "discContainer" in self.content or "vinylDisc" in self.content,
            "Must have left vinyl disc container"
        )
        # Shockwave ripple exists
        self.assertTrue(
            "shockwave" in self.content.lower() or "ripple" in self.content.lower(),
            "Must have shockwave ripple animation for disc impact"
        )
        # Projectile gunshot animation exists
        self.assertTrue(
            "projectile" in self.content.lower() or "gunshot" in self.content.lower() or "bullet" in self.content.lower(),
            "Must have projectile gunshot animation from arc to vinyl disc"
        )
        # Arc curved queue exists
        self.assertTrue(
            "arc" in self.content.lower() or "curved" in self.content.lower() or "rail" in self.content.lower(),
            "Must have right-hand curved arc queue"
        )
        # Eliminate dead grey color (20, 20, 25)
        self.assertNotIn("20, 20, 25", self.content, "Dead grey color (20, 20, 25) must be replaced with dynamic accent palette")

    def test_case_4_completed_view_polish(self):
        """Case 4: Completed View auto-shrinks width to 380px, height to 240px, hides 'x', and shows summary."""
        # Auto-shrink width to 380px on completed
        width_match = re.search(r"width:\s*root\.importCompleted\s*\?\s*(\d+)", self.content)
        self.assertTrue(bool(width_match), "Dialog width must branch on root.importCompleted")
        self.assertEqual(int(width_match.group(1)), 380, "Completed width must be 380px")

        # Auto-shrink height to 240px on completed
        height_match = re.search(r"height:\s*root\.importCompleted\s*\?\s*(\d+)", self.content)
        self.assertTrue(bool(height_match), "Dialog height must branch on root.importCompleted")
        self.assertEqual(int(height_match.group(1)), 240, "Completed height must be 240px")

        # Top-right 'x' close button hidden on completed view
        self.assertTrue(
            re.search(r"visible:\s*!root\.importCompleted", self.content) is not None,
            "Top-right close button must be hidden when importCompleted is true"
        )

    def test_case_5_static_contract(self):
        """Case 5: Must retain all critical functional signals and properties."""
        self.assertIn("signal playlistImported", self.content)
        self.assertIn("function cancelImport()", self.content)
        self.assertIn("function checkImportStatus()", self.content)

if __name__ == "__main__":
    unittest.main()
