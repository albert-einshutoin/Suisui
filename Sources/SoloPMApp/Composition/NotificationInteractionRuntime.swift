import Foundation
import SoloPMCore
@preconcurrency import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    /// Posted when the user taps (default-activates) a digest-style
    /// notification so the app shell can bring the Project Board on screen.
    static let soloPMDigestNotificationOpened = Notification.Name("dev.solopm.digestNotificationOpened")
}

extension AppRuntimeFactory {
    static func makeDeadlineNotificationActionHandler() throws -> DeadlineNotificationActionHandler {
        let connection = try migratedConnection()
        return DeadlineNotificationActionHandler(
            taskStore: SQLiteTaskStore(connection: connection),
            notificationClient: UserNotificationsNotificationClient(),
            settings: loadRuntimeSettings().settings
        )
    }
}

/// Registers the actionable deadline notification category and routes
/// delivered notification actions (complete / snooze) into core handling.
final class SoloPMNotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SoloPMNotificationResponder()

    func install() {
        // UNUserNotificationCenter.current() aborts in bundle-less processes
        // (bare `swift run` debug binaries); notification actions only make
        // sense for real app-bundle launches anyway.
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let completeAction = UNNotificationAction(
            identifier: DeadlineNotificationInteraction.completeTaskActionIdentifier,
            title: localizedDisplay("Mark as Done"),
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: DeadlineNotificationInteraction.snoozeOneHourActionIdentifier,
            title: localizedDisplay("Remind Me in 1 Hour"),
            options: []
        )
        let taskCategory = UNNotificationCategory(
            identifier: DeadlineNotificationInteraction.taskCategoryIdentifier,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([taskCategory])
        center.delegate = self
    }

    // Deadline notifications stay useful while SoloPM is frontmost; a menu
    // bar app is "running" nearly all the time, so suppressing foreground
    // banners would hide most deadline alerts.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let content = response.notification.request.content
        let requestIdentifier = response.notification.request.identifier

        // Tapping a digest-style notification should land the user on the
        // Project Board, not just foreground a windowless app.
        if actionIdentifier == UNNotificationDefaultActionIdentifier,
           requestIdentifier.hasPrefix("solopm-daily-digest-")
               || requestIdentifier.hasPrefix("solopm-weekly-review-") {
#if canImport(AppKit)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .soloPMDigestNotificationOpened, object: nil)
            }
#endif
        }
        let userInfo = content.userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        // Store access and re-scheduling block on locks/semaphores; keep the
        // notification callback thread free and hand the work off.
        let completion = UncheckedSendableCompletion(run: completionHandler)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { completion.run() }
            guard let handler = try? AppRuntimeFactory.makeDeadlineNotificationActionHandler() else {
                return
            }
            let outcome = handler.handle(
                actionIdentifier: actionIdentifier,
                notificationTitle: content.title,
                notificationBody: content.body.isEmpty ? nil : content.body,
                userInfo: userInfo
            )
            if case .completedTask = outcome {
                DispatchQueue.main.async {
                    AppRuntimeFactory.postProjectBoardDidChange()
                }
            }
        }
    }
}

// UNUserNotificationCenter completion handlers are not marked Sendable in the
// overlay; the center guarantees single delivery, so hopping queues is safe.
private final class UncheckedSendableCompletion: @unchecked Sendable {
    let run: () -> Void

    init(run: @escaping () -> Void) {
        self.run = run
    }
}

#if canImport(AppKit)
/// Keeps the Dock icon badge in sync with the overdue task count so the
/// deadline debt is visible without opening any window.
@MainActor
final class DockTileBadgeController {
    static let shared = DockTileBadgeController()

    private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: .soloPMProjectBoardDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                DockTileBadgeController.shared.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let overdueCount: Int
            do {
                let provider = try SQLiteMenuBarSummaryProvider(
                    path: AppRuntimeFactory.applicationDatabaseURL().path
                )
                overdueCount = try provider.loadMenuBarSummary().overdueTaskCount
            } catch {
                overdueCount = 0
            }
            await MainActor.run {
                NSApp.dockTile.badgeLabel = overdueCount > 0 ? String(overdueCount) : nil
            }
        }
    }
}
#endif
