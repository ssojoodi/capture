import AppKit

public enum ImageRenderer {
    public static func render(state: AnnotationDocumentState) -> NSImage? {
        guard let baseCGImage = state.baseCGImage else { return nil }
        let sourceSize = state.imageSize
        let imageBounds = CGRect(origin: .zero, size: sourceSize)
        let crop = state.cropRect ?? state.canvasBounds
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
    /// A standalone annotation image with no source image or selection decoration.
    public static func renderAnnotation(_ annotation: Annotation) -> CGImage? {
        guard !(annotation is BlurAnnotation) else { return nil }
        let bounds = annotation.renderedBounds.insetBy(dx: -1, dy: -1).integral
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width < CGFloat(Int.max), bounds.height < CGFloat(Int.max),
              let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        annotation.draw(in: context, baseImage: nil, imageSize: bounds.size, scale: 1)
        return context.makeImage()
    }

    /// Transparent samples carry no weight; premultiplied RGB is divided by total alpha.
    public static func averageVisibleColor(in image: CGImage) -> CGColor {
        let width = min(64, image.width)
        let height = min(64, image.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let sample = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = sample.data else { return NSColor.white.cgColor }
        sample.interpolationQuality = .high
        sample.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            red += Double(bytes[offset])
            green += Double(bytes[offset + 1])
            blue += Double(bytes[offset + 2])
            alpha += Double(bytes[offset + 3])
        }
        guard alpha > 0 else { return NSColor.white.cgColor }
        return CGColor(colorSpace: colorSpace, components: [red / alpha, green / alpha, blue / alpha, 1])!
    }

    public static func opaqueJPEGImage(from image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(averageVisibleColor(in: image))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

}
