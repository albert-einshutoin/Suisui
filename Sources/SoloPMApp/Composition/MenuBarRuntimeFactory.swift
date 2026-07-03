import Foundation
import SoloPMCore

extension AppRuntimeFactory {
    @MainActor
    static func makeMenuBarSummaryController() -> MenuBarSummaryController {
        do {
            let provider = try SQLiteMenuBarSummaryProvider(path: applicationDatabaseURL().path)
            let controller = MenuBarSummaryController(provider: provider)
            controller.refresh()
            return controller
        } catch {
            let controller = MenuBarSummaryController(provider: UnavailableMenuBarSummaryProvider(error: error))
            controller.refresh()
            return controller
        }
    }
}

private struct UnavailableMenuBarSummaryProvider: MenuBarSummaryProviding {
    let error: Error

    func loadMenuBarSummary() throws -> MenuBarSummary {
        throw error
    }
}
