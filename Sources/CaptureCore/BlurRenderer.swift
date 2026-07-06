import AppKit

public enum BlurRenderer {
    public static func blurredRegion(from baseImage: CGImage, imageSize: CGSize, rect imageRect: CGRect, radius: CGFloat) -> CGImage? {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let normalized = imageRect.normalized.clamped(to: imageBounds).integral
        guard !normalized.isNull, normalized.width >= 1, normalized.height >= 1 else { return nil }

        let pixelRect = CGRect(
            x: normalized.origin.x,
            y: imageSize.height - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        ).integral.intersection(imageBounds)
        guard !pixelRect.isNull, let crop = baseImage.cropping(to: pixelRect) else { return nil }

        let colorSpace = baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        let pixelSize = max(4, radius)
        let sampleWidth = max(1, Int((normalized.width / pixelSize).rounded(.up)))
        let sampleHeight = max(1, Int((normalized.height / pixelSize).rounded(.up)))
        guard let sampleContext = CGContext(
            data: nil,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        sampleContext.interpolationQuality = .high
        sampleContext.setBlendMode(.copy)
        sampleContext.draw(crop, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        guard let sampledImage = sampleContext.makeImage() else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: Int(normalized.width),
            height: Int(normalized.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        outputContext.interpolationQuality = .none
        outputContext.setBlendMode(.copy)
        outputContext.draw(sampledImage, in: CGRect(x: 0, y: 0, width: normalized.width, height: normalized.height))
        return outputContext.makeImage()
    }
}
