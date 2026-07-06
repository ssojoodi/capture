#!/usr/bin/env swift

import AppKit
import Foundation

func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center, letterSpacing: Double = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: letterSpacing
    ]

    text.draw(in: rect, withAttributes: attributes)
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()

    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawArrow(in rect: CGRect) {
    let path = NSBezierPath()
    let minX = rect.minX
    let midY = rect.midY
    let width = rect.width
    let height = rect.height

    path.move(to: CGPoint(x: minX, y: midY + height * 0.10))
    path.curve(
        to: CGPoint(x: minX + width * 0.68, y: midY + height * 0.20),
        controlPoint1: CGPoint(x: minX + width * 0.26, y: midY + height * 0.12),
        controlPoint2: CGPoint(x: minX + width * 0.48, y: midY + height * 0.18)
    )
    path.line(to: CGPoint(x: minX + width * 0.64, y: midY + height * 0.48))
    path.line(to: CGPoint(x: minX + width, y: midY))
    path.line(to: CGPoint(x: minX + width * 0.64, y: midY - height * 0.48))
    path.line(to: CGPoint(x: minX + width * 0.68, y: midY - height * 0.20))
    path.curve(
        to: CGPoint(x: minX, y: midY - height * 0.10),
        controlPoint1: CGPoint(x: minX + width * 0.48, y: midY - height * 0.18),
        controlPoint2: CGPoint(x: minX + width * 0.26, y: midY - height * 0.12)
    )
    path.curve(
        to: CGPoint(x: minX, y: midY + height * 0.10),
        controlPoint1: CGPoint(x: minX - 6, y: midY - height * 0.10),
        controlPoint2: CGPoint(x: minX - 6, y: midY + height * 0.10)
    )
    path.close()

    NSColor(calibratedRed: 0.055, green: 0.647, blue: 0.914, alpha: 1).setFill()
    path.fill()
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: render_dmg_background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = CGSize(width: 660, height: 400)
let image = NSImage(size: size)

image.lockFocus()

let bounds = CGRect(origin: .zero, size: size)
NSGradient(
    starting: NSColor(calibratedRed: 0.99, green: 0.995, blue: 1, alpha: 1),
    ending: NSColor(calibratedRed: 0.87, green: 0.965, blue: 1, alpha: 1)
)?.draw(in: bounds, angle: -35)

roundedRect(
    CGRect(x: 26, y: 26, width: 608, height: 348),
    radius: 30,
    fill: NSColor.white.withAlphaComponent(0.72),
    stroke: NSColor(calibratedRed: 0.49, green: 0.827, blue: 0.988, alpha: 0.88),
    lineWidth: 2
)

drawText(
    "Capture",
    in: CGRect(x: 60, y: 318, width: 540, height: 44),
    font: NSFont.systemFont(ofSize: 36, weight: .bold),
    color: NSColor(calibratedRed: 0.027, green: 0.349, blue: 0.522, alpha: 1)
)

drawText(
    "DRAG TO INSTALL",
    in: CGRect(x: 60, y: 290, width: 540, height: 22),
    font: NSFont.systemFont(ofSize: 14, weight: .medium),
    color: NSColor(calibratedRed: 0.012, green: 0.518, blue: 0.753, alpha: 1),
    letterSpacing: 2
)

let panelFill = NSColor.white.withAlphaComponent(0.94)
let panelStroke = NSColor(calibratedRed: 0.49, green: 0.827, blue: 0.988, alpha: 0.82)
roundedRect(CGRect(x: 90, y: 92, width: 158, height: 158), radius: 34, fill: panelFill, stroke: panelStroke, lineWidth: 2)
roundedRect(CGRect(x: 412, y: 92, width: 158, height: 158), radius: 34, fill: panelFill, stroke: panelStroke, lineWidth: 2)

drawArrow(in: CGRect(x: 291, y: 146, width: 84, height: 50))

drawText(
    "Capture.app",
    in: CGRect(x: 70, y: 62, width: 198, height: 22),
    font: NSFont.systemFont(ofSize: 13, weight: .medium),
    color: NSColor(calibratedRed: 0.027, green: 0.349, blue: 0.522, alpha: 1)
)

drawText(
    "Applications",
    in: CGRect(x: 392, y: 62, width: 198, height: 22),
    font: NSFont.systemFont(ofSize: 13, weight: .medium),
    color: NSColor(calibratedRed: 0.027, green: 0.349, blue: 0.522, alpha: 1)
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL)
} catch {
    fputs("write failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
