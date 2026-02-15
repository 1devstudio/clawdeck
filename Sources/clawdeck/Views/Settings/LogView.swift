import SwiftUI
import AppKit

struct LogView: View {
    @State private var logger = AppLogger.shared
    @State private var selectedLevel: AppLogLevel = .debug
    @State private var selectedCategory: String = "All"
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var scrollProxy: ScrollViewReader?
    
    private var categories: [String] {
        let allCategories = Set(logger.entries.map { $0.category })
        return ["All"] + Array(allCategories).sorted()
    }
    
    private var filteredEntries: [AppLogEntry] {
        logger.entries
            .filter { entry in
                // Filter by level (show selected level and above)
                entry.level.priority >= selectedLevel.priority
            }
            .filter { entry in
                // Filter by category
                selectedCategory == "All" || entry.category == selectedCategory
            }
            .filter { entry in
                // Filter by search text
                searchText.isEmpty || 
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Level filter
                Picker("Level", selection: $selectedLevel) {
                    ForEach(AppLogLevel.allCases) { level in
                        Label(level.displayName, systemImage: level.sfSymbol)
                            .tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                // Category filter
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $searchText)
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                
                // Auto-scroll toggle
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                
                Divider()
                    .frame(height: 20)
                
                // Action buttons
                Button("Clear") {
                    logger.clearLogs()
                }
                .buttonStyle(.bordered)
                
                Button("Export") {
                    exportLogs()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            
            Divider()
            
            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(.regularMaterial)
                .onChange(of: filteredEntries.count) { _, _ in
                    if autoScroll, let lastEntry = filteredEntries.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if autoScroll, let lastEntry = filteredEntries.last {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Application Log")
        .frame(minWidth: 800, minHeight: 500)
    }
    
    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "clawdeck-logs-\(Date().timeIntervalSince1970).txt"
        savePanel.title = "Export Logs"
        
        savePanel.begin { result in
            guard result == .OK, let url = savePanel.url else { return }
            
            let logsContent = logger.exportLogs()
            
            do {
                try logsContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.error("Failed to export logs: \(error.localizedDescription)", category: "UI")
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: AppLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level badge
            HStack(spacing: 4) {
                Image(systemName: entry.level.sfSymbol)
                    .foregroundStyle(entry.level.color)
                    .font(.caption)
                Text(entry.level.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(entry.level.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(entry.level.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: 80)
            
            // Category tag
            Text(entry.category)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 80)
            
            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    LogView()
        .onAppear {
            // Add some sample log entries for preview
            AppLogger.debug("Sample debug message", category: "Network")
            AppLogger.info("Sample info message", category: "Session")
            AppLogger.warning("Sample warning message", category: "UI")
            AppLogger.error("Sample error message", category: "Protocol")
        }
}