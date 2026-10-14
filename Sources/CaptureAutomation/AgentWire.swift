import Foundation
import CryptoKit
import Darwin

public struct AgentError: Error, LocalizedError {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { "\(code): \(message)" }
    public var response: [String: Any] { ["error": ["code": code, "message": message]] }
}

/// Private, bounded, length-prefixed JSON between the helper and the app.
public enum AgentWire {
    public static let requestLimit = 1_048_576
    public static let responseLimit = 20_971_520
    public static func directory(for appPath: String) -> String {
        let hash = SHA256.hash(data: Data(URL(fileURLWithPath: appPath).resolvingSymlinksInPath().path.utf8))
        let suffix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "/tmp/capture-\(getuid())-\(suffix)"
    }
    public static func prepareDirectory(_ directory: String) throws {
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw failure("Create private directory") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            throw AgentError("connection_unavailable", "Agent directory must be owned by this user with mode 0700.")
        }
    }
    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
    public static func address<T>(_ path: String, _ operation: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw AgentError("connection_unavailable", "Socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try operation($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    public static func configure(_ fd: Int32, timeout: Int = 30) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var time = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout.size(ofValue: time)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout.size(ofValue: time)))
    }
    public static func connect(to directory: String) throws -> Int32 {
        try prepareDirectory(directory)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("Create socket") }
        configure(fd)
        do {
            let result = try address(directory + "/agent.sock") { Darwin.connect(fd, $0, $1) }
            guard result == 0, sameUser(fd) else { throw AgentError("connection_unavailable", "Open Capture and enable Allow Agent Control, then retry. No edit was replayed.") }
            return fd
        } catch { close(fd); throw error }
    }
    public static func read(_ fd: Int32, limit: Int) throws -> [String: Any] {
        let header = try receive(fd, count: 4)
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0 && size <= limit else { throw AgentError("invalid_request", "Message exceeds the size limit.") }
        let data = try receive(fd, count: size)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentError("invalid_request", "Expected a JSON object.") }
        return result
    }
    public static func write(_ value: [String: Any], to fd: Int32, limit: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= limit else { throw AgentError("limit_exceeded", "Message exceeds the size limit.") }
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw failure("Write response; inspect before retrying edits") }
                offset += sent
            }
        }
    }
    private static func receive(_ fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure("Connection closed or timed out; inspect before retrying edits") }
                offset += n
            }
        }
        return data
    }
    public static func failure(_ action: String) -> AgentError { AgentError("connection_unavailable", action + ": " + String(cString: strerror(errno))) }
}
