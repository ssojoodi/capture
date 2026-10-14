import AppKit
import CaptureCore
#if canImport(CaptureAutomation)
import CaptureAutomation
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let updates = UpdateController()
    private let agentServer: AgentServer
    private let agentDefaults: UserDefaults
    init(agentDefaults: UserDefaults = .standard, agentSocketIdentity: String = Bundle.main.bundlePath) {
        self.agentDefaults = agentDefaults
        agentServer = AgentServer(appPath: agentSocketIdentity)
        super.init()
    }
    private var agentStatus = "Agent control off"
    private var agentEnabled: Bool { agentDefaults.bool(forKey: "agentControl.enabled") }
    private var windowControllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        agentServer.handle = { [weak self] request in self?.handleAgentRequest(request) ?? AgentError("unavailable", "Capture is closing.").response }
        agentServer.connectionChanged = { [weak self] count in
            guard let self else { return }
            self.agentStatus = self.agentEnabled ? "Agent connections: \(count)" : "Agent control off"
        }
        if agentEnabled { startAgentServer() }
        newDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) { updates.applicationDidBecomeActive() }
    func applicationDidResignActive(_ notification: Notification) { updates.applicationDidResignActive() }
    @objc func checkForUpdates(_ sender: Any?) { updates.checkForUpdates(sender) }
    @objc func toggleAutomaticChecks(_ sender: Any?) { updates.toggleAutomaticChecks(sender) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAgentControl(_:)) { item.state = agentEnabled ? .on : .off; return true }
        if item.action == #selector(showAgentStatus(_:)) { item.title = agentStatus; return false }
        return updates.validateMenuItem(item)
    }
    @objc func showAgentStatus(_ sender: Any?) {}
    @objc func toggleAgentControl(_ sender: Any?) {
        agentDefaults.set(!agentEnabled, forKey: "agentControl.enabled")
        if agentEnabled { startAgentServer() } else { agentServer.stop(); agentStatus = "Agent control off" }
    }
    private func startAgentServer() {
        do { try agentServer.start(); agentStatus = "Agent connections: 0" }
        catch { agentStatus = "Agent control unavailable: " + error.localizedDescription }
    }
    @objc func copyMCPConfiguration(_ sender: Any?) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/capture-mcp").path
        let config: [String: Any] = ["mcpServers": ["capture": ["command": helper, "args": [] as [String]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func handleAgentRequest(_ request: [String: Any]) -> [String: Any] {
        guard agentEnabled else { return AgentError("access_disabled", "Enable Capture → Allow Agent Control.").response }
        do {
            guard let method = request["method"] as? String, let arguments = request["arguments"] as? [String: Any] else { throw AgentError("invalid_request", "Expected method and arguments.") }
            try AgentTools.validate(method, arguments: arguments)
            if method == "list_documents" {
                return ["documents": windowControllers.map { controller -> [String: Any] in
                    var value = controller.agentDocument.summary(busy: controller.agentBusy)
                    value["title"] = controller.window?.title ?? "Capture"
                    return value
                }]
            }
            if method == "open_image" {
                guard NSApp.modalWindow == nil else { throw AgentError("document_busy", "Dismiss the active dialog first.") }
                let path = arguments["path"] as! String
                let image = try AgentDocument.image(at: path)
                let controller = MainWindowController()
                controller.agentLoad(image, url: try AgentDocument.fileURL(path))
                controller.onWindowClosed = { [weak self] closed in self?.windowControllers.removeAll { $0 === closed } }
                windowControllers.append(controller)
                controller.window?.orderFront(nil)
                return controller.agentDocument.inspect()
            }
            guard let id = arguments["documentID"] as? String, let controller = windowControllers.first(where: { $0.agentDocument.id == id }) else { throw AgentError("document_not_found", "List documents to obtain a current document ID.") }
            return try controller.agentPerform(method, arguments: arguments)
        } catch let error as AgentError { return error.response }
        catch { return AgentError("operation_failed", error.localizedDescription).response }
    }
    func applicationWillTerminate(_ notification: Notification) { agentServer.stop() }

    @objc func newDocument(_ sender: Any?) {
        let previousWindow = NSApp.keyWindow ?? windowControllers.last?.window
        let screen = previousWindow?.screen ?? NSScreen.main
        let controller = MainWindowController(screen: screen)
        controller.onWindowClosed = { [weak self] closedController in
            self?.windowControllers.removeAll { $0 === closedController }
        }
        windowControllers.append(controller)
        if let previousWindow {
            let topLeft = NSPoint(x: previousWindow.frame.minX + 24, y: previousWindow.frame.maxY - 24)
            controller.window?.cascadeTopLeft(from: topLeft)
            if let window = controller.window, let visibleFrame = screen?.visibleFrame {
                window.setFrame(window.frame.fitted(inside: visibleFrame), display: false)
            }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !PNGShareSession.hasActiveSessions
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for controller in windowControllers {
            if !controller.canTerminate() { return .terminateCancel }
        }
        return .terminateNow
    }
}
