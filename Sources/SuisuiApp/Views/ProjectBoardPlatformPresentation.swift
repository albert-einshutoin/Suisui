import SuisuiCore
import SwiftUI
import os
#if canImport(AppKit)
import AppKit
#endif

private struct ProjectBoardSynchronizedColumnBounds: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func projectBoardSynchronizedColumnBounds() -> some View {
        modifier(ProjectBoardSynchronizedColumnBounds())
    }
}

struct ProjectBoardTodayRefreshLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var boundaryRefreshTask: Task<Void, Never>?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        // Keep time-driven refreshes outside ProjectBoardView's already-large
        // modifier chain so Swift can type-check the view while the live app
        // still crosses day, timezone, locale, and activation boundaries.
        content
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onAppear {
                scheduleBoundaryRefreshIfActive()
            }
            .onDisappear {
                cancelBoundaryRefresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    cancelBoundaryRefresh()
                    return
                }
                refreshAndRescheduleBoundary()
            }
    }

    private func refreshAndRescheduleBoundary() {
        guard scenePhase == .active else {
            return
        }
        refresh()
        scheduleBoundaryRefreshIfActive()
    }

    private func scheduleBoundaryRefreshIfActive() {
        cancelBoundaryRefresh()
        guard scenePhase == .active else {
            return
        }

        let boundary = DailyPlanningReviewRefreshSchedule.nextStrictBoundary(
            after: Date(),
            calendar: .current
        )
        let nanoseconds = UInt64(max(boundary.timeIntervalSinceNow, 0) * 1_000_000_000)
        boundaryRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, scenePhase == .active else {
                return
            }

            refresh()
            scheduleBoundaryRefreshIfActive()
        }
    }

    private func cancelBoundaryRefresh() {
        boundaryRefreshTask?.cancel()
        boundaryRefreshTask = nil
    }
}

#if canImport(AppKit)
struct ProjectBoardToolbarLayoutBridge: NSViewRepresentable {
    let columnVisibility: NavigationSplitViewVisibility
    let onToolbarLayoutChanged: () -> Void
    let onWindowWidthChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProjectBoardToolbarLayoutBridgeView(frame: .zero)
        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.onWindowWidthChanged = onWindowWidthChanged
        view.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = columnVisibility
        guard let view = nsView as? ProjectBoardToolbarLayoutBridgeView else {
            return
        }

        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.onWindowWidthChanged = onWindowWidthChanged
        view.installToolbarDisplayModeObservationIfNeeded()
        view.installToolbarDisplayModeMenuPruningIfNeeded()
        view.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
    }
}

private final class ProjectBoardToolbarLayoutBridgeView: NSView {
    var onToolbarLayoutChanged: (() -> Void)?
    var onWindowWidthChanged: ((CGFloat) -> Void)?
    private let runtimeDiagnosticLogger = Logger(subsystem: "dev.suisui.app", category: "runtime")
    private weak var observedToolbar: NSToolbar?
    private var toolbarDisplayModeObservation: NSKeyValueObservation?
    private var isToolbarDisplayModeMenuPruningInstalled = false
    private var observedToolbarDisplayMode: NSToolbar.DisplayMode?
    private var isPerformingToolbarLayoutPass = false
    private var toolbarLayoutReconcileDepth = 0
    private var toolbarLayoutMaxDepth = 0
    private var didScheduleInitialToolbarLayoutStabilization = false
    private var observedWindowWidth: CGFloat?
    private var reportedContentLayoutSize: NSSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enforceProjectBoardWindowMinimumSize()
        reportWindowWidthIfChanged()
        installToolbarDisplayModeObservationIfNeeded()
        installToolbarDisplayModeMenuPruningIfNeeded()
        reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
        scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded()
    }

    override func layout() {
        super.layout()
        enforceProjectBoardWindowMinimumSize()
        reportWindowWidthIfChanged()
        reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
    }

    private func reportWindowWidthIfChanged() {
        guard let width = window?.frame.width, width != observedWindowWidth else {
            return
        }
        observedWindowWidth = width
        onWindowWidthChanged?(width)
    }

    private func enforceProjectBoardWindowMinimumSize() {
        guard let window else {
            return
        }

        // AX-driven resizes can bypass SwiftUI's content fitting constraint.
        // The product contract is expressed in content coordinates; titlebar
        // and toolbar height vary per window and must not consume the usable
        // 960x572 board area.
        let minimumContentSize = NSSize(
            width: ProjectBoardWindowMetrics.minWidth,
            height: ProjectBoardWindowMetrics.minHeight
        )
        if window.contentMinSize != minimumContentSize {
            window.contentMinSize = minimumContentSize
        }

        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size
        if window.minSize != minimumFrameSize {
            window.minSize = minimumFrameSize
        }

        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let constrainedContentSize = NSSize(
            width: max(currentContentRect.width, minimumContentSize.width),
            height: max(currentContentRect.height, minimumContentSize.height)
        )
        guard constrainedContentSize != currentContentRect.size else {
            reportContentLayoutSizeIfRequested(window)
            return
        }

        var constrainedFrame = window.frameRect(
            forContentRect: NSRect(origin: currentContentRect.origin, size: constrainedContentSize)
        )
        // Growing upward preserves the titlebar position and avoids moving a
        // window under the pointer while toolbar reconciliation is re-entered.
        constrainedFrame.origin.x = window.frame.minX
        constrainedFrame.origin.y = window.frame.maxY - constrainedFrame.height
        window.setFrame(constrainedFrame, display: true)
        reportContentLayoutSizeIfRequested(window)
    }

    private func reportContentLayoutSizeIfRequested(_ window: NSWindow) {
        guard let rawPath = ProcessInfo.processInfo.environment[
            "SUISUI_LAYOUT_STABILITY_WINDOW_CONTENT_SIZE_PATH"
        ], rawPath.isEmpty == false else {
            return
        }

        let contentLayoutSize = window.contentLayoutRect.size
        guard contentLayoutSize != reportedContentLayoutSize else {
            return
        }
        reportedContentLayoutSize = contentLayoutSize

        // Runtime layout evidence needs the usable content size after titlebar
        // and toolbar subtraction. Production runs do no file I/O because the
        // opt-in evidence path is absent.
        let payload = "\(Int(contentLayoutSize.width.rounded())) \(Int(contentLayoutSize.height.rounded()))\n"
        try? payload.write(
            toFile: rawPath,
            atomically: true,
            encoding: .utf8
        )
    }

    @discardableResult
    private func removeNativeSidebarToggle(in toolbar: NSToolbar) -> Bool {
        let removalIndexes = ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes(
            in: toolbar.projectBoardLayoutItems
        )
        guard removalIndexes.isEmpty == false else {
            return false
        }

        // Keep toolbar display modes user-adaptive; only remove the native
        // sidebar item and tracking separator that visually drift in this
        // SwiftUI-hosted split view.
        for index in removalIndexes.reversed() {
            toolbar.removeItem(at: index)
        }
        return true
    }

    func installToolbarDisplayModeObservationIfNeeded() {
        guard let toolbar = window?.toolbar,
              observedToolbar !== toolbar else {
            return
        }

        _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
        toolbarDisplayModeObservation?.invalidate()
        observedToolbar = toolbar
        observedToolbarDisplayMode = toolbar.displayMode
        toolbarDisplayModeObservation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, _ in
            guard let self else {
                return
            }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.reconcileToolbarDisplayModeChange()
                }
            } else {
                DispatchQueue.main.async {
                    self.reconcileToolbarDisplayModeChange()
                }
            }
        }
    }

    private func scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded() {
        guard didScheduleInitialToolbarLayoutStabilization == false else {
            return
        }

        didScheduleInitialToolbarLayoutStabilization = true
        for delay in [0.05, 0.25, 0.75] {
            // layout-attachment-delay: initial AppKit toolbar attachment gap.
            // SwiftUI can attach the bridge before NSToolbar items exist; this
            // bounded startup sampling is the only delayed correction allowed
            // by ADR 0009, and user-triggered display-mode/sidebar changes
            // mutate the toolbar synchronously without forcing a full view-tree layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
            }
        }
    }

    private func reconcileToolbarDisplayModeChange() {
        guard let toolbar = observedToolbar ?? window?.toolbar,
              observedToolbarDisplayMode != toolbar.displayMode else {
            return
        }

        _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
        observedToolbarDisplayMode = toolbar.displayMode
        reconcileProjectBoardToolbarLayout(
            allowRetryIfToolbarMissing: false,
            notifyColumnsWhenToolbarAlreadyStable: true
        )
    }

    @discardableResult
    private func enforceProjectBoardSupportedToolbarDisplayMode(_ toolbar: NSToolbar) -> Bool {
        let supportedDisplayMode = projectBoardSupportedToolbarDisplayMode(for: toolbar.displayMode)
        guard toolbar.displayMode != supportedDisplayMode else {
            return false
        }

        toolbar.displayMode = supportedDisplayMode
        return true
    }

    private func projectBoardSupportedToolbarDisplayMode(for displayMode: NSToolbar.DisplayMode) -> NSToolbar.DisplayMode {
        switch displayMode {
        case .iconAndLabel:
            return .iconAndLabel
        case .iconOnly:
            return .iconOnly
        case .labelOnly, .default:
            // Text-only toolbar buttons collapse the icon anchors that the
            // Project Board header uses for stable scan order. Prefer the
            // full label mode when AppKit asks for an unsupported display mode.
            return .iconAndLabel
        @unknown default:
            return .iconAndLabel
        }
    }

    func installToolbarDisplayModeMenuPruningIfNeeded() {
        guard isToolbarDisplayModeMenuPruningInstalled == false else {
            return
        }

        isToolbarDisplayModeMenuPruningInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(projectBoardToolbarMenuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    @objc private func projectBoardToolbarMenuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              window != nil else {
            return
        }

        pruneUnsupportedProjectBoardToolbarDisplayModeItems(from: menu)
    }

    private func pruneUnsupportedProjectBoardToolbarDisplayModeItems(from menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                pruneUnsupportedProjectBoardToolbarDisplayModeItems(from: submenu)
            }
        }

        guard isProjectBoardToolbarDisplayModeMenu(menu) else {
            return
        }

        let unsupportedTitles = Set(["Text Only", "テキストのみ"])
        for item in menu.items.reversed() where unsupportedTitles.contains(item.title) {
            // AppKit builds toolbar display-mode menus lazily and does not
            // expose a public allowed-display-modes API. Remove only the
            // unsupported text-only item so users keep the two stable modes.
            menu.removeItem(item)
        }
    }

    private func isProjectBoardToolbarDisplayModeMenu(_ menu: NSMenu) -> Bool {
        let itemTitles = Set(menu.items.map(\.title))
        let hasIconAndTextMode = itemTitles.contains("Icon and Text") || itemTitles.contains("アイコンとテキスト")
        let hasIconOnlyMode = itemTitles.contains("Icon Only") || itemTitles.contains("アイコンのみ")
        return hasIconAndTextMode && hasIconOnlyMode
    }

    func reconcileProjectBoardToolbarLayout(
        allowRetryIfToolbarMissing: Bool,
        notifyColumnsWhenToolbarAlreadyStable: Bool = false
    ) {
        enforceProjectBoardWindowMinimumSize()
        // Record re-entry before the existing boolean guard returns. This keeps
        // nested attempts observable without allowing nested toolbar mutation.
        toolbarLayoutReconcileDepth += 1
        toolbarLayoutMaxDepth = max(toolbarLayoutMaxDepth, toolbarLayoutReconcileDepth)
        runtimeDiagnosticLogger.notice(
            "suisui.toolbar.layout.maxDepth=\(self.toolbarLayoutMaxDepth, privacy: .public)"
        )
        defer { toolbarLayoutReconcileDepth -= 1 }

        guard isPerformingToolbarLayoutPass == false else {
            return
        }

        guard toolbarLayoutReconcileDepth == 1 else {
            return
        }

        guard let toolbar = window?.toolbar else {
            if allowRetryIfToolbarMissing {
                retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: 6)
            }
            return
        }

        isPerformingToolbarLayoutPass = true
        defer { isPerformingToolbarLayoutPass = false }

        var didMutateToolbar = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            if window?.titleVisibility != .hidden {
                window?.titleVisibility = .hidden
                didMutateToolbar = true
            }
            if toolbar.centeredItemIdentifier != nil {
                toolbar.centeredItemIdentifier = nil
                didMutateToolbar = true
            }
            didMutateToolbar = enforceProjectBoardSupportedToolbarDisplayMode(toolbar) || didMutateToolbar
            didMutateToolbar = removeNativeSidebarToggle(in: toolbar) || didMutateToolbar
        }

        if didMutateToolbar {
            markProjectBoardWindowLayoutDirty()
        }

        if didMutateToolbar || notifyColumnsWhenToolbarAlreadyStable {
            // NSToolbar display-mode changes come from AppKit context menus,
            // outside SwiftUI state. Bump SwiftUI state only when the toolbar
            // actually changed; forcing contentView layout here recursively
            // size-fits the whole Project Board and stalls packaged app launch.
            onToolbarLayoutChanged?()
        }
    }

    private func markProjectBoardWindowLayoutDirty() {
        window?.contentView?.needsLayout = true
        window?.contentView?.needsDisplay = true
    }

    private func retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            return
        }

        // SwiftUI may attach the NSToolbar after the representable enters the
        // window, and its toolbar items can arrive shortly after the toolbar
        // itself. Retry only for that initial attachment gap; user-triggered
        // display-mode/sidebar changes run synchronously once the toolbar exists.
        // layout-attachment-delay: initial AppKit toolbar attachment gap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else {
                return
            }

            self.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
            if self.window?.toolbar == nil {
                self.retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: remainingAttempts - 1)
            }
        }
    }

}

private extension NSToolbar {
    var projectBoardLayoutItems: [ProjectBoardToolbarLayoutPolicy.Item] {
        items.map(\.projectBoardLayoutItem)
    }
}

private extension NSToolbarItem {
    var projectBoardLayoutItem: ProjectBoardToolbarLayoutPolicy.Item {
        ProjectBoardToolbarLayoutPolicy.Item(
            identifierRawValue: itemIdentifier.rawValue,
            label: label,
            paletteLabel: paletteLabel,
            toolTip: toolTip,
            accessibilityIdentifier: view?.accessibilityIdentifier(),
            isNativeToggleAction: action == #selector(NSSplitViewController.toggleSidebar(_:))
        )
    }
}
#else
struct ProjectBoardToolbarLayoutBridge: View {
    let columnVisibility: NavigationSplitViewVisibility
    let onToolbarLayoutChanged: () -> Void
    let onWindowWidthChanged: (CGFloat) -> Void

    var body: some View {
        EmptyView()
    }
}
#endif
