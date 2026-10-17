import Foundation
import Darwin
#if canImport(CaptureAutomation)
import CaptureAutomation
#endif

/// Socket work stays off the main thread; command execution is serialized on it.
final class AgentServer {
    private let directory: String
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var lockFile: Int32 = -1
    private var clients: Set<Int32> = []
    private var generation = UUID()
    var handle: (([String: Any]) -> [String: Any])?
    var connectionChanged: ((Int) -> Void)?
    init(appPath: String = Bundle.main.bundlePath) { directory = AgentWire.directory(for: appPath) }
    deinit { stop() }

    func start() throws {
        guard listener < 0 else { return }
        try AgentWire.prepareDirectory(directory)
        let file = open(directory + "/owner.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw AgentWire.failure("Open agent lock") }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else { close(file); throw AgentError("connection_unavailable", "Another copy of this Capture app is already serving agents.") }
        lockFile = file
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { stop(); throw AgentWire.failure("Create listener") }
        unlink(directory + "/agent.sock")
        do {
            let bound = try AgentWire.address(directory + "/agent.sock") { Darwin.bind(fd, $0, $1) }
            guard bound == 0, chmod(directory + "/agent.sock", 0o600) == 0, listen(fd, 8) == 0 else { throw AgentWire.failure("Listen") }
        } catch { close(fd); stop(); throw error }
        lock.lock(); listener = fd; let epoch = generation; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { close(fd) }
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                guard let self else { close(client); break }
                AgentWire.configure(client, timeout: 300)
                self.lock.lock()
                let permitted = self.generation == epoch && self.clients.count < 8 && AgentWire.sameUser(client)
                if permitted { self.clients.insert(client) }
                self.lock.unlock()
                guard permitted else { close(client); continue }
                self.notifyConnections()
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(client, epoch: epoch) }
            }
        }
    }
    func stop() {
        lock.lock()
        generation = UUID()
        if listener >= 0 { shutdown(listener, SHUT_RDWR); listener = -1 }
        for client in clients { shutdown(client, SHUT_RDWR) }
        lock.unlock()
        if lockFile >= 0 { unlink(directory + "/agent.sock"); flock(lockFile, LOCK_UN); close(lockFile); lockFile = -1 }
    }
    private func notifyConnections() {
        lock.lock(); let count = clients.count; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.connectionChanged?(count) }
    }
    private func serve(_ fd: Int32, epoch: UUID) {
        defer { lock.lock(); clients.remove(fd); lock.unlock(); close(fd); notifyConnections() }
        do {
            while true {
                let request = try AgentWire.read(fd, limit: AgentWire.requestLimit)
                let response: [String: Any] = DispatchQueue.main.sync {
                    self.lock.lock(); let current = self.generation == epoch; self.lock.unlock()
                    guard current else { return AgentError("access_disabled", "Agent control was disabled.").response }
                    return self.handle?(request) ?? AgentError("unavailable", "Capture is not ready.").response
                }
                try AgentWire.write(response, to: fd, limit: AgentWire.responseLimit)
            }
        } catch { /* Disconnects end this session. Never replay commands. */ }
    }
}
