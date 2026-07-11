import AVFoundation
import Foundation
import SoloPMCore

/// Reads the macOS microphone authorization status from `AVCaptureDevice` so
/// the onboarding permission snapshot can show the real `.granted` / `.denied`
/// state instead of falling back to `.notDetermined` for every user.
///
/// Core cannot import AVFoundation, so this adapter lives in the app
/// composition layer and is composed by `AppRuntimeFactory.makeIntegrationPermissionSnapshot`.
enum AVFoundationMicrophonePermissionSnapshotReader {
    static func snapshot(base: PermissionSnapshot = .empty) -> PermissionSnapshot {
        var snapshot = base
        snapshot.setStatus(permissionStatus(from: AVCaptureDevice.authorizationStatus(for: .audio)), for: .microphone)
        return snapshot
    }

    static func permissionStatus(from status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }
}
