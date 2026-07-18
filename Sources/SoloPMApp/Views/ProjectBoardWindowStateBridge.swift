import AppKit
import SoloPMCore
import SwiftUI

/// A geometry-only AppKit edge for behavior SwiftUI scenes do not expose.
/// SwiftUI continues to own navigation and inspector state through
/// `SceneStorage`; this bridge persists only the backing window frame.
struct ProjectBoardWindowStateBridge: NSViewRepresentable {
    let sceneID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneID: sceneID)
    }

    func makeNSView(context: Context) -> ProjectBoardWindowAttachmentView {
        let view = ProjectBoardWindowAttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: ProjectBoardWindowAttachmentView, context: Context) {
        context.coordinator.update(sceneID: sceneID)
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
        private var observers: [NSObjectProtocol] = []
        private var pendingSave: DispatchWorkItem?
        private var hasRestoredCurrentWindow = false
        private let defaults: UserDefaults

        init(sceneID: UUID, defaults: UserDefaults = .standard) {
            self.sceneID = sceneID
            self.defaults = defaults
        }

        func update(sceneID: UUID) {
            guard self.sceneID != sceneID else { return }
            detach(savingCurrentFrame: true)
            self.sceneID = sceneID
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
            guard let data = defaults.data(forKey: storageKey),
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
            let item = DispatchWorkItem { [weak self] in
                self?.saveFrame(frame)
            }
            pendingSave = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }

        private func saveFrame(_ frame: NSRect) {
            let state = ProjectBoardWindowPresentationState(frame: ProjectBoardWindowFrame(frame))
            guard let data = try? JSONEncoder().encode(state) else { return }
            defaults.set(data, forKey: storageKey)
        }

        private var storageKey: String {
            "solopm.projectBoard.windowFrame.\(sceneID.uuidString)"
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
