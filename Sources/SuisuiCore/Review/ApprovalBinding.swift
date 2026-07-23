import CryptoKit
import Foundation

public enum CanonicalJSONError: Error, Equatable, Sendable {
    case nonFiniteNumber
}

/// Encodes the execution contract with stable object-key ordering and number
/// normalization. Approval digests use this encoder instead of Foundation's
/// general-purpose encoders because their output format is not an API contract.
public enum CanonicalJSONEncoder {
    public static func encode(_ value: JSONValue) throws -> Data {
        Data(try encodeString(value).utf8)
    }

    public static func encodeString(_ value: JSONValue) throws -> String {
        switch value {
        case .string(let string):
            return encodeJSONString(string)
        case .number(let number):
            return try encodeNumber(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .object(let object):
            let fields = try object.keys
                .sorted(by: canonicalKeyOrder)
                .map { key in
                    "\(encodeJSONString(key)):\(try encodeString(object[key] ?? .null))"
                }
            return "{\(fields.joined(separator: ","))}"
        case .array(let array):
            return "[\(try array.map(encodeString).joined(separator: ","))]"
        case .null:
            return "null"
        case .actionOutput(let reference):
            return try encodeString(reference.canonicalJSONValue)
        }
    }

    private static func encodeNumber(_ number: Double) throws -> String {
        guard number.isFinite else {
            throw CanonicalJSONError.nonFiniteNumber
        }
        guard number != 0 else {
            return "0"
        }

        var rendered = String(number).lowercased()
        if let exponentIndex = rendered.firstIndex(of: "e") {
            var mantissa = String(rendered[..<exponentIndex])
            if mantissa.hasSuffix(".0") {
                mantissa.removeLast(2)
            }
            let exponentText = String(rendered[rendered.index(after: exponentIndex)...])
            let exponent = Int(exponentText) ?? 0
            return "\(mantissa)e\(exponent)"
        }
        if rendered.hasSuffix(".0") {
            rendered.removeLast(2)
        }
        return rendered
    }

    private static func encodeJSONString(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x08:
                result += "\\b"
            case 0x09:
                result += "\\t"
            case 0x0A:
                result += "\\n"
            case 0x0C:
                result += "\\f"
            case 0x0D:
                result += "\\r"
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x00...0x1F:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    private static func canonicalKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }
}

public struct ActionOutputReference: Codable, Equatable, Hashable, Sendable {
    public let actionID: String
    public let key: String

    public init(actionID: String, key: String) {
        self.actionID = actionID
        self.key = key
    }

    fileprivate var canonicalJSONValue: JSONValue {
        .object([
            "$type": .string("actionOutput"),
            "actionID": .string(actionID),
            "key": .string(key)
        ])
    }
}

public struct ActionDependencyResolutionEvidence: Codable, Equatable, Sendable {
    public let argumentPath: String
    public let sourceActionID: String
    public let outputKey: String
    public let resolvedValueDigest: String

    public init(
        argumentPath: String,
        sourceActionID: String,
        outputKey: String,
        resolvedValueDigest: String
    ) {
        self.argumentPath = argumentPath
        self.sourceActionID = sourceActionID
        self.outputKey = outputKey
        self.resolvedValueDigest = resolvedValueDigest
    }
}

public struct ResolvedActionEvidence: Codable, Equatable, Sendable {
    public let actionID: String
    public let resolvedArgumentsDigest: String
    public let dependencies: [ActionDependencyResolutionEvidence]

    public init(
        actionID: String,
        resolvedArgumentsDigest: String,
        dependencies: [ActionDependencyResolutionEvidence]
    ) {
        self.actionID = actionID
        self.resolvedArgumentsDigest = resolvedArgumentsDigest
        self.dependencies = dependencies
    }
}

public struct ApprovalPlanItem: Equatable, Sendable {
    public var action: PlanAction
    public var isEnabled: Bool

    public init(action: PlanAction, isEnabled: Bool) {
        self.action = action
        self.isEnabled = isEnabled
    }

    fileprivate var canonicalJSONValue: JSONValue {
        .object([
            "id": .string(action.id),
            "tool": .string(action.tool.rawValue),
            "riskLevel": .string(action.riskLevel.rawValue),
            "enabled": .bool(isEnabled),
            "requiresUserConfirmation": .bool(action.requiresUserConfirmation),
            "arguments": .object(action.arguments)
        ])
    }
}

public struct ApprovalPlanBinding: Equatable, Sendable {
    public var planID: String
    public var items: [ApprovalPlanItem]
    public var executionPolicy: ActionExecutorFailurePolicy

    public init(
        planID: String,
        items: [ApprovalPlanItem],
        executionPolicy: ActionExecutorFailurePolicy
    ) {
        self.planID = planID
        self.items = items
        self.executionPolicy = executionPolicy
    }

    public var enabledActionIDs: Set<String> {
        Set(items.lazy.filter(\.isEnabled).map(\.action.id))
    }

    public func canonicalJSON() throws -> Data {
        try CanonicalJSONEncoder.encode(.object([
            "schemaVersion": .number(1),
            "planID": .string(planID),
            "executionPolicy": .string(executionPolicy.rawValue),
            "actions": .array(items.map(\.canonicalJSONValue))
        ]))
    }

    public func digest() throws -> Data {
        Data(SHA256.hash(data: try canonicalJSON()))
    }
}

public struct ApprovedExecution: Codable, Equatable, Sendable {
    public let approvalID: UUID
    public let sessionID: String
    public let planID: String
    public let canonicalPlanDigest: Data
    public let enabledActionIDs: Set<String>
    public let issuedAt: Date
    public let expiresAt: Date
    public let nonce: UUID
    private var legacyID: String?

    public init(
        approvalID: UUID,
        sessionID: String,
        planID: String,
        canonicalPlanDigest: Data,
        enabledActionIDs: Set<String>,
        issuedAt: Date,
        expiresAt: Date,
        nonce: UUID
    ) {
        self.approvalID = approvalID
        self.sessionID = sessionID
        self.planID = planID
        self.canonicalPlanDigest = canonicalPlanDigest
        self.enabledActionIDs = enabledActionIDs
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.legacyID = nil
    }

    /// Compatibility initializer for explicit, non-plan tool approvals.
    /// ReviewSession approvals never use this path: they seal the reviewed
    /// ActionPlan through `ReviewSession.approve`.
    init(id: String, sessionID: String, approvedAt: Date = Date()) {
        let approvalID = UUID(uuidString: id) ?? UUID()
        self.init(
            approvalID: approvalID,
            sessionID: sessionID,
            planID: "standalone:\(id)",
            canonicalPlanDigest: Data(SHA256.hash(data: Data("\(sessionID):\(id)".utf8))),
            enabledActionIDs: ["standalone"],
            issuedAt: approvedAt,
            expiresAt: approvedAt.addingTimeInterval(300),
            nonce: UUID()
        )
        self.legacyID = id
    }

    public var id: String {
        legacyID ?? approvalID.uuidString
    }

    public var approvedAt: Date {
        issuedAt
    }

    public func validate(
        for binding: ApprovalPlanBinding,
        sessionID expectedSessionID: String,
        now: Date
    ) throws {
        guard sessionID == expectedSessionID else {
            throw ApprovedExecutionValidationError.sessionMismatch
        }
        guard planID == binding.planID else {
            throw ApprovedExecutionValidationError.planMismatch
        }
        guard canonicalPlanDigest.count == 32,
              canonicalPlanDigest == (try binding.digest()) else {
            throw ApprovedExecutionValidationError.digestMismatch
        }
        guard enabledActionIDs == binding.enabledActionIDs else {
            throw ApprovedExecutionValidationError.enabledActionsMismatch
        }
        guard now >= issuedAt else {
            throw ApprovedExecutionValidationError.notYetValid
        }
        guard now < expiresAt else {
            throw ApprovedExecutionValidationError.expired
        }
    }
}

public typealias ApprovalToken = ApprovedExecution

public enum ApprovedExecutionValidationError: Error, Equatable, Sendable {
    case sessionMismatch
    case planMismatch
    case digestMismatch
    case enabledActionsMismatch
    case notYetValid
    case expired
}

public extension Data {
    var lowercaseHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

public extension CanonicalJSONEncoder {
    static func digest(_ value: JSONValue) throws -> Data {
        Data(SHA256.hash(data: try encode(value)))
    }
}
