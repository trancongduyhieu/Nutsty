# Liquid Glass Unification Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Upgrade `LiquidGlass.qml` to use the high-performance hardware-accelerated `MultiEffect` optical formula from `PlayerBarBottom` (48px Gaussian blur, 1.55x saturation vibrancy, 48% dark scrim) without spotlight, and eliminate opaque blocks in Download & Notification popovers with zero-lag resource guarantees.

**Architecture:** Replace the noisy GLSL shader in `components/LiquidGlass.qml` with a GPU-clipped `ShaderEffectSource` and `MultiEffect` pipeline that sleeps completely (`live: false`, `sourceItem: null`) when inactive. Remove the 90% opaque dark foundation in `DownloadQueuePopover.qml` and `FriendRequestsPopover.qml` so the real liquid glass transparency shines through.

**Tech Stack:** QML (Qt Quick 6), QtQuick.Effects (MultiEffect), ShaderEffectSource.

---

### Task 1: Refactor `components/LiquidGlass.qml` to PlayerBar Optical Pipeline with Zero-Lag Guards

**Files:**
- Modify: `components/LiquidGlass.qml`

**Step 1: Check existing `LiquidGlass.qml` structure and contracts**
Verify existing properties to ensure 100% backward compatibility:
- `backgroundSourceItem`, `radius`, `tintColor`, `interactive`, `contentData`, `isFlowActive`.

**Step 2: Implement hardware-accelerated `MultiEffect` pipeline**
Replace the GLSL shader and Timer with:
- `isEffectActive` boolean check (`root.visible && root.opacity > 0.01 && root.width > 0 && root.height > 0 && root.backgroundSourceItem !== null`).
- `cropAnchorHelper` mapping coordinates to `backgroundSourceItem`.
- `ShaderEffectSource` with `sourceRect` matching component bounds, `live: root.isEffectActive`, `recursive: false`, `smooth: true`.
- `capsuleMask` Rectangle for bo góc đồng tâm.
- `MultiEffect` with `blur: 1.0`, `blurMax: 48`, `saturation: 1.55`, `brightness: -0.05`, `maskEnabled: true`, `autoPaddingEnabled: false`.
- Adaptive dark scrim with `root.tintColor` (default `Qt.rgba(0.08, 0.09, 0.12, 0.48)`) and hairline border 1px.
- Optional `interactive` scale (`isPressed ? 1.02 : 1.0`) with `Easing.OutBack`.
- Strictly NO spotlight.

**Step 3: Verify codebase AST & syntax**
Run: `python scripts/verify_codebase.py`
Expected: ALL CHECKS PASSED.

**Step 4: Commit**
```bash
git add components/LiquidGlass.qml
git commit -m "feat(ui): upgrade LiquidGlass to PlayerBar MultiEffect optical pipeline with zero-lag guards"
```

---

### Task 2: Remove Opaque Obsidian Slab from `DownloadQueuePopover.qml`

**Files:**
- Modify: `components/DownloadQueuePopover.qml:68-75`

**Step 1: Locate and remove the opaque obsidian foundation**
Remove the `Rectangle { color: Qt.rgba(0.05, 0.06, 0.09, 0.90) }` behind `popoverGlass`.

**Step 2: Tune popover `LiquidGlass` properties**
Set `tintColor: Qt.rgba(0.08, 0.09, 0.12, 0.52)` and clean up redundant layered rectangle borders.

**Step 3: Verify codebase AST & syntax**
Run: `python scripts/verify_codebase.py`
Expected: ALL CHECKS PASSED.

**Step 4: Commit**
```bash
git add components/DownloadQueuePopover.qml
git commit -m "style(ui): unlock translucent liquid glass in DownloadQueuePopover"
```

---

### Task 3: Remove Opaque Obsidian Slab from `FriendRequestsPopover.qml` (Notifications)

**Files:**
- Modify: `components/FriendRequestsPopover.qml:92-98`

**Step 1: Locate and remove the opaque obsidian foundation**
Remove the `Rectangle { color: Qt.rgba(0.05, 0.06, 0.09, 0.90) }` behind `card`.

**Step 2: Tune popover `LiquidGlass` properties**
Set `tintColor: Qt.rgba(0.08, 0.09, 0.12, 0.52)` and ensure smooth 1px hairline concentric border.

**Step 3: Verify codebase AST & syntax**
Run: `python scripts/verify_codebase.py`
Expected: ALL CHECKS PASSED.

**Step 4: Commit**
```bash
git add components/FriendRequestsPopover.qml
git commit -m "style(ui): unlock translucent liquid glass in FriendRequestsPopover"
```

---

### Task 4: End-to-End Verification & Verification Script

**Files:**
- Test: `scripts/verify_codebase.py`

**Step 1: Run comprehensive verification**
Run: `python scripts/verify_codebase.py`
Expected: `0 errors, 0 warnings, all QML/JS contracts passed`.

**Step 2: Update task tracking**
Update `docs/plans/task.md` with the new completed tasks.
