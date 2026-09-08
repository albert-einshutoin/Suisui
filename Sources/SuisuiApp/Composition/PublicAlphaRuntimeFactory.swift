import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    static func makePublicAlphaMeasurement() throws -> PublicAlphaRuntimeMeasurement {
        let defaults = UserDefaults.standard
        let seedKey = "suisui.publicAlphaParticipantSeed"
        let seed: String
        if let existing = defaults.string(forKey: seedKey) {
            seed = existing
        } else {
            seed = UUID().uuidString
            defaults.set(seed, forKey: seedKey)
        }
        let build = try? PublicAlphaBuildIdentity(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            sourceCommit: Bundle.main.object(forInfoDictionaryKey: "SuisuiSourceCommit") as? String ?? ""
        )
        return try PublicAlphaRuntimeMeasurement(
            url: applicationSupportDirectoryURL().appendingPathComponent("PublicAlphaValidation/ledger.json"),
            participantSeed: seed,
            build: build,
            isEnabled: { UserDefaults.standard.bool(forKey: "suisui.publicAlphaMeasurementEnabled") }
        )
    }

    static func deletePublicAlphaMeasurement() throws {
        try makePublicAlphaMeasurement().deleteParticipant()
        UserDefaults.standard.set(false, forKey: "suisui.publicAlphaMeasurementEnabled")
        UserDefaults.standard.set(UUID().uuidString, forKey: "suisui.publicAlphaParticipantSeed")
    }

    static func recordPublicAlphaResultDisplayed(receiptID: String) {
        guard let measurement = try? makePublicAlphaMeasurement(),
              let reference = try? measurement.workReference(sourceID: receiptID, stage: .localExecution)
        else { return }
        measurement.record(.resultDisplayed, mark: .completed, sourceID: receiptID, workReference: reference)
    }
}
