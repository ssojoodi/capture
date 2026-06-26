import AppKit
import XCTest
@testable import SkitchEquivalentCore

final class AnnotationCoreTests: XCTestCase {
    func testArrowHitTestingIncludesLineAndExcludesFarPoint() {
        let arrow = ArrowAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 10), strokeWidth: 6)
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 12)))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 50, y: 60)))
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
}
