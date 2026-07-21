import Foundation

/// Stable App Server methods used by Suisui. Keeping this list explicit prevents
/// experimental coding-agent capabilities from silently entering the voice-task path.
public enum CodexAppServerMethod {
    public static let initialize = "initialize"
    public static let accountRead = "account/read"
    public static let accountLoginStart = "account/login/start"
    public static let accountLoginCancel = "account/login/cancel"
    public static let accountLogout = "account/logout"
    public static let accountRateLimitsRead = "account/rateLimits/read"
    public static let modelList = "model/list"
    public static let threadStart = "thread/start"
    public static let turnStart = "turn/start"
    public static let turnInterrupt = "turn/interrupt"

    public static let commandExecutionRequestApproval = "item/commandExecution/requestApproval"
    public static let fileChangeRequestApproval = "item/fileChange/requestApproval"
    public static let permissionsRequestApproval = "item/permissions/requestApproval"
}

public enum CodexLoginKind: String, CaseIterable, Codable, Hashable, Sendable {
    case chatGPTBrowser = "chatgpt"
    case chatGPTDeviceCode = "chatgptDeviceCode"
}

public struct CodexLoginStartParams: Codable, Equatable, Sendable {
    public let type: CodexLoginKind

    public init(type: CodexLoginKind) {
        self.type = type
    }
}

public enum CodexPlanType: String, Codable, Equatable, Sendable {
    case free
    case go
    case plus
    case pro
    case prolite
    case team
    case selfServeBusinessUsageBased = "self_serve_business_usage_based"
    case business
    case enterpriseCBPUsageBased = "enterprise_cbp_usage_based"
    case enterprise
    case edu
    case unknown

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

public enum CodexAccount: Equatable, Sendable {
    case chatGPT(email: String?, plan: CodexPlanType)
    case unsupported(type: String)
}

extension CodexAccount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "chatgpt" else {
            self = .unsupported(type: type)
            return
        }

        self = .chatGPT(
            email: try container.decodeIfPresent(String.self, forKey: .email),
            plan: try container.decode(CodexPlanType.self, forKey: .planType)
        )
    }
}

public struct CodexAccountReadResponse: Decodable, Equatable, Sendable {
    public let account: CodexAccount?
    public let requiresOpenAIAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case account
        case requiresOpenAIAuth = "requiresOpenaiAuth"
    }
}

public enum CodexLoginStartResponse: Equatable, Sendable {
    case chatGPTBrowser(loginID: String, authenticationURL: URL)
    case chatGPTDeviceCode(loginID: String, userCode: String, verificationURL: URL)
}

extension CodexLoginStartResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case loginID = "loginId"
        case authenticationURL = "authUrl"
        case userCode
        case verificationURL = "verificationUrl"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CodexLoginKind.self, forKey: .type)
        let loginID = try container.decode(String.self, forKey: .loginID)
        switch type {
        case .chatGPTBrowser:
            self = .chatGPTBrowser(
                loginID: loginID,
                authenticationURL: try container.decode(URL.self, forKey: .authenticationURL)
            )
        case .chatGPTDeviceCode:
            self = .chatGPTDeviceCode(
                loginID: loginID,
                userCode: try container.decode(String.self, forKey: .userCode),
                verificationURL: try container.decode(URL.self, forKey: .verificationURL)
            )
        }
    }
}

public enum CodexInboundMessageKind: Equatable, Sendable {
    case response
    case notification
    case serverRequest
}

/// Envelope metadata is decoded before any method-specific payload. Unknown
/// notifications remain ignorable, while requests can be rejected immediately.
public struct CodexInboundMessage: Decodable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: Int64?
    public let method: String?

    public var kind: CodexInboundMessageKind {
        if method != nil {
            return id == nil ? .notification : .serverRequest
        }
        return .response
    }

    public var isForbiddenToolLifecycle: Bool {
        switch method {
        case CodexAppServerMethod.commandExecutionRequestApproval,
             CodexAppServerMethod.fileChangeRequestApproval,
             CodexAppServerMethod.permissionsRequestApproval:
            return true
        default:
            return false
        }
    }
}

public struct CodexJSONRPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    public let jsonrpc = "2.0"
    public let id: Int64
    public let method: String
    public let params: Params

    public init(id: Int64, method: String, params: Params) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct CodexJSONRPCResponse<Result: Decodable & Sendable>: Decodable, Sendable {
    public let jsonrpc: String
    public let id: Int64
    public let result: Result
}
