import Foundation
import SwiftUI

enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic
    case openAI
    case grok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: "A"
        case .openAI: "O"
        case .grok: "X"
        }
    }

    var color: Color {
        switch self {
        case .anthropic: Color(red: 0.89, green: 0.39, blue: 0.20)
        case .openAI: Color(red: 0.13, green: 0.62, blue: 0.48)
        case .grok: Color(red: 0.32, green: 0.48, blue: 0.94)
        }
    }

    var loginHint: String {
        switch self {
        case .anthropic: "Sign in with Claude Code"
        case .openAI: "Sign in with Codex"
        case .grok: "Sign in with Grok CLI"
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case remaining = "Remaining"
    case used = "Used"

    var id: String { rawValue }

    var metricSuffix: String {
        self == .remaining ? "fuel" : "used"
    }
}

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    init(id: String, label: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.id = id
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }

    func percentage(for mode: DisplayMode) -> Double {
        mode == .used ? usedPercent : 100 - usedPercent
    }

    var resetText: String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSinceNow
        guard seconds > 0 else { return "resetting" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "resets in \(max(1, minutes))m" }
        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        if hours < 24 { return "resets in \(hours)h \(leftoverMinutes)m" }
        return "resets in \(hours / 24)d \(hours % 24)h"
    }
}

struct ProviderUsage: Identifiable, Equatable, Sendable {
    let provider: ProviderID
    let windows: [UsageWindow]
    let message: String?
    let refreshedAt: Date

    var id: ProviderID { provider }

    static func loading(_ provider: ProviderID) -> ProviderUsage {
        ProviderUsage(provider: provider, windows: [], message: "Refreshing…", refreshedAt: .distantPast)
    }

    static func failed(_ provider: ProviderID, message: String) -> ProviderUsage {
        ProviderUsage(provider: provider, windows: [], message: message, refreshedAt: Date())
    }

    var mostConstrained: UsageWindow? {
        windows.max(by: { $0.usedPercent < $1.usedPercent })
    }
}

struct UsageLimitAlert: Equatable, Sendable {
    let id: String
    let provider: ProviderID
    let window: UsageWindow

    var title: String {
        "\(provider.name) usage reached \(Int(window.usedPercent.rounded()))%"
    }

    var body: String {
        let remaining = Int((100 - window.usedPercent).rounded())
        let reset = window.resetText.map { ". \($0.capitalized)" } ?? ""
        return "\(window.label) has \(remaining)% fuel remaining\(reset)."
    }
}

enum UsageLimitAlertPolicy {
    static func alerts(
        in usages: [ProviderID: ProviderUsage],
        threshold: Int,
        excluding deliveredIDs: Set<String>
    ) -> [UsageLimitAlert] {
        usages.values.flatMap { usage in
            usage.windows.compactMap { window in
                guard window.usedPercent >= Double(threshold) else { return nil }
                let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "rolling"
                let id = "notchfuel-\(usage.provider.rawValue)-\(window.id)-\(cycle)-\(threshold)"
                guard !deliveredIDs.contains(id) else { return nil }
                return UsageLimitAlert(id: id, provider: usage.provider, window: window)
            }
        }
        .sorted { $0.window.usedPercent > $1.window.usedPercent }
    }
}

enum UsageClientError: LocalizedError, Sendable {
    case notSignedIn(ProviderID)
    case expired(ProviderID)
    case http(ProviderID, Int)
    case invalidResponse(ProviderID)

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let provider): provider.loginHint
        case .expired(let provider): "Open \(provider.name) once to renew its session"
        case .http(_, let code): "Refresh failed (HTTP \(code))"
        case .invalidResponse: "Usage data is not available yet"
        }
    }
}
