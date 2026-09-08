import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    @MainActor
    static func makeMenuBarSummaryController() -> MenuBarSummaryController {
        MenuBarSummaryController {
            do {
                return try SQLiteMenuBarSummaryProvider(path: applicationDatabaseURL().path)
            } catch {
                return UnavailableMenuBarSummaryProvider(error: error)
            }
        }
    }

    @MainActor
    static func makeMenuBarQuickCaptureController() -> MenuBarQuickCaptureController {
        MenuBarQuickCaptureController(
            storeFactory: {
                do {
                    let connection = try migratedConnection()
                    return SQLiteProjectBoardStore(connection: connection)
                } catch {
                    return UnavailableProjectBoardStore(error: error)
                }
            },
            onChange: postProjectBoardDidChange
        )
    }
}

private struct UnavailableMenuBarSummaryProvider: MenuBarSummaryProviding {
    let error: Error

    func loadMenuBarSummary() throws -> MenuBarSummary {
        throw error
    }
}
