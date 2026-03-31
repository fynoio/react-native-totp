import Foundation

public struct CompletionRequest: Codable {
  enum CodingKeys: String, CodingKey {
    case tenantId = "tenant_id"
    case enrolmentId = "enrolment_id"
    case otp
    case deviceUuid = "device_uuid"
    case userId = "user_id"
  }
  public let tenantId: String
  public let enrolmentId: String
  public let otp: String
  public let deviceUuid: String
  public let userId: String
}

public struct RegistrationRequest: Codable {
  enum CodingKeys: String, CodingKey {
    case tenantId = "tenant_id"
    case userId = "user_id"
  }
  public let tenantId: String
  public let userId: String
}

public struct ErrorResponse: Codable {
  public let error: String
  public let message: String
}

public struct SuccessResponse: Codable {
  enum CodingKeys: String, CodingKey {
    case enrolmentId = "enrolment_id"
    case config
  }
  public let enrolmentId: String
  public let config: TotpConfig
}

public struct TotpConfig: Codable {
  public let digits: Int
  public let period: Int
  public let algorithm: String
  
  public init(digits: Int, period: Int, algorithm: String) {
    self.digits = digits
    self.period = period
    self.algorithm = algorithm
  }
}

public struct TotpData {
  public let encryptedSecretAlias: String
  public let iv: String?
  public let config: TotpConfig
  public let status: Int
}

public struct ActiveTenant {
  public let tenantId: String
  public let tenantLabel: String
  public let config: TotpConfig?
}
