# Text Arrow Style Iteration

## Summary

Refine Capture's annotation styling so the Text tool defaults to transparent text and arrows look closer to Skitch: elegant, bold, tapered, and immediately readable.

This iteration is intentionally visual and focused. It should not add a full style inspector.

## Product Behavior Target

- Text annotations should have no background by default.
- Text should remain readable and elegant on common screenshots.
- The app should still support text backgrounds as an option, but transparent should be the default.
- Arrows should look more like Skitch arrows:
  - tapered shaft
  - rounded tail
  - large triangular arrowhead
  - single filled shape rather than a simple stroked line plus separate head
  - vivid pink/red default color
- Existing copy/export output should match the live canvas styling.

## Architecture Changes

Text:

- Change `TextAnnotation` defaults so `backgroundColor` is transparent by default.
- Add an explicit way to represent whether a text annotation draws a background.
- Keep the current simple text model; avoid a full inspector.
- If adding background toggling in this iteration, prefer a minimal keyboard/menu/toolbar action over a style panel.

Arrow:

- Replace the current stroked-line arrow rendering with a filled geometric arrow path.
- Build the arrow from image-space start/end points:
  - compute direction and perpendicular vectors
  - use a narrow rounded/tapered tail
  - widen into a large head near the end point
  - keep a minimum length threshold for tiny drags
- Keep hit-testing practical by continuing to use distance-to-segment or a widened path test.
- Preserve fast rendering with Core Graphics only.

## UX Acceptance Criteria

- New text annotations render without a colored rectangle by default.
- Existing text still draws correctly.
- There is still a practical path to create text with a background if implemented in this slice.
- New arrows visually resemble the attached Skitch-style arrow:
  - filled vivid pink/red
  - tapered body
  - broad triangular head
  - rounded tail
- Arrow previews while dragging use the same visual style as committed arrows.
- Exported JPG and clipboard copy match the live canvas.
- Undo/redo still works for text and arrow creation.

## Automated Test Plan

- Test `TextAnnotation` defaults to transparent/no-background behavior.
- Test text rendering still changes pixels when drawn.
- Test arrow hit-testing still includes points near the shaft and excludes far points.
- If arrow geometry is factored into a helper, test generated path bounds for vertical and diagonal arrows.
- Keep existing undo/redo, blur, crop, and zoom tests passing.

## Manual Verification Plan

- Run:

```shell
xcrun xcodebuild -project SkitchEquivalent.xcodeproj -scheme SkitchEquivalent -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

- Launch `Capture.app`.
- Open or paste a screenshot.
- Add text and confirm it has no background by default.
- If a background toggle exists, enable it and confirm background text still works.
- Draw multiple arrows:
  - vertical arrow
  - diagonal arrow
  - short arrow near the minimum usable length
- Confirm arrow preview and committed arrow match.
- Undo/redo text and arrow edits.
- Copy/export and verify output matches the visible canvas.
- Capture a verification screenshot under `artifacts/verification/`.

## Assumptions and Non-Goals

- The app remains native AppKit and light-mode.
- No full style inspector is added.
- No color picker is required unless explicitly requested later.
- No editable project file format is added.
- The attached arrow image is a style reference, not a pixel-perfect asset to embed.
