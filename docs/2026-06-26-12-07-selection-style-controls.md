# Selection Style Controls Iteration

## Summary

Make selected annotations editable in place. A selected element should show a visible selection box with resize handles, and the user should be able to adjust size, line/text/arrow color, and stroke or arrow thickness.

This iteration should keep the app minimal. The goal is direct manipulation and a small fixed style palette, not a full inspector.

## Product Behavior Target

- Selecting an annotation shows an editing box around it.
- Rectangle, ellipse, text, and blur selections can be resized by dragging handles.
- Arrow selections can be edited by dragging endpoint handles:
  - tail handle changes arrow start point
  - head handle changes arrow end point
  - dragging the arrow body moves the whole arrow
- Selected annotations can still be moved by dragging inside or near the annotation.
- Selected shape/arrow line thickness can be changed.
- Selected text size or text styling can be considered only if needed; the required scope is color.
- Selected annotation color can be changed using a fixed seven-color palette.
- Color palette should contain soft:
  - red
  - blue
  - green
  - orange
  - yellow
  - white
  - black
- Palette values must be defined as convenient code constants so the colors can be changed later in one place.

## Architecture Changes

Selection geometry:

- Introduce a small selection model for hit-testing resize handles.
- Define handle positions in image coordinates.
- Convert handle hit-testing through the existing `ViewportTransform` so behavior remains correct at all zoom levels.
- Keep transient resize state separate from committed annotation state.
- Record undo snapshots when a resize, move, color change, or thickness change begins.

Suggested handle model:

```swift
enum SelectionHandle {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case arrowStart
    case arrowEnd
}
```

Style model:

- Add a centralized palette, for example:

```swift
public enum CapturePalette {
    public static let softRed: NSColor = ...
    public static let softBlue: NSColor = ...
}
```

- Prefer a compact array for toolbar/menu generation:

```swift
public struct CaptureColor: Equatable {
    public let name: String
    public let color: NSColor
}
```

- Keep defaults aligned with the current app:
  - arrow default uses soft red
  - rectangle/ellipse default uses soft red
  - text default uses soft red
- Add a simple way to apply style to the selected annotation.
- Avoid a complex inspector panel; prefer toolbar buttons, segmented controls, or a small popover if needed.

Annotation model:

- Ensure each styleable annotation exposes:
  - editable color
  - editable thickness where applicable
- Rectangle and ellipse use stroke color and stroke width.
- Arrow uses filled arrow color and thickness/shaft scale.
- Text uses text color.
- Blur may ignore color/thickness unless a future visible blur boundary is added.

## UX Acceptance Criteria

- Clicking an annotation selects it and shows a clear selection box.
- Rectangle and ellipse can be resized from handles.
- Text boxes can be resized from handles.
- Blur regions can be resized from handles.
- Arrow start and end can be adjusted from endpoint handles.
- Dragging the body of a selected annotation moves it.
- Applying a color changes the selected annotation immediately.
- Applying thickness changes rectangle, ellipse, and arrow appearance immediately.
- Undo reverses resize, move, color, and thickness changes.
- Redo reapplies them.
- Zoom in/out does not break selection handles or resizing.
- Copy/export output matches the visible styled canvas.

## Automated Test Plan

- Unit test selection handle geometry for rectangles.
- Unit test arrow endpoint handle hit-testing.
- Unit test resizing a rectangle updates bounds predictably.
- Unit test resizing an arrow endpoint updates start/end predictably.
- Unit test color application changes the correct annotation property.
- Unit test thickness application changes rectangle/ellipse/arrow thickness.
- Unit test undo/redo works for style and resize changes.
- Keep existing export, crop, blur, text, arrow, undo/redo, and zoom tests passing.

## Manual Verification Plan

- Run:

```shell
xcrun xcodebuild -project SkitchEquivalent.xcodeproj -scheme SkitchEquivalent -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

- Launch `Capture.app`.
- Open or paste a screenshot.
- Create rectangle, ellipse, text, blur, and arrow annotations.
- Select each annotation and confirm handles appear.
- Resize rectangle, ellipse, text, and blur.
- Change arrow direction by dragging head and tail handles.
- Move selected annotations by dragging their body.
- Change color for text, arrow, rectangle, and ellipse using all seven palette colors.
- Change thickness for arrow, rectangle, and ellipse.
- Undo/redo resize, color, and thickness edits.
- Zoom in/out and confirm selection handles still work.
- Copy/export and verify output matches the visible canvas.
- Capture a verification screenshot under `artifacts/verification/`.

## Assumptions and Non-Goals

- The app remains native AppKit and light-mode.
- No full inspector sidebar is added.
- No arbitrary color picker is added.
- No custom per-object style persistence beyond in-memory annotations is added.
- Blur does not need color or thickness styling in this iteration.
- Selection handles should be functional and clear; they do not need to perfectly mimic Skitch visuals yet.
