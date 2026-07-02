import Foundation
import CryptoKit

public enum SubscriptionPlan: String, Codable, CaseIterable, Equatable, Sendable {
    case free
    case sync
    case pro
    case founder

    public var displayName: String {
        switch self {
        case .free:
            "Free"
        case .sync:
            "Sync"
        case .pro:
            "Pro"
        case .founder:
            "Founder"
        }
    }

    public func allows(_ feature: FeatureGate) -> Bool {
        rank >= feature.requiredPlan.rank
    }

    private var rank: Int {
        switch self {
        case .free:
            0
        case .sync:
            1
        case .pro:
            2
        case .founder:
            3
        }
    }
}

public enum FeatureGate: String, Codable, CaseIterable, Equatable, Sendable {
    case externalSync
    case advancedMCPExecution
    case cloudRelay
    case hostedMCPEndpoint
    case documentScopedAutomation
    case harnessHistory
    case externalConnectorWrite
    case providerPresets

    public var requiredPlan: SubscriptionPlan {
        switch self {
        case .externalSync:
            .sync
        case .advancedMCPExecution,
             .cloudRelay,
             .hostedMCPEndpoint,
             .documentScopedAutomation,
             .harnessHistory,
             .externalConnectorWrite,
             .providerPresets:
            // External execution and cloud automation carry ongoing security,
            // audit, and support cost, so they stay above the personal Sync tier.
            .pro
        }
    }
}

public struct EntitlementSnapshot: Equatable, Sendable {
    public var plan: SubscriptionPlan
    public var source: EntitlementSource

    public init(plan: SubscriptionPlan, source: EntitlementSource) {
        self.plan = plan
        self.source = source
    }
}

public enum EntitlementSource: String, Equatable, Sendable {
    case defaultFree
    case localLicense
    case invalidLocalLicense
}

public protocol EntitlementStore: Sendable {
    func snapshot() throws -> EntitlementSnapshot
}

public enum EntitlementError: Error, Equatable, Sendable {
    case upgradeRequired(feature: FeatureGate, requiredPlan: SubscriptionPlan)
}

public struct EntitlementChecker: Sendable {
    private let store: any EntitlementStore

    public init(store: any EntitlementStore) {
        self.store = store
    }

    public func require(_ feature: FeatureGate) throws {
        let snapshot = try store.snapshot()
        guard snapshot.plan.allows(feature) else {
            throw EntitlementError.upgradeRequired(feature: feature, requiredPlan: feature.requiredPlan)
        }
    }
}

public protocol LocalLicenseVerifier: Sendable {
    func plan(for licenseText: String) -> SubscriptionPlan?
}

public struct NoBundledLocalLicenseVerifier: LocalLicenseVerifier {
    public init() {}

    public func plan(for licenseText: String) -> SubscriptionPlan? {
        nil
    }
}

public struct SignedLocalLicenseVerifier: LocalLicenseVerifier {
    private let publicKey: Curve25519.Signing.PublicKey?
    private let validator: LocalLicenseValidator

    public init(publicKeyBase64: String, validator: LocalLicenseValidator = LocalLicenseValidator()) {
        if let publicKeyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)) {
            publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } else {
            publicKey = nil
        }
        self.validator = validator
    }

    public func plan(for licenseText: String) -> SubscriptionPlan? {
        guard let publicKey,
              let data = licenseText.data(using: .utf8) else {
            return nil
        }

        let result = validator.validate(data: data)
        guard case .valid = result.status,
              let license = result.license,
              let signatureText = license.signature?.trimmingCharacters(in: .whitespacesAndNewlines),
              let signature = Data(base64Encoded: signatureText),
              publicKey.isValidSignature(signature, for: Self.signingPayload(for: license)) else {
            return nil
        }

        switch license.plan {
        case .free:
            return .free
        case .personalPlus:
            // Personal Plus is a legacy paid personal SKU. It maps to Pro so old
            // local licenses keep external connector writes without inventing a
            // second entitlement tier that the pricing gate cannot express.
            return .pro
        case .founder:
            // Founder is documented as Pro during early access with extra support
            // metadata, so it must outrank Pro while preserving approval gates.
            return .founder
        }
    }

    public static func signingPayload(for license: LocalLicense) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expiresAt = license.expiresAt.map { formatter.string(from: $0) } ?? "-"
        let fields = [
            license.id,
            license.plan.rawValue,
            formatter.string(from: license.issuedAt),
            expiresAt
        ] + license.features.sorted()

        // Each field is length-framed so a license with one comma-containing
        // feature cannot share the same signature payload as multiple features.
        return Data(fields.map(framedField).joined(separator: "|").utf8)
    }

    private static func framedField(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}

public struct KeychainEntitlementStore: EntitlementStore {
    private let secretStore: any SecretStore
    private let verifier: any LocalLicenseVerifier

    public init(
        secretStore: any SecretStore,
        verifier: any LocalLicenseVerifier = NoBundledLocalLicenseVerifier()
    ) {
        self.secretStore = secretStore
        self.verifier = verifier
    }

    public func snapshot() throws -> EntitlementSnapshot {
        guard let licenseText = try secretStore.read(.subscriptionLicense)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !licenseText.isEmpty else {
            return EntitlementSnapshot(plan: .free, source: .defaultFree)
        }

        guard let plan = verifier.plan(for: licenseText) else {
            return EntitlementSnapshot(plan: .free, source: .invalidLocalLicense)
        }

        return EntitlementSnapshot(plan: plan, source: .localLicense)
    }
}
