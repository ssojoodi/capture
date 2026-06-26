# Capture Minimal Native macOS Annotator Plan

## Summary

Build Capture, a fast, minimal macOS app focused on opening or pasting an image, annotating it, then exporting a flattened JPG or copying the result to the clipboard.

Chosen defaults:

- Native macOS app named `Capture` using Swift + AppKit.
- Elegant forced light-mode visual design with a native toolbar and warm canvas.
- Custom `NSView` canvas for low-latency drawing and hit-testing.
- Input via open file, drag/drop, and clipboard paste.
- No screenshot capture in v1.
- No editable project files in v1; export/copy only.

## Core Architecture

- Use an AppKit single-window app with three main areas: top toolbar, central canvas, lightweight inspector/status area if needed.
- Represent the loaded image as an immutable base image plus an ordered list of annotation objects.
- Render annotations live on an `NSView` canvas using Core Graphics/AppKit drawing.
- On export/copy, flatten the base image plus annotations into a single bitmap.
- Keep all editing in memory; closing the window discards unsaved annotations after confirmation if needed.

Core model shape:

```swift
enum Tool {
    case arrow
    case text
    case blur
    case crop
    case rectangle
    case ellipse
    case select
}

protocol Annotation {
    var id: UUID { get }
    var bounds: CGRect { get set }
    func draw(in context: CGContext, scale: CGFloat)
    func hitTest(_ point: CGPoint) -> Bool
}
```

Concrete annotations:

- `ArrowAnnotation`: start point, end point, stroke width, color.
- `TextAnnotation`: rect, string, font size, color.
- `BlurAnnotation`: rect, blur radius.
- `RectangleAnnotation`: rect, stroke/fill style.
- `EllipseAnnotation`: rect, stroke/fill style.

Crop is not stored as a normal annotation; it updates the active image/canvas crop rect before export.

## Key Implementation Changes

- Create an AppKit app with a custom `AnnotationCanvasView`.
- Add an `AnnotationDocumentState` object holding:
  - base image
  - image pixel size
  - zoom/pan state
  - selected tool
  - selected annotation
  - annotations array
  - optional crop rect
- Implement mouse handling directly in the canvas:
  - click-drag to create arrows, shapes, blur regions, and crop regions
  - click to select existing annotations
  - drag selected annotations to move them
  - double-click text annotation to edit
- Add a small toolbar:
  - open image
  - paste image
  - select
  - arrow
  - text
  - blur
  - crop
  - rectangle
  - ellipse
  - copy
  - export JPG
- Use simple fixed styling defaults:
  - red arrows and outlines
  - white text with red background or red text depending on readability
  - medium blur radius
  - no complex style inspector in v1
- Implement keyboard shortcuts:
  - `Cmd+O`: open
  - `Cmd+V`: paste image
  - `Cmd+C`: copy flattened image
  - `Cmd+E`: export JPG
  - `Delete`: delete selected annotation
  - `Esc`: return to select tool
- Export JPG through `NSBitmapImageRep` with a default quality around `0.9`.
- Copy flattened image to `NSPasteboard` as PNG/TIFF-compatible image data for broad macOS app compatibility.

## Performance Design

- Avoid SwiftUI for the drawing surface; use AppKit/Core Graphics directly.
- Keep annotations vector-based until final export.
- Redraw only the visible canvas when editing.
- Cache expensive blur output per blur annotation and invalidate only when its rect changes.
- Keep image decoding once per opened/pasted image.
- Avoid layers of document abstraction, persistence, sync, or database storage.

## Test Plan

Manual acceptance scenarios:

- Open a JPG or PNG and see it fit the window.
- Paste an image from clipboard and annotate it.
- Draw an arrow, rectangle, ellipse, blur region, and text label.
- Select, move, and delete annotations.
- Crop the image and confirm export uses the cropped area.
- Copy the flattened result and paste into Preview, Messages, Slack, or another image target.
- Export JPG and verify the file opens correctly.
- Confirm large screenshots remain responsive during basic annotation.

Lightweight automated tests:

- Unit test annotation hit-testing.
- Unit test flattened export dimensions with and without crop.
- Unit test annotation ordering.
- Unit test crop rect clamping to image bounds.

## Assumptions

- v1 does not include screenshot capture.
- v1 does not save editable project files.
- v1 targets recent macOS versions using Swift and AppKit.
- Styling is intentionally minimal and opinionated rather than customizable.
- Export format requirement is JPG, while clipboard copy may use a richer pasteboard image representation for compatibility.
