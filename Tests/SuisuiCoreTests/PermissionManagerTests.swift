import XCTest
@testable import SuisuiCore

final class PermissionManagerTests: XCTestCase {
    func testStaticPermissionManagerReturnsSharedPermissionSnapshot() {
        var snapshot = PermissionSnapshot.empty
        snapshot.setStatus(.granted, for: .calendar)
        snapshot.setStatus(.denied, for: .notifications)
        let manager = StaticPermissionManager(snapshot: snapshot)

        XCTAssertEqual(manager.status(for: .calendar), .granted)
        XCTAssertEqual(manager.snapshot().status(for: .notifications), .denied)
    }

    func testPermissionDisplayPolicyDisablesDeniedAndRestrictedStates() {
        XCTAssertFalse(PermissionDisplayPolicy.isActionDisabled(for: .notDetermined))
        XCTAssertFalse(PermissionDisplayPolicy.isActionDisabled(for: .granted))
        XCTAssertTrue(PermissionDisplayPolicy.isActionDisabled(for: .denied))
        XCTAssertTrue(PermissionDisplayPolicy.isActionDisabled(for: .restricted))
        XCTAssertEqual(PermissionDisplayPolicy.label(for: .denied), "Denied")
    }

    func testPermissionDisplayPolicyMapsIntegrationConnectionStatus() {
        XCTAssertEqual(PermissionDisplayPolicy.integrationStatusLabel(for: .notDetermined), "Not configured")
        XCTAssertEqual(PermissionDisplayPolicy.integrationStatusLabel(for: .granted), "Connected")
        XCTAssertEqual(PermissionDisplayPolicy.integrationStatusLabel(for: .denied), "Permission denied")
        XCTAssertEqual(PermissionDisplayPolicy.integrationStatusLabel(for: .restricted), "Restricted")
    }
}
