import Foundation

// MARK: - AnyCodable wrapper

/// A type-erased Codable value for dynamic JSON payloads.
struct AnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported type"))
        }
    }

    // MARK: - Convenience accessors

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var doubleValue: Double? { value as? Double }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var arrayValue: [Any]? { value as? [Any] }

    /// Decode the underlying value as a specific Decodable type.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Frame types

/// Discriminated union for gateway wire frames.
enum GatewayFrame: Sendable {
    case request(RequestFrame)
    case response(ResponseFrame)
    case event(EventFrame)
}

/// Outgoing request frame.
struct RequestFrame: Codable, Sendable {
    let type: String = "req"
    let id: String
    let method: String
    let params: AnyCodable?

    init(id: String = UUID().uuidString, method: String, params: AnyCodable? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case type, id, method, params
    }
}

/// Incoming response frame.
struct ResponseFrame: Codable, Sendable {
    let type: String
    let id: String
    let ok: Bool
    let payload: AnyCodable?
    let error: ErrorShape?
}

/// Incoming event frame.
struct EventFrame: Codable, Sendable {
    let type: String
    let event: String
    let payload: AnyCodable?
}

/// Error shape in response frames.
struct ErrorShape: Codable, Sendable {
    let code: String?
    let message: String?
    let details: AnyCodable?
}

// MARK: - Frame decoder

/// Decodes raw JSON data into a typed GatewayFrame.
enum GatewayFrameDecoder {
    private struct FrameTypeProbe: Decodable {
        let type: String
    }

    static func decode(from data: Data) throws -> GatewayFrame {
        let decoder = JSONDecoder()
        let probe = try decoder.decode(FrameTypeProbe.self, from: data)

        switch probe.type {
        case "req":
            return .request(try decoder.decode(RequestFrame.self, from: data))
        case "res":
            return .response(try decoder.decode(ResponseFrame.self, from: data))
        case "event":
            return .event(try decoder.decode(EventFrame.self, from: data))
        default:
            throw GatewayFrameError.unknownFrameType(probe.type)
        }
    }
}

enum GatewayFrameError: Error, LocalizedError {
    case unknownFrameType(String)

    var errorDescription: String? {
        switch self {
        case .unknownFrameType(let type):
            return "Unknown gateway frame type: \(type)"
        }
    }
}
