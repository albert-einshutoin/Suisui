import Foundation
import SoloPMCore

/// Non-closure wrapper for the sample-project action. Using a struct (instead
/// of a bare function-typed parameter) keeps the new defaulted
/// `OnboardingWelcomeView` init parameter from ever capturing the existing
/// trailing `onFinish:` closure at the pinned SoloPMApp.swift call site.
struct OnboardingSampleProjectAction {
    let run: @Sendable () throws -> Void
}

/// Wires the real SQLite-backed sample creator into onboarding. The database
/// connection is opened at tap time, not when the sheet is constructed.
enum OnboardingSampleProjectFactory {
    static func makeAction() -> OnboardingSampleProjectAction {
        OnboardingSampleProjectAction {
            let connection = try AppRuntimeFactory.migratedConnection()
            let creator = OnboardingSampleProjectCreator(
                projectStore: SQLiteProjectStore(connection: connection),
                taskStore: SQLiteTaskStore(connection: connection),
                localize: { localizedDisplay($0) }
            )
            _ = try creator.createSampleProjectIfNeeded()
        }
    }
}
