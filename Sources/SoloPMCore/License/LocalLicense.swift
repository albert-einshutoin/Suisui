import Foundation

public struct LocalLicense: Codable, Equatable, Sendable {
    public var id: String
    public var plan: LicensePlan
    public var issuedAt: Date
    public var expiresAt: Date?
    public var features: [String]
    public var signature: String?

    public init(
        id: String,
        plan: LicensePlan,
        issuedAt: Date,
        expiresAt: Date? = nil,
        features: [String] = [],
        signature: String? = nil
    ) {
        self.id = id
        self.plan = plan
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.features = features
        self.signature = signature
    }
}

public enum LicensePlan: String, Codable, Equatable, Sendable {
    case free
    case founder
    case personalPlus

    public var displayName: String {
        switch self {
        case .free:
            "Free"
        case .founder:
            "Founder"
        case .personalPlus:
            "Personal Plus"
        }
    }
}

public struct LicenseValidationResult: Equatable, Sendable {
    public var status: LicenseStatus
    public var license: LocalLicense?

    public init(status: LicenseStatus, license: LocalLicense? = nil) {
        self.status = status
        self.license = license
    }

    public var displayState: LicenseDisplayState {
        switch status {
        case .missing:
            .missing
        case .valid(let plan):
            .active(planName: plan.displayName)
        case .expired(let plan):
            .expired(planName: plan.displayName)
        case .invalid(let reason):
            .invalid(message: reason)
        }
    }
}

public enum LicenseStatus: Equatable, Sendable {
    case missing
    case valid(plan: LicensePlan)
    case expired(plan: LicensePlan)
    case invalid(reason: String)
}

public enum LicenseDisplayState: Equatable, Sendable {
    case missing
    case active(planName: String)
    case expired(planName: String)
    case invalid(message: String)
}

public struct LocalLicenseValidator: Sendable {
    private let personalInformationFields: Set<String> = [
        "email",
        "name",
        "fullName",
        "userName",
        "phone",
        "address"
    ]

    public init() {}

    public func validate(data: Data?, now: Date = Date()) -> LicenseValidationResult {
        guard let data else {
            return LicenseValidationResult(status: .missing)
        }

        do {
            try rejectPersonalInformationFields(in: data)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let license = try decoder.decode(LocalLicense.self, from: data)

            if let expiresAt = license.expiresAt, expiresAt <= now {
                return LicenseValidationResult(status: .expired(plan: license.plan), license: license)
            }

            return LicenseValidationResult(status: .valid(plan: license.plan), license: license)
        } catch let error as LicenseValidationError {
            return LicenseValidationResult(status: .invalid(reason: error.message))
        } catch {
            return LicenseValidationResult(status: .invalid(reason: "License file is not valid JSON."))
        }
    }

    private func rejectPersonalInformationFields(in data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw LicenseValidationError(message: "License file is not valid JSON.")
        }

        let keys = Set(dictionary.keys)
        if !keys.intersection(personalInformationFields).isEmpty {
            throw LicenseValidationError(message: "License file must not contain personal information fields.")
        }
    }
}

private struct LicenseValidationError: Error {
    var message: String
}
