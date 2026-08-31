import Foundation
import Testing
@testable import NotchFuel

struct UsageParsersTests {
    @Test func parsesCurrentAnthropicLimits() throws {
        let data = Data(#"{"limits":[{"kind":"session","percent":21,"resets_at":"2030-01-01T05:00:00Z"},{"kind":"weekly_all","percent":71,"resets_at":"2030-01-07T00:00:00Z"}]}"#.utf8)
        let result = try UsageParsers.anthropic(data)
        #expect(result.map(\.label) == ["Session", "Weekly"])
        #expect(result.map(\.usedPercent) == [21, 71])
    }

    @Test func parsesLegacyAnthropicLimits() throws {
        let data = Data(#"{"five_hour":{"utilization":12.5},"seven_day":{"utilization":44}}"#.utf8)
        let result = try UsageParsers.anthropic(data)
        #expect(result.count == 2)
        #expect(result[0].usedPercent == 12.5)
    }

    @Test func parsesOpenAIWindows() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":34,"reset_after_seconds":1800,"window_minutes":300},"secondary_window":{"used_percent":9,"reset_after_seconds":90000,"window_minutes":10080}}}"#.utf8)
        let result = try UsageParsers.openAI(data)
        #expect(result.map(\.label) == ["Session", "Weekly"])
        #expect(result.map(\.usedPercent) == [34, 9])
    }

    @Test func parsesCodexSessionFallbackShape() throws {
        let data = Data(#"{"rate_limits":{"primary":{"used_percent":2,"window_minutes":300,"resets_at":1893456000},"secondary":{"used_percent":8,"window_minutes":10080,"resets_at":1894060800}}}"#.utf8)
        let result = try UsageParsers.openAI(data)
        #expect(result.count == 2)
        #expect(result[1].label == "Weekly")
    }

    @Test func parsesGrokCreditsAndMonthly() throws {
        let credits = Data(#"{"config":{"creditUsagePercent":29,"billingPeriodEnd":"2030-01-07T00:00:00Z","productUsage":[{"product":"GrokBuild","usagePercent":18}]}}"#.utf8)
        let monthly = Data(#"{"config":{"monthlyLimit":{"val":200},"used":{"val":50}}}"#.utf8)
        let result = try UsageParsers.grokCredits(credits)
        let month = try UsageParsers.grokMonthly(monthly)
        #expect(result.map(\.label) == ["Weekly", "Build"])
        #expect(month?.usedPercent == 25)
    }

    @Test func switchesBetweenRemainingAndUsed() {
        let window = UsageWindow(id: "test", label: "Test", usedPercent: 27)
        #expect(window.percentage(for: .remaining) == 73)
        #expect(window.percentage(for: .used) == 27)
    }
}
