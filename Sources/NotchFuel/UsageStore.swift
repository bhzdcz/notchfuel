import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    static let notificationThresholdOptions = [50, 60, 70, 75, 80, 85, 90, 95]

    @Published var usages: [ProviderID: ProviderUsage] = Dictionary(
        uniqueKeysWithValues: ProviderID.allCases.map { ($0, .loading($0)) }
    )
    @Published var isRefreshing = false
    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode") }
    }
    @Published var enabledProviders: Set<ProviderID> {
        didSet { UserDefaults.standard.set(enabledProviders.map(\.rawValue), forKey: "enabledProviders") }
    }
    @Published private(set) var notificationThreshold: Int?
    @Published private(set) var notificationPermissionDenied = false

    private var refreshTask: Task<Void, Never>?
    private let notificationManager = UsageNotificationManager()
    private var deliveredAlertIDs: Set<String>

    init() {
        displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .remaining
        let saved = UserDefaults.standard.stringArray(forKey: "enabledProviders") ?? []
        let providers = Set(saved.compactMap(ProviderID.init(rawValue:)))
        enabledProviders = providers.isEmpty ? Set(ProviderID.allCases) : providers
        let savedThreshold = UserDefaults.standard.integer(forKey: "notificationThreshold")
        notificationThreshold = savedThreshold > 0 ? savedThreshold : nil
        deliveredAlertIDs = Set(UserDefaults.standard.stringArray(forKey: "deliveredAlertIDs") ?? [])
    }

    deinit { refreshTask?.cancel() }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: ProviderUsage.self) { group in
            for provider in ProviderID.allCases {
                group.addTask { await UsageService.fetch(provider) }
            }
            for await usage in group { usages[usage.provider] = usage }
        }
        await evaluateUsageAlerts()
    }

    func setNotificationThreshold(_ threshold: Int?) {
        notificationThreshold = threshold
        if let threshold {
            UserDefaults.standard.set(threshold, forKey: "notificationThreshold")
        } else {
            UserDefaults.standard.removeObject(forKey: "notificationThreshold")
        }
        deliveredAlertIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "deliveredAlertIDs")
        notificationPermissionDenied = false

        guard threshold != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let granted = await notificationManager.requestAuthorization()
            notificationPermissionDenied = !granted
            if granted { await evaluateUsageAlerts() }
        }
    }

    private func evaluateUsageAlerts() async {
        guard let threshold = notificationThreshold else { return }
        let alerts = UsageLimitAlertPolicy.alerts(
            in: usages,
            threshold: threshold,
            excluding: deliveredAlertIDs
        )
        guard !alerts.isEmpty else { return }

        let authorized = await notificationManager.isAuthorized()
        notificationPermissionDenied = !authorized
        guard authorized else { return }

        for alert in alerts {
            await notificationManager.deliver(alert)
            deliveredAlertIDs.insert(alert.id)
        }
        UserDefaults.standard.set(Array(deliveredAlertIDs), forKey: "deliveredAlertIDs")
    }

    func toggle(_ provider: ProviderID) {
        if enabledProviders.contains(provider) {
            guard enabledProviders.count > 1 else { return }
            enabledProviders.remove(provider)
        } else {
            enabledProviders.insert(provider)
        }
    }

    var menuBarText: String {
        ProviderID.allCases.compactMap { provider in
            guard enabledProviders.contains(provider),
                  let window = usages[provider]?.mostConstrained else { return nil }
            return "\(provider.shortName) \(Int(window.percentage(for: displayMode).rounded()))%"
        }.joined(separator: "  ·  ")
    }

    var lastRefreshText: String {
        let dates = usages.values.map(\.refreshedAt).filter { $0 != .distantPast }
        guard let latest = dates.max() else { return "Not refreshed yet" }
        return "Updated \(latest.formatted(.relative(presentation: .named)))"
    }
}
