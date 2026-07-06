import AppKit

public struct CaptureColor: Equatable {
    public let name: String
    public let color: NSColor

    public init(name: String, color: NSColor) {
        self.name = name
        self.color = color
    }

    public static func == (lhs: CaptureColor, rhs: CaptureColor) -> Bool {
        lhs.name == rhs.name
    }
}

public enum CapturePalette {
    public static let softRed = NSColor(calibratedRed: 0.93, green: 0.24, blue: 0.42, alpha: 1)
    public static let softBlue = NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.86, alpha: 1)
    public static let softGreen = NSColor(calibratedRed: 0.22, green: 0.64, blue: 0.42, alpha: 1)
    public static let softOrange = NSColor(calibratedRed: 0.94, green: 0.50, blue: 0.23, alpha: 1)
    public static let softYellow = NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.22, alpha: 1)
    public static let softWhite = NSColor(calibratedWhite: 0.98, alpha: 1)
    public static let softBlack = NSColor(calibratedWhite: 0.12, alpha: 1)

    public static let all: [CaptureColor] = [
        CaptureColor(name: "Red", color: softRed),
        CaptureColor(name: "Blue", color: softBlue),
        CaptureColor(name: "Green", color: softGreen),
        CaptureColor(name: "Orange", color: softOrange),
        CaptureColor(name: "Yellow", color: softYellow),
        CaptureColor(name: "White", color: softWhite),
        CaptureColor(name: "Black", color: softBlack)
    ]
}
