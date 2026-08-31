import Foundation

enum UsageParsers {
    static func anthropic(_ data: Data) throws -> [UsageWindow] {
        let root = try dictionary(data)

        if let limits = root["limits"] as? [[String: Any]] {
            let windows = limits.compactMap { limit -> UsageWindow? in
                guard let percent = number(limit["percent"]) ?? number(limit["utilization"]) else { return nil }
                let kind = limit["kind"] as? String ?? "weekly"
                let scope = limit["scope"] as? [String: Any]
                let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                let label: String
                switch kind {
                case "session": label = "Session"
                case "weekly_all": label = "Weekly"
                default: label = model ?? title(kind)
                }
                return UsageWindow(
                    id: "anthropic-\(kind)-\(model ?? "all")",
                    label: label,
                    usedPercent: percent,
                    resetsAt: date(limit["resets_at"])
                )
            }
            if !windows.isEmpty { return windows }
        }

        let legacy: [(String, String)] = [
            ("five_hour", "Session"),
            ("seven_day", "Weekly"),
            ("seven_day_sonnet", "Sonnet"),
            ("seven_day_opus", "Opus")
        ]
        let windows = legacy.compactMap { key, label -> UsageWindow? in
            guard let item = root[key] as? [String: Any],
                  let percent = number(item["utilization"]) ?? number(item["percent"]) else { return nil }
            return UsageWindow(id: "anthropic-\(key)", label: label, usedPercent: percent, resetsAt: date(item["resets_at"]))
        }
        guard !windows.isEmpty else { throw UsageClientError.invalidResponse(.anthropic) }
        return windows
    }

    static func openAI(_ data: Data) throws -> [UsageWindow] {
        let root = try dictionary(data)
        let rateLimit = (root["rate_limit"] as? [String: Any])
            ?? (root["rate_limits"] as? [String: Any])
            ?? root

        let candidates: [(String, String)] = [
            ("primary_window", "Session"),
            ("primary", "Session"),
            ("secondary_window", "Weekly"),
            ("secondary", "Weekly")
        ]
        var seen = Set<String>()
        let windows = candidates.compactMap { key, fallbackLabel -> UsageWindow? in
            guard let window = rateLimit[key] as? [String: Any],
                  let percent = number(window["used_percent"]) ?? number(window["utilization"]) else { return nil }
            let minutes = int(window["window_minutes"])
            let label = minutes.map { windowLabel(minutes: $0, fallback: fallbackLabel) } ?? fallbackLabel
            guard seen.insert(label).inserted else { return nil }
            let reset = date(window["reset_at"] ?? window["resets_at"])
                ?? int(window["reset_after_seconds"]).map { Date().addingTimeInterval(TimeInterval($0)) }
            return UsageWindow(id: "openai-\(key)", label: label, usedPercent: percent, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw UsageClientError.invalidResponse(.openAI) }
        return windows
    }

    static func grokCredits(_ data: Data) throws -> [UsageWindow] {
        let root = try dictionary(data)
        let config = root["config"] as? [String: Any] ?? root
        let reset = date(config["billingPeriodEnd"])
            ?? date((config["currentPeriod"] as? [String: Any])?["end"])
            ?? date(root["period_end"])
        var windows: [UsageWindow] = []

        if let percent = number(config["creditUsagePercent"])
            ?? number(config["usage_percentage"])
            ?? number(config["usagePercent"]) {
            windows.append(UsageWindow(id: "grok-weekly", label: "Weekly", usedPercent: percent, resetsAt: reset))
        }

        for product in config["productUsage"] as? [[String: Any]] ?? [] {
            guard let rawName = product["product"] as? String,
                  let percent = number(product["usagePercent"]) else { continue }
            let name: String
            switch rawName {
            case "GrokBuild": name = "Build"
            case "Api", "API": name = "API"
            case "GrokChat": name = "Chat"
            case "GrokImagine": name = "Imagine"
            default: name = rawName.replacingOccurrences(of: "Grok", with: "")
            }
            windows.append(UsageWindow(id: "grok-product-\(rawName)", label: name, usedPercent: percent, resetsAt: reset))
        }

        guard !windows.isEmpty else { throw UsageClientError.invalidResponse(.grok) }
        return windows
    }

    static func grokMonthly(_ data: Data) throws -> UsageWindow? {
        let root = try dictionary(data)
        let config = root["config"] as? [String: Any] ?? root
        let reset = date(config["billingPeriodEnd"])
            ?? date((config["currentPeriod"] as? [String: Any])?["end"])
            ?? date(root["period_end"])

        if let limit = nestedNumber(config["monthlyLimit"]),
           let used = nestedNumber(config["used"]), limit > 0 {
            return UsageWindow(id: "grok-monthly", label: "Monthly", usedPercent: used / limit * 100, resetsAt: reset)
        }
        if let percent = number(config["usage_percentage"]) ?? number(config["usagePercent"]) {
            return UsageWindow(id: "grok-monthly", label: "Monthly", usedPercent: percent, resetsAt: reset)
        }
        return nil
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse(.openAI)
        }
        return root
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func nestedNumber(_ value: Any?) -> Double? {
        if let number = number(value) { return number }
        guard let object = value as? [String: Any] else { return nil }
        return number(object["val"]) ?? number(object["value"])
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = int(value) { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = fractional.date(from: string) { return result }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func title(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func windowLabel(minutes: Int, fallback: String) -> String {
        switch minutes {
        case 300: "Session"
        case 10_080: "Weekly"
        default: fallback
        }
    }
}
