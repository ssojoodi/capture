# Capture Next Iteration Plan

## Summary

Improve the current `Capture` app by making the implemented annotation tools reliable, bringing the interaction model closer to Skitch, and adding practical zoom controls.

This iteration should not expand the feature set beyond the existing v1 scope. The goal is to make the current tools feel correct, fast, and obvious.

## Key Changes

- Fix annotation correctness across the existing tools:
  - Verify arrow, text, blur, crop, rectangle, and ellipse creation on real images.
  - Fix blur rendering so blurred regions visibly affect the exported/copied image and the live canvas preview.
  - Ensure crop affects export/copy dimensions and visual preview predictably.
  - Ensure hit-testing, selection, movement, and deletion work for each editable annotation type.
- Bring tool UX closer to Skitch:
  - Selecting a region-based tool should immediately put the canvas into region-selection mode.
  - For blur, rectangle, ellipse, and crop, the pointer should communicate rectangular selection before the user clicks/drags.
  - While dragging, show a live selection rectangle or shape preview with Skitch-like immediacy.
  - After creating an annotation, keep behavior intentionally fast: either return to select mode or stay on the active tool consistently, with the chosen behavior documented in code comments/tests.
  - Text should be quick to create and edit, with a minimal inline or near-inline editing flow rather than a heavy modal if feasible.
- Add zoom in/out:
  - Add toolbar controls and keyboard shortcuts for zoom in, zoom out, and zoom to fit.
  - Use centered zoom behavior that preserves the visible image focus where practical.
  - Keep annotation coordinates in image space so zoom does not affect export fidelity.
  - Ensure drag creation, hit-testing, crop, and movement still work correctly at non-100% zoom.

## UX Acceptance Criteria

- A user can open or paste an image, select Blur, drag a rectangle, and immediately see the selected area blurred.
- Blur appears in both the live canvas and flattened export/copy output.
- Region tools feel like region tools as soon as they are selected; the cursor/preview should not feel like ordinary selection mode.
- Arrows draw from start to end with a visible arrowhead and remain movable/deletable.
- Rectangles and ellipses draw with visible red outlines and remain movable/deletable.
- Text can be added, edited, moved, deleted, and exported.
- Crop can be set, previewed, and reflected in export/copy output.
- Zoom in, zoom out, and zoom to fit work from both toolbar and keyboard shortcuts.
- All annotation interactions remain correct after zooming.

## Test Plan

Automated tests:

- Add or update rendering tests proving blur changes pixels inside the blur rect while preserving output dimensions.
- Test crop clamping and flattened export dimensions at multiple crop rectangles.
- Test coordinate conversion for zoomed hit-testing and drag creation logic where it can be isolated outside `NSView`.
- Test annotation ordering and deletion behavior after creating multiple annotations.

Manual verification:

- Run `xcrun xcodebuild -project SkitchEquivalent.xcodeproj -scheme SkitchEquivalent -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test`.
- Launch the built `Capture.app`.
- Open or paste a real screenshot and manually exercise every tool.
- Capture a screenshot showing the light-mode app with an image containing arrow, text, blur, rectangle, ellipse, and crop/zoom evidence.
- Export a JPG and verify the result opens and includes the expected annotations.
- Copy the flattened image and paste it into another app to verify clipboard output.

## Assumptions

- The app remains native AppKit with a custom canvas.
- The app remains light-mode and minimal.
- No screenshot-capture feature is added in this iteration.
- No editable project file format is added in this iteration.
- Existing source/module names may remain `SkitchEquivalent` internally; user-facing product name remains `Capture`.
