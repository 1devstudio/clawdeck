import Foundation

/// Lifecycle phase of a tool call.
enum ToolCallPhase: String, Sendable {
    case running     // Tool is executing
    case completed   // Tool finished successfully
    case error       // Tool returned an error
}

/// A single tool call within an agent run, displayed inline in the chat.
@Observable
final class ToolCall: Identifiable {
    let id: String            // toolCallId from the gateway
    let name: String          // Tool name (e.g. "exec", "Read", "web_search")
    var phase: ToolCallPhase
    var args: [String: Any]?  // Input arguments (from "start" phase)
    var result: String?       // Tool result text (from "result" phase)
    var isError: Bool         // Whether the result is an error
    let startedAt: Date

    /// Human-readable summary of tool arguments (e.g. file path, command).
    var meta: String? {
        guard let args = args else { return nil }
        let name = self.name.lowercased()

        // File operations
        if name == "read" {
            return (args["path"] as? String) ?? (args["file_path"] as? String)
        }
        if name == "write" {
            return (args["path"] as? String) ?? (args["file_path"] as? String)
        }
        if name == "edit" {
            return (args["path"] as? String) ?? (args["file_path"] as? String)
        }

        // Shell commands
        if name == "exec" || name == "bash" {
            return (args["command"] as? String).map { cmd in
                String(cmd.prefix(120))
            }
        }

        // Web
        if name == "web_search" {
            return (args["query"] as? String)
        }
        if name == "web_fetch" {
            return (args["url"] as? String)
        }

        // Browser
        if name == "browser" {
            return (args["action"] as? String)
        }

        // Memory
        if name == "memory_search" {
            return (args["query"] as? String)
        }
        if name == "memory_get" {
            return (args["path"] as? String)
        }

        // Sessions
        if name == "sessions_spawn" {
            return (args["task"] as? String).map { String($0.prefix(80)) }
        }

        // Image analysis
        if name == "image" {
            return (args["prompt"] as? String).map { String($0.prefix(80)) }
        }

        // Cron
        if name == "cron" {
            return (args["action"] as? String)
        }

        // Message
        if name == "message" {
            return (args["action"] as? String)
        }

        // Session status
        if name == "session_status" {
            return nil
        }

        // TTS
        if name == "tts" {
            return (args["text"] as? String).map { String($0.prefix(60)) }
        }

        // Generic: try common parameter names
        if let path = args["path"] as? String { return path }
        if let query = args["query"] as? String { return query }
        if let action = args["action"] as? String { return action }

        return nil
    }

    /// Icon name for the tool type.
    var iconName: String {
        let name = self.name.lowercased()
        switch name {
        case "read":                    return "doc.text"
        case "write":                   return "doc.text.fill"
        case "edit":                    return "pencil"
        case "exec", "bash":            return "terminal"
        case "web_search":              return "magnifyingglass"
        case "web_fetch":               return "globe"
        case "browser":                 return "safari"
        case "memory_search":           return "brain"
        case "memory_get":              return "brain.head.profile"
        case "image":                   return "photo"
        case "sessions_spawn":          return "arrow.branch"
        case "sessions_send":           return "paperplane"
        case "sessions_list":           return "list.bullet"
        case "sessions_history":        return "clock"
        case "session_status":          return "chart.bar"
        case "cron":                    return "clock.arrow.circlepath"
        case "message":                 return "message"
        case "tts":                     return "speaker.wave.2"
        case "canvas":                  return "paintbrush"
        case "nodes":                   return "desktopcomputer"
        case "gateway":                 return "server.rack"
        case "agents_list":             return "person.2"
        default:                        return "wrench"
        }
    }

    init(
        id: String,
        name: String,
        phase: ToolCallPhase = .running,
        args: [String: Any]? = nil,
        result: String? = nil,
        isError: Bool = false,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.phase = phase
        self.args = args
        self.result = result
        self.isError = isError
        self.startedAt = startedAt
    }
}
