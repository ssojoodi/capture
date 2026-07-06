import AppKit

public enum ImageRenderer {
    public static func render(state: AnnotationDocumentState) -> NSImage? {
        guard let baseCGImage = state.baseCGImage else { return nil }
        let sourceSize = state.imageSize
        let imageBounds = CGRect(origin: .zero, size: sourceSize)
        let crop = state.cropRect ?? imageBounds
        let outputSize = crop.size
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width.rounded()),
            height: Int(outputSize.height.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: -crop.origin.x, y: -crop.origin.y)
        context.draw(baseCGImage, in: imageBounds)
        for annotation in state.annotations where annotation is BlurAnnotation {
            annotation.draw(in: context, baseImage: baseCGImage, imageSize: sourceSize, scale: 1)
        }
        for annotation in state.annotations where !(annotation is BlurAnnotation) {
            annotation.draw(in: context, baseImage: baseCGImage, imageSize: sourceSize, scale: 1)
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: outputSize)
    }
}
