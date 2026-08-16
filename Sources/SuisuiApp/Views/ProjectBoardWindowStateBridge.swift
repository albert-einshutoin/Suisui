import AppKit
import SuisuiCore
import SwiftUI

/// A geometry-only AppKit edge for behavior SwiftUI scenes do not expose.
/// SwiftUI continues to own navigation and inspector state through
/// `SceneStorage`; this bridge persists only the backing window frame.
struct ProjectBoardWindowStateBridge: NSViewRepresentable {
    let sceneID: UUID
    let restoresPrimaryWindow: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneID: sceneID, restoresPrimaryWindow: restoresPrimaryWindow)
    }

    func makeNSView(context: Context) -> ProjectBoardWindowAttachmentView {
        let view = ProjectBoardWindowAttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: ProjectBoardWindowAttachmentView, context: Context) {
        context.coordinator.update(
            sceneID: sceneID,
            restoresPrimaryWindow: restoresPrimaryWindow
        )
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    static func dismantleNSView(
        _ nsView: ProjectBoardWindowAttachmentView,
        coordinator: Coordinator
    ) {
        nsView.onWindowChange = nil
        coordinator.detach(savingCurrentFrame: true)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var sceneID: UUID
        private var restoresPrimaryWindow: Bool
        private var observers: [NSObjectProtocol] = []
        private var pendingSave: Task<Void, Never>?
        private var hasRestoredCurrentWindow = false
        private let defaults: UserDefaults

        init(
            sceneID: UUID,
            restoresPrimaryWindow: Bool,
            defaults: UserDefaults = .standard
        ) {
            self.sceneID = sceneID
            self.restoresPrimaryWindow = restoresPrimaryWindow
            self.defaults = defaults
        }

        func update(sceneID: UUID, restoresPrimaryWindow: Bool) {
            if self.sceneID != sceneID {
                detach(savingCurrentFrame: true)
                self.sceneID = sceneID
            }
            guard self.restoresPrimaryWindow != restoresPrimaryWindow else { return }
            self.restoresPrimaryWindow = restoresPrimaryWindow
            // The root learns whether it owns the primary scene on appear.
            // Re-run restoration once when that stable role becomes available.
            if restoresPrimaryWindow, let window {
                hasRestoredCurrentWindow = false
                restoreFrameIfAvailable(on: window)
            }
        }

        func attach(to nextWindow: NSWindow?) {
            guard let nextWindow else {
                detach(savingCurrentFrame: true)
                return
            }
            guard window !== nextWindow else { return }
            detach(savingCurrentFrame: true)
            window = nextWindow
            restoreFrameIfAvailable(on: nextWindow)
            observe(nextWindow)
            if nextWindow.isKeyWindow {
                ProjectBoardSceneCoordinator.shared.markActive(sceneID: sceneID)
            }
        }

        func detach(savingCurrentFrame: Bool) {
            if savingCurrentFrame, let window {
                saveFrame(window.frame)
            }
            pendingSave?.cancel()
            pendingSave = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            window = nil
            hasRestoredCurrentWindow = false
        }

        private func restoreFrameIfAvailable(on window: NSWindow) {
            guard !hasRestoredCurrentWindow else { return }
            hasRestoredCurrentWindow = true
            window.minSize = NSSize(
                width: ProjectBoardWindowFrame.minimumWidth,
                height: ProjectBoardWindowFrame.minimumHeight
            )
            guard !isPresentationPersistenceDisabled else {
                return
            }
            let data = restoresPrimaryWindow
                ? defaults.data(forKey: primaryStorageKey) ?? defaults.data(forKey: storageKey)
                : defaults.data(forKey: storageKey)
            guard let data,
                  let state = ProjectBoardWindowPresentationState.decodeCurrent(from: data) else {
                return
            }
            let visibleFrames = NSScreen.screens.map { ProjectBoardWindowFrame($0.visibleFrame) }
            let frame = state.frame.sanitized(visibleFrames: visibleFrames)
            window.setFrame(frame.nsRect, display: false)
        }

        private func observe(_ window: NSWindow) {
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        self?.scheduleSave(frame: window.frame)
                    }
                })
            }
            observers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    ProjectBoardSceneCoordinator.shared.markActive(sceneID: self.sceneID)
                }
            })
            observers.append(center.addObserver(
                forName: .suisuiProjectBoardShortcutRequested,
                object: nil,
                queue: .main
            ) { [weak self, weak window] notification in
                guard let requestedSceneID = (
                    notification.object as? ProjectBoardShortcutRequest
                )?.sceneID else {
                    return
                }
                MainActor.assumeIsolated {
                    guard let self,
                          let window,
                          requestedSceneID == self.sceneID else {
                        return
                    }
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
            })
            observers.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    self?.saveFrame(window.frame)
                }
            })
        }

        private func scheduleSave(frame: NSRect) {
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                // Coalesce continuous drag notifications without scheduling a
                // layout correction on the run loop. The latest frame still
                // wins, while cancellation prevents stale geometry writes.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.saveFrame(frame)
            }
        }

        private func saveFrame(_ frame: NSRect) {
            guard !isPresentationPersistenceDisabled else {
                return
            }
            let state = ProjectBoardWindowPresentationState(frame: ProjectBoardWindowFrame(frame))
            guard let data = try? JSONEncoder().encode(state) else { return }
            defaults.set(data, forKey: storageKey)
            if restoresPrimaryWindow {
                // OS restoration stays disabled to avoid stale SwiftUI windows.
                // Only the first board uses this stable cross-launch fallback.
                defaults.set(data, forKey: primaryStorageKey)
            }
        }

        private var storageKey: String {
            "suisui.projectBoard.windowFrame.\(sceneID.uuidString)"
        }

        private var primaryStorageKey: String {
            "suisui.projectBoard.primaryWindowFrame"
        }

        private var isPresentationPersistenceDisabled: Bool {
            // Runtime evidence owns only its temporary process. Never read or
            // write the developer's actual window frame during those launches.
            ProcessInfo.processInfo.environment[
                "SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE"
            ] == "1"
        }
    }
}

final class ProjectBoardWindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private extension ProjectBoardWindowFrame {
    init(_ rect: NSRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}
