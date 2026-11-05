# Design Document: Liquid Glass Unification & Performance Optimization

- **Date**: 2026-11-04
- **Status**: Approved (Brainstorming completed)
- **Topic**: Unify Liquid Glass effect across Notifications, Download Popover, and Modals using the `PlayerBarBottom` optical formula with strict zero-lag performance guarantees.

---

## 1. Problem Statement

1. **Inconsistent & Heavy Aesthetics**:
   - `PlayerBarBottom.qml` features a silky, vibrant Liquid Glass aesthetic powered by Qt Quick's hardware-accelerated `MultiEffect` (Gaussian blur 48px, saturation 1.55x, brightness -0.05, and 48% semi-transparent dark scrim).
   - In contrast, `components/LiquidGlass.qml` used a custom GLSL shader (`liquid_glass.frag.qsb`) with a 10 FPS running `Timer` that caused visual noise and lacked true depth blur.
   - To mask the lack of blur in `LiquidGlass.qml`, popovers like `DownloadQueuePopover.qml` and `FriendRequestsPopover.qml` wrapped themselves in a nearly pitch-black, opaque slab (`Qt.rgba(0.05, 0.06, 0.09, 0.90)`), destroying the translucent glass look and creating visual inconsistency.

2. **User Requirements**:
   - Apply the `PlayerBarBottom` glass effect to Notifications and Download popovers by upgrading the shared `LiquidGlass.qml` component.
   - **Exclusive Spotlight Rule**: Strictly NO spotlight glow in `LiquidGlass.qml`. The cursor-following radial spotlight remains an exclusive signature feature of `PlayerBarBottom.qml`.
   - **Performance & Zero-Lag Guarantee**: Must consume minimal resources, prevent frame drops, and guarantee zero idle GPU/CPU drain.

---

## 2. Goals & Non-Goals

### Goals
- Modernize `components/LiquidGlass.qml` with the proven `MultiEffect` hardware Gaussian blur formula from `PlayerBarBottom.qml`.
- Remove the opaque obsidian backgrounds (`0.90` opacity) in `DownloadQueuePopover.qml` and `FriendRequestsPopover.qml` so the real glass material shines through.
- Implement strict performance optimizations:
  - Zero idle rendering: Deactivate texture capture (`live: false`, `sourceItem: null`) when popovers/modals are hidden or closed (`opacity <= 0.01` or `!visible`).
  - Eliminate the continuous QML animation `Timer` from `LiquidGlass.qml`.
  - Tightly bounded source rect: Crop only the exact `[x, y, width, height]` bounds from `backgroundSourceItem`.
- Maintain 100% backward compatibility for all existing public properties (`backgroundSourceItem`, `radius`, `tintColor`, `contentData`, `interactive`).

### Non-Goals
- Do NOT bring the radial spotlight (`spotlightLayer` / `RadialGradient`) into `LiquidGlass.qml`.
- Do NOT alter the internal layout, buttons, or business logic of `DownloadQueuePopover.qml` or `FriendRequestsPopover.qml`.

---

## 3. Architecture & Technical Design

### A. Core Engine: `components/LiquidGlass.qml`

1. **Active State Detection**:
   ```qml
   readonly property bool isEffectActive: root.visible && root.opacity > 0.01 && root.width > 0 && root.height > 0 && root.backgroundSourceItem !== null
   ```

2. **Optimized Background Texture Crop**:
   ```qml
   Item {
       id: cropAnchorHelper
       property point cropPos: {
           if (!root.backgroundSourceItem || !root.isEffectActive) return Qt.point(root.x, root.y);
           var _dep = root.x + root.y + root.width + root.height + (root.parent ? (root.parent.width + root.parent.height) : 0);
           return root.mapToItem(root.backgroundSourceItem, 0, 0);
       }
   }

   ShaderEffectSource {
       id: backdropCropSource
       sourceItem: root.isEffectActive ? root.backgroundSourceItem : null
       sourceRect: Qt.rect(cropAnchorHelper.cropPos.x, cropAnchorHelper.cropPos.y, root.width, root.height)
       visible: false
       live: root.isEffectActive
       smooth: true
       recursive: false
       hideSource: false
   }
   ```

3. **MultiEffect Hardware Blur**:
   ```qml
   MultiEffect {
       anchors.fill: parent
       source: backdropCropSource
       blurEnabled: true
       blur: 1.0
       blurMax: 48
       saturation: 1.55
       brightness: -0.05
       maskEnabled: true
       maskSource: capsuleMask
       autoPaddingEnabled: false
       visible: root.isEffectActive
       z: 1
   }
   ```

4. **Adaptive Dark Scrim & Hairline Border**:
   ```qml
   Rectangle {
       anchors.fill: parent
       radius: root.radius
       color: root.tintColor
       border.color: root.borderColor
       border.width: 1
       z: 2
   }
   ```
   - Default `tintColor`: `Qt.rgba(0.08, 0.09, 0.12, 0.48)` (48% silky dark overlay).
   - Default `borderColor`: `Qt.rgba(1, 1, 1, 0.16)` or dynamic accent tint.

5. **Optional Interactive Spring Scale**:
   - When `interactive: true`, support subtle press feedback (`scale: pressed ? 1.02 : 1.0`) with `Easing.OutBack`.

### B. Popover Updates

1. **`components/DownloadQueuePopover.qml`**:
   - Remove line 68-73: Opaque `Rectangle { color: Qt.rgba(0.05, 0.06, 0.09, 0.90) }`.
   - Set `LiquidGlass` tint: `Qt.rgba(0.08, 0.09, 0.12, 0.52)` with hairline accent border.
2. **`components/FriendRequestsPopover.qml`**:
   - Remove line 92-97: Opaque `Rectangle { color: Qt.rgba(0.05, 0.06, 0.09, 0.90) }`.
   - Set `LiquidGlass` tint: `Qt.rgba(0.08, 0.09, 0.12, 0.52)` with hairline accent border.

---

## 4. Performance & Resource Verification Plan

1. **Zero Idle Overhead Verification**:
   - When popovers are closed (`isOpen === false`), ensure `ShaderEffectSource.live === false` and `sourceItem === null`.
   - No GPU texture copies occur during playback or background operations.
2. **Static Code & Contract Check**:
   - Run `python scripts/verify_codebase.py` to ensure AST and QML syntax compliance.
