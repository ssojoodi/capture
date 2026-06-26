# WYSIWYG Undo Redo Iteration

## Summary

Bring Capture closer to Skitch by making tool operations take effect immediately on mouse-up instead of appearing as construction rectangles or deferred export-only effects. Add undo and redo so immediate edits remain safe.

The core behavior target is WYSIWYG: the canvas should show the actual result as soon as the user completes a drag or text edit.

## Product Behavior Target

- Shape tools should show only a transient drag preview while dragging.
- On mouse-up, rectangle and ellipse edits become committed visible annotations; the dotted or construction selection rectangle disappears.
- Blur should visibly affect the image immediately after the blur drag completes.
- Crop should crop the visible working image immediately after the crop drag completes.
- Copy and export should flatten what the user already sees, not apply hidden deferred edits for the first time.
- Undo should reverse the last committed edit.
- Redo should restore the last undone edit.

## Architecture Changes

Introduce an explicit edit history model.

Recommended model:

```swift
struct DocumentSnapshot {
    var baseImage: NSImage
    var operations: [CommittedOperation]
    var cropRect: CGRect?
}

enum CommittedOperation {
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)
    case blur(BlurOperation)
    case rectangle(RectangleAnnotation)
    case ellipse(EllipseAnnotation)
}
```

Expected direction:

- Keep mouse drag state separate from committed document state.
- Treat drag rectangles as transient canvas previews only.
- Commit an operation on mouse-up if the drag exceeds a minimum size.
- Render committed operations on the live canvas, not only during export.
- Store undo/redo stacks as snapshots or inverse commands, choosing the simplest reliable implementation.
- Clear redo when a new operation is committed after undo.
- Keep zoom state outside undo/redo history.
- Consider crop a committed document operation because it changes the visible working image.

Implementation bias:

- Prefer snapshot-based undo/redo first if it is simpler and reliable for screenshots.
- Keep history depth bounded if memory becomes a concern, for example 50 states.
- Avoid introducing a project file format.

## Tool-Specific Behavior

Arrow:

- Drag from tail to head.
- Show transient arrow preview during drag.
- Commit visible arrow on mouse-up.
- Remove construction bounds after commit.

Text:

- Click or drag to create text.
- Enter inline edit mode immediately.
- Commit text when editing ends.
- Undo should remove the committed text or revert the text edit, depending on implementation scope.

Blur:

- Selecting Blur should put the pointer into region-selection mode.
- Dragging shows a transient region preview.
- Mouse-up commits the blur effect visibly on the canvas.
- Copy/export should match the visible blurred result.

Crop:

- Selecting Crop should put the pointer into crop-region mode.
- Dragging shows a transient crop rectangle.
- Mouse-up crops the visible image/canvas immediately.
- Undo restores the pre-crop visible image/state.

Rectangle and ellipse:

- Dragging shows the shape preview.
- Mouse-up commits the shape itself.
- No persistent dotted rectangle should remain unless the object is actively selected for movement/editing.

## UX Acceptance Criteria

- After drawing a rectangle, only the rectangle remains visible.
- After drawing an ellipse, only the ellipse remains visible.
- After applying blur, the blurred pixels are visible before copy/export.
- After cropping, the canvas dimensions and visible image update immediately.
- Undo reverses arrow, text, blur, crop, rectangle, and ellipse commits.
- Redo reapplies an undone commit.
- Creating a new edit after undo clears redo.
- Zoom remains visual-only and should not be affected by undo/redo.
- Copy/export output matches the live visible canvas.

## Automated Test Plan

- Test undo removes the most recent committed operation.
- Test redo restores an undone operation.
- Test new edit after undo clears redo.
- Test crop changes flattened/live output dimensions immediately.
- Test blur changes pixels in the live/flattened result immediately after commit.
- Test zoom transform remains separate from document history.

## Manual Verification Plan

- Run:

```shell
xcrun xcodebuild -project SkitchEquivalent.xcodeproj -scheme SkitchEquivalent -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

- Launch `Capture.app`.
- Open or paste a real screenshot.
- Draw arrow, text, blur, crop, rectangle, and ellipse.
- Confirm each tool commits on mouse-up or edit completion and no construction rectangle remains.
- Use undo repeatedly until the original image is restored.
- Use redo repeatedly until all edits are restored.
- Apply a new edit after undo and confirm redo is cleared.
- Copy the image and paste it elsewhere.
- Export JPG and verify it matches the visible canvas.
- Capture a verification screenshot in `artifacts/verification/`.

## Assumptions and Non-Goals

- The app remains native AppKit.
- The app remains light-mode.
- No style inspector is added.
- No project file persistence is added.
- No screenshot capture feature is added.
- Selection and movement can remain minimal as long as committed visual output and undo/redo work correctly.
