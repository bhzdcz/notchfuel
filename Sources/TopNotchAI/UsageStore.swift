import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
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

    private var refreshTask: Task<Void, Never>?

    init() {
        displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .remaining
        let saved = UserDefaults.standard.stringArray(forKey: "enabledProviders") ?? []
        let providers = Set(saved.compactMap(ProviderID.init(rawValue:)))
        enabledProviders = providers.isEmpty ? Set(ProviderID.allCases) : providers
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
