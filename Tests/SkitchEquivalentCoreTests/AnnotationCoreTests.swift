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
        let image = NSImage(size: NSSize(width: 200, height: 200))
        state.load(image: image)
        let bottom = RectangleAnnotation(bounds: CGRect(x: 20, y: 20, width: 120, height: 120))
        let top = BlurAnnotation(bounds: CGRect(x: 30, y: 30, width: 80, height: 80))
        state.addAnnotation(bottom)
        state.addAnnotation(top)
        XCTAssertEqual(state.annotation(at: CGPoint(x: 50, y: 50))?.id, top.id)
    }

    func testCropRectIsClampedToImageBounds() {
        let state = AnnotationDocumentState()
        let image = NSImage(size: NSSize(width: 300, height: 200))
        state.load(image: image)
        state.setCropRect(CGRect(x: -50, y: 20, width: 500, height: 300))
        XCTAssertEqual(state.cropRect, CGRect(x: 0, y: 20, width: 300, height: 180))
    }

    func testFlattenedExportUsesCropDimensions() throws {
        let state = AnnotationDocumentState()
        let image = NSImage(size: NSSize(width: 300, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 200).fill()
        image.unlockFocus()
        state.load(image: image)
        state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 60)))
        state.setCropRect(CGRect(x: 10, y: 20, width: 120, height: 90))
        let flattened = try XCTUnwrap(state.flattenedImage())
        XCTAssertEqual(flattened.size, NSSize(width: 120, height: 90))
        XCTAssertNotNil(state.jpegData())
    }
}
