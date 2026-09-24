import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        newDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func newDocument(_ sender: Any?) {
        let previousWindow = NSApp.keyWindow ?? windowControllers.last?.window
        let controller = MainWindowController()
        controller.onWindowClosed = { [weak self] closedController in
            self?.windowControllers.removeAll { $0 === closedController }
        }
        windowControllers.append(controller)
        if let previousWindow {
            let topLeft = NSPoint(x: previousWindow.frame.minX + 24, y: previousWindow.frame.maxY - 24)
            controller.window?.cascadeTopLeft(from: topLeft)
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for controller in windowControllers {
            if !controller.canTerminate() { return .terminateCancel }
        }
        return .terminateNow
    }
}
