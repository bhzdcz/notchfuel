import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindowController: NSObject {
    private let store: UsageStore
    private let updater: AppUpdater
    private let islandPanel: NSPanel
    private let presentation = IslandPresentation()
    private var layout: NotchLayout?
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(store: UsageStore, updater: AppUpdater) {
        self.store = store
        self.updater = updater
        islandPanel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func show() {
        reposition()
        islandPanel.orderFrontRegardless()
    }

    private func configurePanel() {
        islandPanel.isOpaque = false
        islandPanel.backgroundColor = .clear
        islandPanel.hasShadow = true
        islandPanel.hidesOnDeactivate = false
        islandPanel.isMovable = false
        islandPanel.becomesKeyOnlyIfNeeded = true
        islandPanel.acceptsMouseMovedEvents = true
        islandPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        islandPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    private func reposition() {
        guard let screen = targetScreen else { return }
        let nextLayout = NotchLayout(screen: screen)
        layout = nextLayout
        presentation.isExpanded = false
        islandPanel.setFrame(nextLayout.collapsedFrame, display: true)
        let container = NSView(
            frame: NSRect(origin: .zero, size: nextLayout.collapsedFrame.size)
        )
        container.autoresizingMask = [.width, .height]

        let hostingView = NSHostingView(
            rootView: DynamicIslandView(
                store: store,
                updater: updater,
                presentation: presentation,
                menuBarHeight: nextLayout.menuBarHeight,
                onHoverChanged: { [weak self] inside in
                    self?.hoverChanged(inside)
                }
            )
        )
        // The panel owns its animated size. Prevent SwiftUI's intrinsic-content
        // measurements from resizing the window during the island transition.
        hostingView.sizingOptions = []
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        islandPanel.contentView = container
    }

    private var targetScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    private func hoverChanged(_ isInside: Bool) {
        if isInside {
            collapseTask?.cancel()
            expand()
        } else {
            scheduleCollapse()
        }
    }

    private func expand() {
        guard !presentation.isExpanded, let layout else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            presentation.isExpanded = true
        }
        animatePanel(to: layout.expandedFrame, duration: 0.32)
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled, let self else { return }
            guard !self.isPointerInside else { return }
            self.collapse()
        }
    }

    private func collapse() {
        guard presentation.isExpanded, let layout else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            presentation.isExpanded = false
        }
        animatePanel(to: layout.collapsedFrame, duration: 0.28)
    }

    private var isPointerInside: Bool {
        islandPanel.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
    }

    private func animatePanel(to frame: NSRect, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            islandPanel.animator().setFrame(frame, display: true)
        }
    }
}

@MainActor
private final class IslandPresentation: ObservableObject {
    @Published var isExpanded = false
}

private struct NotchLayout {
    let menuBarHeight: CGFloat
    let notchWidth: CGFloat
    let collapsedFrame: NSRect
    let expandedFrame: NSRect

    init(screen: NSScreen) {
        let visibleMenuHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        menuBarHeight = min(44, max(34, max(screen.safeAreaInsets.top, visibleMenuHeight)))

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = min(280, max(180, right.minX - left.maxX))
        } else {
            notchWidth = 190
        }

        let collapsedWidth = notchWidth + 18
        let expandedWidth = min(560, screen.frame.width - 64)
        let expandedHeight: CGFloat = 286

        collapsedFrame = NSRect(
            x: screen.frame.midX - collapsedWidth / 2,
            y: screen.frame.maxY - menuBarHeight,
            width: collapsedWidth,
            height: menuBarHeight
        )
        expandedFrame = NSRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: screen.frame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
    }
}

private struct DynamicIslandView: View {
    @ObservedObject var store: UsageStore
    let updater: AppUpdater
    @ObservedObject var presentation: IslandPresentation
    let menuBarHeight: CGFloat
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            islandShape
                .fill(.black)
                .overlay {
                    islandShape.stroke(.white.opacity(presentation.isExpanded ? 0.10 : 0.04), lineWidth: 1)
                }
                .shadow(color: .black.opacity(presentation.isExpanded ? 0.35 : 0), radius: 18, y: 8)

            if presentation.isExpanded {
                ExpandedUsageView(store: store, updater: updater)
                    .padding(.top, menuBarHeight + 8)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
            } else {
                CollapsedNotchCue()
                    .transition(.opacity)
            }
        }
        .contentShape(islandShape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover(perform: onHoverChanged)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: presentation.isExpanded)
        .accessibilityElement(children: presentation.isExpanded ? .contain : .ignore)
        .accessibilityLabel(presentation.isExpanded ? "NotchFuel usage" : "Hover to show AI usage")
    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: presentation.isExpanded ? 26 : 14,
            bottomTrailingRadius: presentation.isExpanded ? 26 : 14,
            topTrailingRadius: 0,
            style: .continuous
        )
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct CollapsedNotchCue: View {
    var body: some View {
        HStack {
            Capsule()
                .fill(ProviderID.anthropic.color)
                .frame(width: 5, height: 14)
            Spacer()
            Capsule()
                .fill(ProviderID.openAI.color)
                .frame(width: 5, height: 14)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .opacity(0.85)
        .accessibilityHidden(true)
    }
}

private struct ExpandedUsageView: View {
    @ObservedObject var store: UsageStore
    let updater: AppUpdater

    var body: some View {
        VStack(spacing: 8) {
            header

            ForEach(ProviderID.allCases) { provider in
                CompactUsageRow(
                    provider: provider,
                    usage: store.usages[provider] ?? .loading(provider),
                    mode: store.displayMode
                )
            }

            footer
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            FuelBrandMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("NotchFuel")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Your AI runway")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Picker("Display", selection: $store.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 152)
            .colorScheme(.dark)

            notificationMenu

            Button {
                updater.checkForUpdates()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            .help("Check for NotchFuel updates")

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                        value: store.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            .disabled(store.isRefreshing)
        }
        .frame(height: 30)
    }

    private var notificationMenu: some View {
        Menu {
            Text("Notify when usage reaches")
            Divider()

            Button {
                store.setNotificationThreshold(nil)
            } label: {
                if store.notificationThreshold == nil {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }

            ForEach(UsageStore.notificationThresholdOptions, id: \.self) { threshold in
                Button {
                    store.setNotificationThreshold(threshold)
                } label: {
                    if store.notificationThreshold == threshold {
                        Label("\(threshold)% used", systemImage: "checkmark")
                    } else {
                        Text("\(threshold)% used")
                    }
                }
            }

            if store.notificationPermissionDenied {
                Divider()
                Text("Notifications are blocked in System Settings")
            }
        } label: {
            Image(systemName: notificationIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.notificationPermissionDenied ? .orange : .white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(notificationHelp)
    }

    private var notificationIcon: String {
        if store.notificationPermissionDenied { return "bell.slash.fill" }
        return store.notificationThreshold == nil ? "bell" : "bell.fill"
    }

    private var notificationHelp: String {
        guard let threshold = store.notificationThreshold else { return "Usage notifications are off" }
        return "Notify at \(threshold)% used"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text("Read-only · local")
            Spacer()
            Text(store.lastRefreshText)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit NotchFuel")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
        .frame(height: 15)
    }
}

private struct CompactUsageRow: View {
    let provider: ProviderID
    let usage: ProviderUsage
    let mode: DisplayMode

    var body: some View {
        HStack(spacing: 10) {
            Text(provider.shortName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 25, height: 25)
                .background(provider.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(provider.name)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 66, alignment: .leading)

            if usage.windows.isEmpty {
                Text(usage.message ?? provider.loginHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                Spacer()
            } else {
                ForEach(Array(usage.windows.prefix(2))) { window in
                    CompactMetric(window: window, provider: provider, mode: mode)
                }
                if usage.windows.count == 1 { Spacer() }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
    }
}

private struct CompactMetric: View {
    let window: UsageWindow
    let provider: ProviderID
    let mode: DisplayMode

    private var percentage: Double { window.percentage(for: mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(window.label)
                    .foregroundStyle(.white.opacity(0.48))
                Spacer(minLength: 2)
                Text("\(Int(percentage.rounded()))% \(mode.metricSuffix)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))

            FuelGauge(percentage: percentage, color: provider.color, segments: 8, height: 5)

            Text(window.resetText ?? "No reset time")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
