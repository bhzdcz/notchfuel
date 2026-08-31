import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @State private var showSources = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(ProviderID.allCases) { provider in
                        ProviderCard(
                            provider: provider,
                            usage: store.usages[provider] ?? .loading(provider),
                            mode: store.displayMode,
                            isVisible: store.enabledProviders.contains(provider),
                            onToggle: { store.toggle(provider) }
                        )
                    }
                }
                .padding(12)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 390, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TopNotch AI")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Your AI headroom, at a glance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                        .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("Refresh now")
            }

            Picker("Display", selection: $store.displayMode) {
                ForEach(DisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "lock.shield")
            Text("Read-only · local")
            Spacer()
            Text(store.lastRefreshText)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit TopNotch AI")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
}

private struct ProviderCard: View {
    let provider: ProviderID
    let usage: ProviderUsage
    let mode: DisplayMode
    let isVisible: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(provider.color.gradient)
                    Text(provider.shortName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name).font(.system(size: 14, weight: .semibold))
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onToggle) {
                    Image(systemName: isVisible ? "menubar.rectangle" : "rectangle.slash")
                        .foregroundStyle(isVisible ? provider.color : .secondary)
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "Shown in menu bar" : "Hidden from menu bar")
            }

            if usage.windows.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: usage.message == "Refreshing…" ? "hourglass" : "exclamationmark.circle")
                    Text(usage.message ?? provider.loginHint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                ForEach(usage.windows.prefix(4)) { window in
                    MetricRow(window: window, provider: provider, mode: mode)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var summary: String {
        if let message = usage.message { return message }
        return "\(usage.windows.count) limit\(usage.windows.count == 1 ? "" : "s") available"
    }
}

private struct MetricRow: View {
    let window: UsageWindow
    let provider: ProviderID
    let mode: DisplayMode

    private var value: Double { window.percentage(for: mode) }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let reset = window.resetText {
                    Text(reset)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("\(Int(value.rounded()))% \(mode == .used ? "used" : "left")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(provider.color.gradient)
                        .frame(width: proxy.size.width * value / 100)
                }
            }
            .frame(height: 6)
            .accessibilityLabel("\(window.label), \(Int(value.rounded())) percent \(mode.rawValue.lowercased())")
        }
    }
}
