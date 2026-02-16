import SwiftUI

/// Compact pill showing context window usage (e.g. "189k/200k (94%)").
/// Placed next to the model selector above the composer.
struct ContextUsageView: View {
    let totalTokens: Int
    let contextTokens: Int?

    /// Usage percentage (0–100), or nil if context window is unknown.
    private var usagePercent: Int? {
        guard let ctx = contextTokens, ctx > 0 else { return nil }
        return min(100, Int(round(Double(totalTokens) / Double(ctx) * 100)))
    }

    /// Color based on usage level.
    private var usageColor: Color {
        guard let pct = usagePercent else { return .secondary }
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .secondary
    }

    var body: some View {
        Text(usageLabel)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
        .foregroundStyle(usageColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .help(tooltipText)
    }

    /// Compact label (e.g. "189k/200k (94%)" or "189k tokens").
    private var usageLabel: String {
        let totalStr = formatTokenCount(totalTokens)
        if let ctx = contextTokens, ctx > 0, let pct = usagePercent {
            return "\(totalStr)/\(formatTokenCount(ctx)) (\(pct)%)"
        }
        return "\(totalStr) tokens"
    }

    /// Tooltip with full details.
    private var tooltipText: String {
        let totalStr = formatTokenCount(totalTokens)
        if let ctx = contextTokens, ctx > 0, let pct = usagePercent {
            let remaining = max(0, ctx - totalTokens)
            return "Context: \(totalStr) / \(formatTokenCount(ctx)) tokens (\(pct)%)\n\(formatTokenCount(remaining)) remaining"
        }
        return "Context: \(totalStr) tokens used"
    }

    /// Format a token count compactly (e.g. 189432 → "189k", 1500000 → "1.5M").
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        } else if count >= 1000 {
            let k = Double(count) / 1000
            return k >= 100 ? String(format: "%.0fk", k) : String(format: "%.0fk", k)
        }
        return "\(count)"
    }
}
