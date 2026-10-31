// Modified for Capture: omit emitted progress notifications; retain metadata decoding.
import Foundation

/// A token used to associate progress notifications with their originating request.
///
/// Progress tokens can be either strings or integers.
/// Progress tokens MUST be unique across all active requests.
public enum ProgressToken: Hashable, Codable, Sendable {
    case string(String)
    case integer(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Progress token must be a string or integer"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        }
    }

    /// Creates a unique progress token using UUID.
    public static func unique() -> ProgressToken {
        .string(UUID().uuidString)
    }
}

/// Metadata that can be included in request parameters.
///
/// This structure represents the `_meta` field in MCP request parameters,
/// which can contain a progress token for receiving progress notifications.
///
/// - SeeAlso: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress
public struct Metadata: Hashable, Codable, Sendable {
    public subscript(_ key: String) -> Value? {
        fields[key]
    }

    /// The underlying fields dictionary.
    public var fields: [String: Value]

    /// The progress token for receiving progress notifications.
    ///
    /// If specified, the caller is requesting out-of-band progress notifications
    /// for this request. The value of this parameter is an opaque token that will
    /// be attached to any subsequent notifications. The receiver is not obligated
    /// to provide these notifications.
    public var progressToken: ProgressToken? {
        get {
            guard let value = fields["progressToken"] else { return nil }
            if let stringValue = value.stringValue {
                return .string(stringValue)
            } else if let intValue = value.intValue {
                return .integer(intValue)
            }
            return nil
        }
        set {
            if let token = newValue {
                switch token {
                case .string(let s):
                    fields["progressToken"] = .string(s)
                case .integer(let i):
                    fields["progressToken"] = .int(i)
                }
            } else {
                fields.removeValue(forKey: "progressToken")
            }
        }
    }

    /// Creates request metadata.
    ///
    /// - Parameters:
    ///   - progressToken: Optional progress token for receiving progress notifications.
    ///     If specified, the caller is requesting out-of-band progress notifications for this request.
    ///   - additionalFields: Optional dictionary of additional metadata fields.
    ///     These fields will be included in the `_meta` object alongside the progress token.
    public init(progressToken: ProgressToken? = nil, additionalFields: [String: Value] = [:]) {
        self.fields = additionalFields
        self.progressToken = progressToken
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.fields = try container.decode([String: Value].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}
