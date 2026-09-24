import AppKit
import XCTest
@testable import CaptureCore

final class AnnotationCoreTests: XCTestCase {
    func testArrowHitTestingIncludesLineAndExcludesFarPoint() {
        let arrow = ArrowAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 10), strokeWidth: 6)
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 12)))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 50, y: 60)))
    }

    func testTextAnnotationDefaultsToHalfOpacityBlackBackground() {
        let text = TextAnnotation(bounds: CGRect(x: 10, y: 10, width: 120, height: 48))
        XCTAssertTrue(text.drawsBackground)
        XCTAssertEqual(text.backgroundColor.usingColorSpace(.sRGB), NSColor.black.withAlphaComponent(0.5).usingColorSpace(.sRGB))
        XCTAssertEqual(text.textColor.usingColorSpace(.sRGB), CapturePalette.softRed.usingColorSpace(.sRGB))
    }

    func testTextRenderingStillChangesPixelsWithoutBackground() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 220, height: 120, color: .white))
        state.addAnnotation(TextAnnotation(bounds: CGRect(x: 20, y: 24, width: 180, height: 70), text: "A", fontSize: 54, drawsBackground: false))
        let flattened = try XCTUnwrap(state.flattenedImage())
        XCTAssertGreaterThan(flattened.countNonWhitePixels(), 20)
        let corner = try XCTUnwrap(flattened.sampleColor(x: 22, y: 26))
        XCTAssertEqual(corner.brightnessComponent, 1, accuracy: 0.001)
    }

    func testTextBackgroundChangesAreUndoableAndDoNotChangeForeground() throws {
        let state = AnnotationDocumentState()
        let text = TextAnnotation(bounds: CGRect(x: 10, y: 10, width: 120, height: 48))
        state.addAnnotation(text)
        let originalRevision = state.revisionID
        XCTAssertFalse(state.applyTextBackgroundToSelected(text.backgroundColor))
        XCTAssertEqual(state.revisionID, originalRevision)
        let blue = CapturePalette.softBlue.withAlphaComponent(0.75)
        XCTAssertTrue(state.applyTextBackgroundToSelected(blue))
        XCTAssertEqual(text.textColor, CapturePalette.softRed)
        XCTAssertTrue(state.undo())
        let restored = try XCTUnwrap(state.annotation(with: text.id) as? TextAnnotation)
        XCTAssertEqual(restored.backgroundColor.usingColorSpace(.sRGB), NSColor.black.withAlphaComponent(0.5).usingColorSpace(.sRGB))
        XCTAssertTrue(state.redo())
        XCTAssertEqual((state.annotation(with: text.id) as? TextAnnotation)?.backgroundColor, blue)
        XCTAssertTrue(state.applyTextBackgroundToSelected(blue.withAlphaComponent(0)))
        XCTAssertFalse((state.annotation(with: text.id) as! TextAnnotation).drawsBackground)
        XCTAssertTrue(state.undo())
        XCTAssertTrue((state.annotation(with: text.id) as! TextAnnotation).drawsBackground)
        XCTAssertEqual((state.annotation(with: text.id) as? TextAnnotation)?.backgroundColor, blue)
    }

    func testTextBackgroundDoesNotChangeOtherAnnotations() {
        let state = AnnotationDocumentState()
        let rectangle = RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 120, height: 48))
        state.addAnnotation(rectangle)
        let revision = state.revisionID
        XCTAssertFalse(state.applyTextBackgroundToSelected(.white))
        XCTAssertEqual(state.revisionID, revision)
        state.selectedAnnotationID = nil
        XCTAssertFalse(state.applyTextBackgroundToSelected(.black))
        XCTAssertEqual(state.revisionID, revision)
    }

    func testTextBackgroundOpacityCompositesIntoFlattenedImage() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 100, height: 100, color: .white))
        state.addAnnotation(TextAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 80), text: ""))
        for opacity: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            state.applyTextBackgroundToSelected(NSColor.black.withAlphaComponent(opacity))
            let flattened = try XCTUnwrap(state.flattenedImage())
            // Read the renderer's sRGB samples directly, avoiding colorAt's colour-space conversion.
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(flattened.cgImageForRendering()))
            var pixel = [UInt](repeating: 0, count: 4)
            bitmap.getPixel(&pixel, atX: 50, y: 50)
            for channel in pixel.prefix(3) {
                XCTAssertEqual(CGFloat(channel) / 255, 1 - opacity, accuracy: 0.01)
            }
            XCTAssertEqual(pixel[3], 255)
        }
    }

    func testSelectionHandleGeometryForRectangle() {
        let rectangle = RectangleAnnotation(bounds: CGRect(x: 20, y: 30, width: 100, height: 80))
        let handles = Dictionary(uniqueKeysWithValues: AnnotationSelectionGeometry.handleCenters(for: rectangle))
        XCTAssertEqual(handles[.topLeft], CGPoint(x: 20, y: 110))
        XCTAssertEqual(handles[.right], CGPoint(x: 120, y: 70))
        XCTAssertEqual(AnnotationSelectionGeometry.hitHandle(at: CGPoint(x: 121, y: 69), annotation: rectangle, hitRadius: 5), .right)
    }

    func testFittingTextBoundsPreservesSizeAndKeepsAllEdgesInsideImage() {
        let image = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(CGRect(x: 190, y: 95, width: 120, height: 60).fitted(inside: image),
                       CGRect(x: 80, y: 40, width: 120, height: 60))
        XCTAssertEqual(CGRect(x: -20, y: -30, width: 120, height: 60).fitted(inside: image),
                       CGRect(x: 0, y: 0, width: 120, height: 60))
        XCTAssertEqual(CGRect(x: 150, y: 50, width: 400, height: 200).fitted(inside: image), image)
    }

    func testArrowEndpointHandleHitTesting() {
        let arrow = ArrowAnnotation(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 100, y: 140))
        XCTAssertEqual(AnnotationSelectionGeometry.hitHandle(at: CGPoint(x: 12, y: 22), annotation: arrow, hitRadius: 6), .arrowStart)
        XCTAssertEqual(AnnotationSelectionGeometry.hitHandle(at: CGPoint(x: 98, y: 138), annotation: arrow, hitRadius: 6), .arrowEnd)
        XCTAssertNil(AnnotationSelectionGeometry.hitHandle(at: CGPoint(x: 50, y: 50), annotation: arrow, hitRadius: 6))
    }

    func testResizingRectangleHandleUpdatesBoundsPredictably() {
        let rect = CGRect(x: 20, y: 30, width: 100, height: 80)
        let resized = AnnotationSelectionGeometry.resizedRect(rect, moving: .bottomRight, to: CGPoint(x: 150, y: 10))
        XCTAssertEqual(resized, CGRect(x: 20, y: 10, width: 130, height: 100))
    }

    func testStateCanResizeArrowEndpointAndUndoIt() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        let arrow = ArrowAnnotation(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 100, y: 100))
        state.addAnnotation(arrow)
        XCTAssertTrue(state.resizeSelected(handle: .arrowEnd, to: CGPoint(x: 160, y: 80)))
        XCTAssertEqual(arrow.end, CGPoint(x: 160, y: 80))
        XCTAssertTrue(state.undo())
        let restored = state.annotations.first as? ArrowAnnotation
        XCTAssertEqual(restored?.end, CGPoint(x: 100, y: 100))
    }

    func testColorAndThicknessApplyToSelectedAnnotationAndUndo() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        let rectangle = RectangleAnnotation(bounds: CGRect(x: 20, y: 30, width: 100, height: 80))
        state.addAnnotation(rectangle)
        XCTAssertTrue(state.applyColorToSelected(CapturePalette.softBlue))
        XCTAssertEqual(rectangle.strokeColor.usingColorSpace(.sRGB), CapturePalette.softBlue.usingColorSpace(.sRGB))
        XCTAssertTrue(state.applyThicknessToSelected(14))
        XCTAssertEqual(rectangle.strokeWidth, 14)
        XCTAssertTrue(state.undo())
        XCTAssertEqual(rectangle.strokeWidth, 14)
        XCTAssertEqual((state.annotations.first as? RectangleAnnotation)?.strokeWidth, 6)
    }

    func testApplyingSameStyleDoesNotCreateUndoEntry() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 20, y: 30, width: 100, height: 80)))

        XCTAssertFalse(state.applyColorToSelected(CapturePalette.softRed))
        XCTAssertFalse(state.applyThicknessToSelected(6))
        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.annotations.count, 0)
    }

    func testPaletteContainsSevenSoftColors() {
        XCTAssertEqual(CapturePalette.all.map(\.name), ["Red", "Blue", "Green", "Orange", "Yellow", "White", "Black"])
    }

    func testAnnotationOrderingReturnsTopmostHit() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        let bottom = RectangleAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 120))
        let top = BlurAnnotation(bounds: CGRect(x: 30, y: 30, width: 80, height: 80))
        state.addAnnotation(bottom)
        state.addAnnotation(top)
        XCTAssertEqual(state.annotation(at: CGPoint(x: 50, y: 50))?.id, top.id)
    }

    func testDeleteSelectedAnnotationRevealsLowerAnnotation() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        let bottom = RectangleAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 120))
        let top = BlurAnnotation(bounds: CGRect(x: 30, y: 30, width: 80, height: 80))
        state.addAnnotation(bottom)
        state.addAnnotation(top)
        state.deleteSelectedAnnotation()
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotation(at: CGPoint(x: 25, y: 25))?.id, bottom.id)
    }

    func testCropRectIsClampedToImageBounds() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 300, height: 200, color: .white))
        state.setCropRect(CGRect(x: -50, y: 20, width: 500, height: 300))
        XCTAssertEqual(state.cropRect, CGRect(x: 0, y: 20, width: 300, height: 180))
    }

    func testFlattenedExportUsesCropDimensions() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 300, height: 200, color: .white))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 60)))
        state.setCropRect(CGRect(x: 10, y: 20, width: 120, height: 90))
        let flattened = try XCTUnwrap(state.flattenedImage())
        XCTAssertEqual(flattened.size, NSSize(width: 120, height: 90))
        XCTAssertNotNil(state.jpegData())
    }

    func testFlattenedExportUsesDifferentCropDimensions() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 240, height: 180, color: .white))
        state.setCropRect(CGRect(x: 40, y: 30, width: 90, height: 70))
        let flattened = try XCTUnwrap(state.flattenedImage())
        XCTAssertEqual(flattened.size, NSSize(width: 90, height: 70))
    }

    func testPNGEncodingPreservesImageDimensionsAndTransparency() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 80, height: 60, color: .clear))

        let data = try XCTUnwrap(state.imageData(format: .png))
        let decoded = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(decoded.size, NSSize(width: 80, height: 60))
        XCTAssertEqual(try XCTUnwrap(decoded.sampleColor(x: 40, y: 30)).alphaComponent, 0, accuracy: 0.001)
    }

    func testJPEGEncodingProducesDecodableFlattenedImage() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 96, height: 64, color: .systemBlue))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 30, height: 20)))

        let data = try XCTUnwrap(state.imageData(format: .jpeg))
        let decoded = try XCTUnwrap(NSImage(data: data))
        XCTAssertEqual(decoded.size, NSSize(width: 96, height: 64))
    }

    func testRevisionReturnsToSavedValueAfterUndoAndRedoRestoresEdit() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 100, height: 100, color: .white))
        let savedRevision = state.revisionID

        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 30, height: 20)))
        let editedRevision = state.revisionID
        XCTAssertNotEqual(editedRevision, savedRevision)

        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.revisionID, savedRevision)
        XCTAssertTrue(state.redo())
        XCTAssertEqual(state.revisionID, editedRevision)
    }

    func testBlurChangesPixelsInsideBlurRect() throws {
        let state = AnnotationDocumentState()
        state.load(image: checkerboardImage(width: 80, height: 80, blockSize: 4))
        state.addAnnotation(BlurAnnotation(bounds: CGRect(x: 20, y: 10, width: 40, height: 60), radius: 10))
        let flattened = try XCTUnwrap(state.flattenedImage())
        let color = try XCTUnwrap(flattened.sampleColor(x: 40, y: 40))
        let brightness = color.brightnessComponent
        XCTAssertGreaterThan(brightness, 0.08)
        XCTAssertLessThan(brightness, 0.92)
    }

    func testBlurPreservesBrightnessOnSolidColor() throws {
        let sourceColor = NSColor(calibratedRed: 0.44, green: 0.72, blue: 0.96, alpha: 1)
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 120, height: 120, color: sourceColor))
        state.addAnnotation(BlurAnnotation(bounds: CGRect(x: 20, y: 20, width: 80, height: 80), radius: 18))

        let flattened = try XCTUnwrap(state.flattenedImage())
        let blurredColor = try XCTUnwrap(flattened.sampleColor(x: 60, y: 60))
        let expected = try XCTUnwrap(sourceColor.usingColorSpace(.sRGB))
        XCTAssertEqual(blurredColor.redComponent, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(blurredColor.greenComponent, expected.greenComponent, accuracy: 0.02)
        XCTAssertEqual(blurredColor.blueComponent, expected.blueComponent, accuracy: 0.02)
        XCTAssertEqual(blurredColor.alphaComponent, 1, accuracy: 0.001)
    }

    func testUndoRemovesMostRecentCommittedOperationAndRedoRestoresIt() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 60)))
        state.addAnnotation(EllipseAnnotation(bounds: CGRect(x: 40, y: 30, width: 70, height: 50)))

        XCTAssertTrue(state.canUndo)
        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertTrue(state.annotations.first is RectangleAnnotation)
        XCTAssertTrue(state.canRedo)

        XCTAssertTrue(state.redo())
        XCTAssertEqual(state.annotations.count, 2)
        XCTAssertTrue(state.annotations.last is EllipseAnnotation)
    }

    func testNewEditAfterUndoClearsRedo() {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 200, height: 200, color: .white))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 60)))
        state.addAnnotation(EllipseAnnotation(bounds: CGRect(x: 40, y: 30, width: 70, height: 50)))
        XCTAssertTrue(state.undo())
        XCTAssertTrue(state.canRedo)

        state.addAnnotation(ArrowAnnotation(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 140, y: 80)))
        XCTAssertFalse(state.canRedo)
        XCTAssertFalse(state.redo())
        XCTAssertTrue(state.annotations.last is ArrowAnnotation)
    }

    func testApplyCropImmediatelyChangesWorkingImageDimensionsAndUndoRestoresThem() throws {
        let state = AnnotationDocumentState()
        state.load(image: solidImage(width: 240, height: 180, color: .white))
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 20, y: 20, width: 80, height: 60)))

        state.applyCrop(CGRect(x: 40, y: 30, width: 90, height: 70))
        XCTAssertEqual(state.imageSize, CGSize(width: 90, height: 70))
        XCTAssertNil(state.cropRect)
        XCTAssertEqual(state.annotations.count, 0)
        let flattened = try XCTUnwrap(state.flattenedImage())
        XCTAssertEqual(flattened.size, NSSize(width: 90, height: 70))

        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.imageSize, CGSize(width: 240, height: 180))
        XCTAssertEqual(state.annotations.count, 1)
    }

    func testViewportTransformRoundTripsImageAndViewCoordinates() {
        let viewport = ViewportTransform(zoom: 2.5, imageOrigin: CGPoint(x: 40, y: 80))
        let imagePoint = CGPoint(x: 120, y: 44)
        let viewPoint = viewport.viewPoint(forImagePoint: imagePoint)
        XCTAssertEqual(viewPoint.x, 340, accuracy: 0.001)
        XCTAssertEqual(viewPoint.y, 190, accuracy: 0.001)
        let roundTrip = viewport.imagePoint(forViewPoint: viewPoint)
        XCTAssertEqual(roundTrip.x, imagePoint.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, imagePoint.y, accuracy: 0.001)
    }

    func testViewportZoomPreservesFocalImagePoint() {
        let viewport = ViewportTransform(zoom: 1, imageOrigin: CGPoint(x: 20, y: 30))
        let focalViewPoint = CGPoint(x: 220, y: 130)
        let before = viewport.imagePoint(forViewPoint: focalViewPoint)
        let zoomed = viewport.zoomed(to: 2, aroundViewPoint: focalViewPoint)
        let after = zoomed.imagePoint(forViewPoint: focalViewPoint)
        XCTAssertEqual(before.x, after.x, accuracy: 0.001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.001)
    }

    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }

    private func checkerboardImage(width: Int, height: Int, blockSize: Int) -> NSImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in stride(from: 0, to: height, by: blockSize) {
            for x in stride(from: 0, to: width, by: blockSize) {
                let isLight = ((x / blockSize) + (y / blockSize)).isMultiple(of: 2)
                context.setFillColor((isLight ? NSColor.white : NSColor.black).cgColor)
                context.fill(CGRect(x: x, y: y, width: blockSize, height: blockSize))
            }
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }
}

private extension NSImage {
    func sampleColor(x: Int, y: Int) -> NSColor? {
        guard let cgImage = cgImageForRendering() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }

    func countNonWhitePixels() -> Int {
        guard let cgImage = cgImageForRendering() else { return 0 }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent < 0.98 || color.greenComponent < 0.98 || color.blueComponent < 0.98 {
                    count += 1
                }
            }
        }
        return count
    }
}
