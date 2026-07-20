import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    /// Collects the metadata-only diagnostics report exported from
    /// Settings > Privacy. Local data is read through COUNT queries only;
    /// content rows, Keychain secrets, and the audit log (which stores plan
    /// content) are never touched. See `DiagnosticsReportBuilder.privacyHeader`
    /// for the exclusion contract stated inside the report itself.
    static func makeDiagnosticsReportText(now: Date = Date()) -> String {
        var openTaskCount: Int?
        var completedTaskCountLast7Days: Int?
        var projectCount: Int?
        if let connection = try? migratedConnection() {
            let taskStore = SQLiteTaskStore(connection: connection)
            openTaskCount = try? taskStore.openCount()
            let iso8601 = ISO8601DateFormatter()
            let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
            completedTaskCountLast7Days = try? taskStore.completedCount(
                since: iso8601.string(from: sevenDaysAgo),
                until: iso8601.string(from: now)
            )
            projectCount = (try? SQLiteProjectStore(connection: connection).list())?.count
        }

        let watcher = makeWatcherDiagnosticsSnapshot()
        let iso8601 = ISO8601DateFormatter()
        let bundle = Bundle.main
        let input = DiagnosticsReportInput(
            settings: loadRuntimeSettings().settings,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            openTaskCount: openTaskCount,
            completedTaskCountLast7Days: completedTaskCountLast7Days,
            projectCount: projectCount,
            watcherLastCheck: watcher.lastCheckAt.map(iso8601.string(from:)),
            watcherNextCheck: watcher.nextCheckAt.map(iso8601.string(from:)),
            generatedAt: now
        )
        return DiagnosticsReportBuilder().makeReport(input: input)
    }
}
