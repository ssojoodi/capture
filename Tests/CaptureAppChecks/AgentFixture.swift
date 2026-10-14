import AppKit
import CaptureCore

/// Runs a real app delegate/server with isolated preferences, never enabling the installed app.
@main
enum AgentFixture {
    static func main() {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let suite = "Capture.AgentFixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "agentControl.enabled")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .aqua)
        let delegate = AppDelegate(agentDefaults: defaults, agentSocketIdentity: folder.path)
        app.delegate = delegate
        app.mainMenu = AppMenu.makeMenu()
        let cg = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 20, y: 20, width: 600, height: 360))
        cg.setFillColor(NSColor.systemBlue.cgColor); cg.fill(CGRect(x: 80, y: 100, width: 220, height: 100))
        let png = NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
        try! png.write(to: folder.appendingPathComponent("input.png"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try! Data(AgentWire.directory(for: folder.path).utf8).write(to: folder.appendingPathComponent("ready"))
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let control = folder.appendingPathComponent("control.json")
            guard let data = try? Data(contentsOf: control), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
            try? FileManager.default.removeItem(at: control)
            let controllers = app.windows.compactMap { $0.windowController as? MainWindowController }
            let controller = controllers.first { $0.agentDocument.id == value["documentID"] }
            switch value["action"] {
            case "toggle": delegate.toggleAgentControl(nil)
            case "user_edit": controller?.agentDocument.state.addAnnotation(RectangleAnnotation(bounds: CGRect(x: 5, y: 5, width: 10, height: 10)))
            case "busy": if let window = controller?.window { window.beginSheet(NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 80), styleMask: [.titled], backing: .buffered, defer: false)) }
            case "resume": if let window = controller?.window, let sheet = window.attachedSheet { window.endSheet(sheet) }
            case "quit":
                defaults.removePersistentDomain(forName: suite)
                delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
                exit(0)
            default: break
            }
            try! Data("ok".utf8).write(to: folder.appendingPathComponent("ack"))
        }
        _ = timer
        app.run()
    }
}
