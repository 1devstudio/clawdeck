import SwiftUI
import Foundation

// MARK: - Log Level

enum AppLogLevel: String, CaseIterable, Identifiable {
    case debug = "debug"
    case info = "info"  
    case warning = "warning"
    case error = "error"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning" 
        case .error: return "Error"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    var sfSymbol: String {
        switch self {
        case .debug: return "hammer"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
    
    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

// MARK: - Log Entry

struct AppLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: AppLogLevel
    let category: String
    let message: String
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - App Logger

@Observable
@MainActor
final class AppLogger {
    // MARK: - Singleton
    
    static let shared = AppLogger()
    
    private init() {}
    
    // MARK: - Storage
    
    @AppStorage("logLevel") private var logLevelRaw: String = AppLogLevel.info.rawValue
    private var _entries: [AppLogEntry] = []
    private let maxEntries = 5000
    private let lock = NSLock()
    
    var minimumLogLevel: AppLogLevel {
        AppLogLevel(rawValue: logLevelRaw) ?? .info
    }
    
    var entries: [AppLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }
    
    // MARK: - Logging Methods
    
    func log(_ level: AppLogLevel, message: String, category: String = "General") {
        // Check if we should log this level
        guard level.priority >= minimumLogLevel.priority else { return }
        
        let entry = AppLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        lock.lock()
        defer { lock.unlock() }
        
        _entries.append(entry)
        
        // Trim old entries if we exceed max
        if _entries.count > maxEntries {
            let removeCount = _entries.count - maxEntries
            _entries.removeFirst(removeCount)
        }
    }
    
    func clearLogs() {
        lock.lock()
        defer { lock.unlock() }
        _entries.removeAll()
    }
    
    func exportLogs() -> String {
        let entries = self.entries
        
        return entries.map { entry in
            "[\(entry.formattedTimestamp)] [\(entry.level.displayName.uppercased())] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
    
    // MARK: - Static Convenience Methods
    
    static func debug(_ message: String, category: String = "General") {
        shared.log(.debug, message: message, category: category)
    }
    
    static func info(_ message: String, category: String = "General") {
        shared.log(.info, message: message, category: category)
    }
    
    static func warning(_ message: String, category: String = "General") {
        shared.log(.warning, message: message, category: category)
    }
    
    static func error(_ message: String, category: String = "General") {
        shared.log(.error, message: message, category: category)
    }
}