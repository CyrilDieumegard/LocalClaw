import CryptoKit
import Foundation

enum LicenseBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> Data? {
        guard !value.isEmpty,
              value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        let remainder = value.count % 4
        guard remainder != 1 else { return nil }
        let padding = remainder == 0 ? "" : String(repeating: "=", count: 4 - remainder)
        return Data(base64Encoded: value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + padding)
    }
}

struct LicenseReceiptKey: Equatable, Sendable {
    let kid: String
    let rawPublicKey: Data

    init(kid: String, rawPublicKey: Data) throws {
        guard kid.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw LicenseReceiptValidationError.invalidKeyIdentifier
        }
        guard rawPublicKey.count == 32 else {
            throw LicenseReceiptValidationError.invalidPublicKey
        }
        self.kid = kid
        self.rawPublicKey = rawPublicKey
    }

    init(kid: String, rawPublicKeyBase64URL: String) throws {
        guard let data = LicenseBase64URL.decode(rawPublicKeyBase64URL) else {
            throw LicenseReceiptValidationError.invalidPublicKey
        }
        try self.init(kid: kid, rawPublicKey: data)
    }
}

struct LicenseReceiptKeyRing: Sendable {
    private let keysByID: [String: Data]

    init(keys: [LicenseReceiptKey]) throws {
        var result: [String: Data] = [:]
        for key in keys {
            guard result.updateValue(key.rawPublicKey, forKey: key.kid) == nil else {
                throw LicenseReceiptValidationError.duplicateKeyIdentifier
            }
        }
        self.keysByID = result
    }

    func rawPublicKey(for kid: String) -> Data? {
        keysByID[kid]
    }
}

enum LicenseProductionTrust {
    static let currentKeyID = "localclaw-license-2026-09-01"
    static let currentPublicKeyBase64URL = "4gCEftrjJWeD6O8323OchqxmrzXoZvkJDFMFyuDd-3A"

    // Add the previous public key here during a planned rotation. Never embed
    // a signing/private key or a customer license key in the application.
    private static let embeddedPublicKeys: [(kid: String, value: String)] = [
        (currentKeyID, currentPublicKeyBase64URL)
    ]

    static func keyRing() throws -> LicenseReceiptKeyRing {
        try LicenseReceiptKeyRing(keys: embeddedPublicKeys.map {
            try LicenseReceiptKey(kid: $0.kid, rawPublicKeyBase64URL: $0.value)
        })
    }

    static func verifier() throws -> LicenseReceiptVerifier {
        LicenseReceiptVerifier(keyRing: try keyRing())
    }
}

struct LicenseReceiptHeader: Codable, Equatable, Sendable {
    let alg: String
    let typ: String
    let kid: String
}

struct LicenseReceiptClaims: Codable, Equatable, Sendable {
    let issuer: String
    let audience: String
    let schema: String
    let jti: String
    let subject: String
    let issuedAt: Int64
    let notBefore: Int64
    let expiresAt: Int64
    let licenseID: String
    let licenseVersion: Int
    let product: String
    let entitlement: String
    let entitlementExpiresAt: Int64?
    let status: String
    let source: String
    let machineHash: String
    let emailHash: String
    let keyHash: String
    let appVersion: String
    let minimumAppVersion: String

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case audience = "aud"
        case schema
        case jti
        case subject = "sub"
        case issuedAt = "iat"
        case notBefore = "nbf"
        case expiresAt = "exp"
        case licenseID = "license_id"
        case licenseVersion = "license_version"
        case product
        case entitlement
        case entitlementExpiresAt = "entitlement_expires_at"
        case status
        case source
        case machineHash = "machine_hash"
        case emailHash = "email_hash"
        case keyHash = "key_hash"
        case appVersion = "app_version"
        case minimumAppVersion = "min_app_version"
    }
}

struct LicenseReceiptExpectation: Equatable, Sendable {
    let email: String
    let licenseKey: String
    let machineID: String
    let appVersion: String
}

struct VerifiedLicenseReceipt: Equatable, Sendable {
    let compactJWS: String
    let header: LicenseReceiptHeader
    let claims: LicenseReceiptClaims

    var receiptExpiration: Date {
        Date(timeIntervalSince1970: TimeInterval(claims.expiresAt))
    }

    var entitlementExpiration: Date? {
        claims.entitlementExpiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var isLifetimeEntitlement: Bool {
        claims.entitlement == "lifetime" && claims.entitlementExpiresAt == nil
    }
}

enum LicenseReceiptValidationError: Error, Equatable, LocalizedError, Sendable {
    case malformedCompactJWS
    case malformedHeader
    case malformedClaims
    case invalidAlgorithm
    case invalidType
    case invalidKeyIdentifier
    case unknownKeyIdentifier
    case duplicateKeyIdentifier
    case invalidPublicKey
    case invalidSignature
    case invalidIssuer
    case invalidAudience
    case invalidSchema
    case invalidReceiptIdentifier
    case invalidLicenseIdentifier
    case invalidLicenseVersion
    case invalidSubject
    case invalidProduct
    case invalidEntitlement
    case inactiveLicense
    case invalidSource
    case receiptNotYetValid
    case receiptExpired
    case entitlementExpired
    case machineMismatch
    case emailMismatch
    case licenseKeyMismatch
    case invalidAppVersion
    case appVersionTooOld

    var errorDescription: String? {
        switch self {
        case .malformedCompactJWS: "Malformed signed license receipt."
        case .malformedHeader: "Malformed license receipt header."
        case .malformedClaims: "Malformed license receipt claims."
        case .invalidAlgorithm: "Unsupported license receipt signature algorithm."
        case .invalidType: "Unsupported license receipt type."
        case .invalidKeyIdentifier: "Missing or invalid license signing key identifier."
        case .unknownKeyIdentifier: "The license receipt uses an unknown signing key."
        case .duplicateKeyIdentifier: "The license signing key ring contains a duplicate identifier."
        case .invalidPublicKey: "The embedded license verification key is invalid."
        case .invalidSignature: "The license receipt signature is invalid."
        case .invalidIssuer: "The license receipt issuer is invalid."
        case .invalidAudience: "The license receipt audience is invalid."
        case .invalidSchema: "The license receipt schema is invalid."
        case .invalidReceiptIdentifier: "The license receipt identifier is invalid."
        case .invalidLicenseIdentifier: "The license identifier is invalid."
        case .invalidLicenseVersion: "The license version is invalid."
        case .invalidSubject: "The license receipt subject does not match its license."
        case .invalidProduct: "The license receipt is for another product."
        case .invalidEntitlement: "The license entitlement is invalid."
        case .inactiveLicense: "The license is not active."
        case .invalidSource: "The license receipt source is invalid."
        case .receiptNotYetValid: "The license receipt is not valid yet."
        case .receiptExpired: "The signed license receipt needs to be refreshed."
        case .entitlementExpired: "The license entitlement has expired."
        case .machineMismatch: "The license receipt belongs to another Mac."
        case .emailMismatch: "The license receipt belongs to another email address."
        case .licenseKeyMismatch: "The license receipt belongs to another license key."
        case .invalidAppVersion: "The license receipt contains an invalid app version."
        case .appVersionTooOld: "This LocalClaw version is too old for the license receipt."
        }
    }
}

struct LicenseReceiptVerifier: Sendable {
    static let issuer = "https://localclaw.io"
    static let audience = "io.localclaw.installer"
    static let schema = "lc-license-receipt/v1"
    static let product = "localclaw"
    static let receiptType = "localclaw-license+jwt"

    private static let supportedSources: Set<String> = ["stripe", "legacy_migration"]
    private let keyRing: LicenseReceiptKeyRing
    private let clockSkew: TimeInterval

    init(keyRing: LicenseReceiptKeyRing, clockSkew: TimeInterval = 300) {
        self.keyRing = keyRing
        self.clockSkew = max(0, clockSkew)
    }

    func verify(
        compactJWS: String,
        expected: LicenseReceiptExpectation,
        now: Date = Date()
    ) throws -> VerifiedLicenseReceipt {
        try authenticatedReceipt(
            compactJWS: compactJWS,
            expected: expected,
            now: now,
            enforceReceiptExpiration: true
        )
    }

    func verifyForExpiredReceiptGrace(
        compactJWS: String,
        expected: LicenseReceiptExpectation,
        now: Date = Date()
    ) throws -> VerifiedLicenseReceipt {
        try authenticatedReceipt(
            compactJWS: compactJWS,
            expected: expected,
            now: now,
            enforceReceiptExpiration: false
        )
    }

    private func authenticatedReceipt(
        compactJWS: String,
        expected: LicenseReceiptExpectation,
        now: Date,
        enforceReceiptExpiration: Bool
    ) throws -> VerifiedLicenseReceipt {
        let segments = compactJWS.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = LicenseBase64URL.decode(String(segments[0])),
              let claimsData = LicenseBase64URL.decode(String(segments[1])),
              let signature = LicenseBase64URL.decode(String(segments[2])),
              signature.count == 64 else {
            throw LicenseReceiptValidationError.malformedCompactJWS
        }

        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(LicenseReceiptHeader.self, from: headerData) else {
            throw LicenseReceiptValidationError.malformedHeader
        }
        guard header.alg == "EdDSA" else { throw LicenseReceiptValidationError.invalidAlgorithm }
        guard header.typ == Self.receiptType else { throw LicenseReceiptValidationError.invalidType }
        guard header.kid.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        ) != nil else { throw LicenseReceiptValidationError.invalidKeyIdentifier }
        let canonicalHeader = Data(
            #"{"alg":"EdDSA","typ":"localclaw-license+jwt","kid":"\#(header.kid)"}"#.utf8
        )
        guard headerData == canonicalHeader else { throw LicenseReceiptValidationError.malformedHeader }
        guard let rawPublicKey = keyRing.rawPublicKey(for: header.kid) else {
            throw LicenseReceiptValidationError.unknownKeyIdentifier
        }
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)
        } catch {
            throw LicenseReceiptValidationError.invalidPublicKey
        }
        guard publicKey.isValidSignature(signature, for: signingInput) else {
            throw LicenseReceiptValidationError.invalidSignature
        }
        guard let claims = try? decoder.decode(LicenseReceiptClaims.self, from: claimsData) else {
            throw LicenseReceiptValidationError.malformedClaims
        }
        try validate(
            claims: claims,
            expected: expected,
            now: now,
            enforceReceiptExpiration: enforceReceiptExpiration
        )
        return VerifiedLicenseReceipt(compactJWS: compactJWS, header: header, claims: claims)
    }

    private func validate(
        claims: LicenseReceiptClaims,
        expected: LicenseReceiptExpectation,
        now: Date,
        enforceReceiptExpiration: Bool
    ) throws {
        guard claims.issuer == Self.issuer else { throw LicenseReceiptValidationError.invalidIssuer }
        guard claims.audience == Self.audience else { throw LicenseReceiptValidationError.invalidAudience }
        guard claims.schema == Self.schema else { throw LicenseReceiptValidationError.invalidSchema }
        guard UUID(uuidString: claims.jti) != nil else { throw LicenseReceiptValidationError.invalidReceiptIdentifier }
        guard UUID(uuidString: claims.licenseID) != nil else { throw LicenseReceiptValidationError.invalidLicenseIdentifier }
        guard claims.licenseVersion >= 1 else { throw LicenseReceiptValidationError.invalidLicenseVersion }
        guard claims.subject == "license:\(claims.licenseID)" else { throw LicenseReceiptValidationError.invalidSubject }
        guard claims.product == Self.product else { throw LicenseReceiptValidationError.invalidProduct }
        guard claims.entitlement == "lifetime", claims.entitlementExpiresAt == nil else {
            throw LicenseReceiptValidationError.invalidEntitlement
        }
        guard claims.status == "active" else { throw LicenseReceiptValidationError.inactiveLicense }
        guard Self.supportedSources.contains(claims.source) else { throw LicenseReceiptValidationError.invalidSource }

        let nowSeconds = now.timeIntervalSince1970
        guard TimeInterval(claims.notBefore) <= nowSeconds + clockSkew,
              TimeInterval(claims.issuedAt) <= nowSeconds + clockSkew else {
            throw LicenseReceiptValidationError.receiptNotYetValid
        }
        guard claims.notBefore == claims.issuedAt - 60,
              claims.expiresAt > claims.issuedAt else {
            throw LicenseReceiptValidationError.malformedClaims
        }
        if enforceReceiptExpiration,
           TimeInterval(claims.expiresAt) <= nowSeconds - clockSkew {
            throw LicenseReceiptValidationError.receiptExpired
        }

        guard claims.machineHash == Self.boundHash(
            domain: "localclaw:machine:v1",
            normalizedValue: Self.normalizeMachineID(expected.machineID)
        ) else { throw LicenseReceiptValidationError.machineMismatch }
        guard claims.emailHash == Self.boundHash(
            domain: "localclaw:email:v1",
            normalizedValue: Self.normalizeEmail(expected.email)
        ) else { throw LicenseReceiptValidationError.emailMismatch }
        guard claims.keyHash == Self.boundHash(
            domain: "localclaw:key:v1",
            normalizedValue: Self.normalizeLicenseKey(expected.licenseKey)
        ) else { throw LicenseReceiptValidationError.licenseKeyMismatch }

        guard InstallerEngine.versionComponents(from: claims.appVersion) != nil,
              InstallerEngine.versionComponents(from: claims.minimumAppVersion) != nil,
              InstallerEngine.versionComponents(from: expected.appVersion) != nil else {
            throw LicenseReceiptValidationError.invalidAppVersion
        }
        guard (InstallerEngine.compareVersion(expected.appVersion, claims.minimumAppVersion) ?? -1) >= 0 else {
            throw LicenseReceiptValidationError.appVersionTooOld
        }
    }

    static func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    static func normalizeLicenseKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.unicodeScalars.map { scalar in
            if scalar.value >= 97, scalar.value <= 122,
               let upper = UnicodeScalar(scalar.value - 32) {
                return Character(upper)
            }
            return Character(scalar)
        })
    }

    static func normalizeMachineID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    static func boundHash(domain: String, normalizedValue: String) -> String {
        var input = Data(domain.utf8)
        input.append(0)
        input.append(contentsOf: normalizedValue.utf8)
        return LicenseBase64URL.encode(Data(SHA256.hash(data: input)))
    }
}

struct LegacyLicenseRecord: Codable, Equatable, Sendable {
    let email: String
    let licenseKey: String
    let token: String
    let machineId: String
    let activatedAt: String
    let expiresAt: String?
}

struct LicenseSecurityState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var signedReceipt: String?
    var legacyGraceStartedAt: String?
    var legacyGraceUntil: String?
    var lastRefreshAttemptAt: String?
    var lastRefreshSucceededAt: String?
    var boundedLegacyMachineHash: String?
    var boundedLegacyEmailHash: String?
    var boundedLegacyKeyHash: String?
}

struct LicenseExchangeRequest: Codable, Equatable, Sendable {
    let email: String
    let licenseKey: String
    let machineId: String
    let appVersion: String
    let currentReceipt: String?
}

struct LicenseExchangeResponse: Codable, Equatable, Sendable {
    struct LicenseSummary: Codable, Equatable, Sendable {
        let id: String?
        let status: String?
        let entitlement: String?
        let machineLimit: Int?
    }

    let ok: Bool
    let mode: String?
    let token: String?
    let receipt: String?
    let receiptFormat: String?
    let expiresAt: String?
    let license: LicenseSummary?
    let message: String?
}

enum LicenseRefreshError: Error, Equatable, LocalizedError, Sendable {
    case serverRefused(String)
    case secureReceiptMissing
    case secureReceiptAliasesDiffer
    case invalidSecureReceiptFormat
    case unsignedRollbackNotAccepted

    var errorDescription: String? {
        switch self {
        case .serverRefused(let message): message
        case .secureReceiptMissing: "The license server did not return a signed receipt."
        case .secureReceiptAliasesDiffer: "The license server returned inconsistent signed receipt aliases."
        case .invalidSecureReceiptFormat: "The license server returned an unsupported signed receipt format."
        case .unsignedRollbackNotAccepted: "The license server returned an unsigned rollback token."
        }
    }
}

enum LicenseExchangeHTTPError: Error, Equatable, LocalizedError, Sendable {
    case noHTTPResponse
    case responseTooLarge
    case malformedResponse
    case refused(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noHTTPResponse: "The license server did not return an HTTP response."
        case .responseTooLarge: "The license server response exceeded the safety limit."
        case .malformedResponse: "The license server returned an unreadable response."
        case .refused(_, let message): message
        }
    }
}

struct LicenseExchangeHTTPClient: Sendable {
    static let maximumResponseBytes = 256 * 1_024

    let endpoint: URL
    let session: URLSession

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func exchange(_ payload: LicenseExchangeRequest) async throws -> LicenseExchangeResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseExchangeHTTPError.noHTTPResponse
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw LicenseExchangeHTTPError.responseTooLarge
        }
        guard let decoded = try? JSONDecoder().decode(LicenseExchangeResponse.self, from: data) else {
            throw LicenseExchangeHTTPError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode), decoded.ok else {
            throw LicenseExchangeHTTPError.refused(
                status: http.statusCode,
                message: decoded.message ?? "License activation refused (\(http.statusCode))."
            )
        }
        return decoded
    }
}

struct LicenseRefreshResult: Sendable {
    let record: LegacyLicenseRecord
    let securityState: LicenseSecurityState
    let decision: LicenseAccessDecision
    let refreshError: String?
}

enum LicenseAccessMode: String, Equatable, Sendable {
    case verifiedReceipt
    case verifiedReceiptRefreshRecommended
    case legacyMigrationPreserved
    case denied
}

struct LicenseAccessDecision: Equatable, Sendable {
    let mode: LicenseAccessMode
    let message: String
    let shouldRefresh: Bool
    let legacyGraceUntil: Date?

    var allowsUse: Bool {
        mode != .denied
    }
}

struct LicenseMigrationPolicy: Sendable {
    let legacyGraceInterval: TimeInterval
    let refreshLeadTime: TimeInterval
    let expiredReceiptGraceInterval: TimeInterval

    init(legacyGraceInterval: TimeInterval = 60 * 60 * 24 * 30,
         refreshLeadTime: TimeInterval = 60 * 60 * 24 * 14,
         expiredReceiptGraceInterval: TimeInterval = 60 * 60 * 24 * 14) {
        self.legacyGraceInterval = max(0, legacyGraceInterval)
        self.refreshLeadTime = max(0, refreshLeadTime)
        self.expiredReceiptGraceInterval = max(0, expiredReceiptGraceInterval)
    }
}

struct LicenseMigrationEvaluator: Sendable {
    private let verifier: LicenseReceiptVerifier
    private let policy: LicenseMigrationPolicy

    init(verifier: LicenseReceiptVerifier, policy: LicenseMigrationPolicy = LicenseMigrationPolicy()) {
        self.verifier = verifier
        self.policy = policy
    }

    func evaluate(
        record: LegacyLicenseRecord,
        securityState: LicenseSecurityState,
        expected: LicenseReceiptExpectation,
        now: Date = Date()
    ) -> LicenseAccessDecision {
        guard record.machineId == expected.machineID else {
            return LicenseAccessDecision(
                mode: .denied,
                message: "License belongs to another Mac. The saved license was preserved for reactivation.",
                shouldRefresh: false,
                legacyGraceUntil: Self.date(from: securityState.legacyGraceUntil)
            )
        }

        if let receipt = securityState.signedReceipt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !receipt.isEmpty {
            do {
                let verified = try verifier.verify(compactJWS: receipt, expected: expected, now: now)
                let shouldRefresh = verified.receiptExpiration.timeIntervalSince(now) <= policy.refreshLeadTime
                return LicenseAccessDecision(
                    mode: shouldRefresh ? .verifiedReceiptRefreshRecommended : .verifiedReceipt,
                    message: shouldRefresh ? "License verified; signed receipt refresh recommended." : "License verified on this Mac.",
                    shouldRefresh: shouldRefresh,
                    legacyGraceUntil: nil
                )
            } catch let error as LicenseReceiptValidationError {
                if error == .receiptExpired,
                   let authenticated = try? verifier.verifyForExpiredReceiptGrace(
                    compactJWS: receipt,
                    expected: expected,
                    now: now
                   ) {
                    let offlineUntil = authenticated.receiptExpiration
                        .addingTimeInterval(policy.expiredReceiptGraceInterval)
                    if offlineUntil >= now {
                        return LicenseAccessDecision(
                            mode: .verifiedReceiptRefreshRecommended,
                            message: "Lifetime license verified; the signed receipt needs a network refresh.",
                            shouldRefresh: true,
                            legacyGraceUntil: offlineUntil
                        )
                    }
                    return LicenseAccessDecision(
                        mode: .denied,
                        message: "The signed receipt refresh grace has ended. Connect this Mac to refresh the lifetime license; saved license data was preserved.",
                        shouldRefresh: true,
                        legacyGraceUntil: offlineUntil
                    )
                }
                return LicenseAccessDecision(
                    mode: .denied,
                    message: "Signed license receipt verification failed. Connect this Mac to refresh it; saved license data was preserved.",
                    shouldRefresh: true,
                    legacyGraceUntil: nil
                )
            } catch {
                return LicenseAccessDecision(
                    mode: .denied,
                    message: "Signed license receipt verification failed. Connect this Mac to refresh it; saved license data was preserved.",
                    shouldRefresh: true,
                    legacyGraceUntil: nil
                )
            }
        }

        let token = record.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              !record.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LicenseAccessDecision(
                mode: .denied,
                message: "The saved license is incomplete. Its files were preserved for support.",
                shouldRefresh: false,
                legacyGraceUntil: nil
            )
        }
        if token.split(separator: ".", omittingEmptySubsequences: false).count == 3 {
            return LicenseAccessDecision(
                mode: .denied,
                message: "The compact signed license cache could not be verified. Connect this Mac to refresh it; saved data was preserved.",
                shouldRefresh: true,
                legacyGraceUntil: nil
            )
        }

        if let graceUntil = Self.date(from: securityState.legacyGraceUntil) {
            let matchesBoundedIdentity = securityState.boundedLegacyMachineHash == Self.machineHash(expected)
                && securityState.boundedLegacyEmailHash == Self.emailHash(expected)
                && securityState.boundedLegacyKeyHash == Self.keyHash(expected)
            guard matchesBoundedIdentity else {
                return LicenseAccessDecision(
                    mode: .legacyMigrationPreserved,
                    message: "Existing license preserved on this Mac during secure receipt migration.",
                    shouldRefresh: true,
                    legacyGraceUntil: nil
                )
            }
            guard graceUntil >= now else {
                return LicenseAccessDecision(
                    mode: .denied,
                    message: "This bounded rollback activation requires an internet connection. The saved license was preserved.",
                    shouldRefresh: true,
                    legacyGraceUntil: graceUntil
                )
            }
            return LicenseAccessDecision(
                mode: .legacyMigrationPreserved,
                message: "Rollback activation preserved during secure receipt migration.",
                shouldRefresh: true,
                legacyGraceUntil: graceUntil
            )
        }

        return LicenseAccessDecision(
            mode: .legacyMigrationPreserved,
            message: "Existing license preserved on this Mac during secure receipt migration.",
            shouldRefresh: true,
            legacyGraceUntil: nil
        )
    }

    func securityStateForExistingLegacyCache(
        from state: LicenseSecurityState,
        now: Date = Date()
    ) -> LicenseSecurityState {
        guard state.legacyGraceStartedAt == nil else { return state }
        var updated = state
        updated.legacyGraceStartedAt = Self.string(from: now)
        // Intentionally no deadline: a cache that was already active on this
        // machine is grandfathered so an app update cannot revoke paid access.
        updated.legacyGraceUntil = nil
        return updated
    }

    func securityStateRecoveringCompactReceipt(
        from state: LicenseSecurityState,
        legacyRecord: LegacyLicenseRecord,
        expected: LicenseReceiptExpectation,
        now: Date = Date()
    ) -> LicenseSecurityState {
        let candidate = legacyRecord.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.split(separator: ".", omittingEmptySubsequences: false).count == 3,
              (try? verifier.verify(compactJWS: candidate, expected: expected, now: now)) != nil else {
            return state
        }
        if let current = state.signedReceipt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty,
           (try? verifier.verify(compactJWS: current, expected: expected, now: now)) != nil {
            return state
        }
        var recovered = state
        recovered.signedReceipt = candidate
        return recovered
    }

    func securityStateStartingBoundedRollback(
        from state: LicenseSecurityState,
        expected: LicenseReceiptExpectation,
        now: Date = Date()
    ) -> LicenseSecurityState {
        var updated = state
        updated.legacyGraceStartedAt = Self.string(from: now)
        updated.legacyGraceUntil = Self.string(from: now.addingTimeInterval(policy.legacyGraceInterval))
        updated.boundedLegacyMachineHash = Self.machineHash(expected)
        updated.boundedLegacyEmailHash = Self.emailHash(expected)
        updated.boundedLegacyKeyHash = Self.keyHash(expected)
        return updated
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func machineHash(_ expected: LicenseReceiptExpectation) -> String {
        LicenseReceiptVerifier.boundHash(
            domain: "localclaw:machine:v1",
            normalizedValue: LicenseReceiptVerifier.normalizeMachineID(expected.machineID)
        )
    }

    private static func emailHash(_ expected: LicenseReceiptExpectation) -> String {
        LicenseReceiptVerifier.boundHash(
            domain: "localclaw:email:v1",
            normalizedValue: LicenseReceiptVerifier.normalizeEmail(expected.email)
        )
    }

    private static func keyHash(_ expected: LicenseReceiptExpectation) -> String {
        LicenseReceiptVerifier.boundHash(
            domain: "localclaw:key:v1",
            normalizedValue: LicenseReceiptVerifier.normalizeLicenseKey(expected.licenseKey)
        )
    }
}

struct LicenseMigrationCoordinator: Sendable {
    typealias ExchangeOperation = @Sendable (LicenseExchangeRequest) async throws -> LicenseExchangeResponse

    private let verifier: LicenseReceiptVerifier
    private let evaluator: LicenseMigrationEvaluator

    init(verifier: LicenseReceiptVerifier, policy: LicenseMigrationPolicy = LicenseMigrationPolicy()) {
        self.verifier = verifier
        self.evaluator = LicenseMigrationEvaluator(verifier: verifier, policy: policy)
    }

    func refresh(
        record: LegacyLicenseRecord,
        securityState: LicenseSecurityState,
        expected: LicenseReceiptExpectation,
        now: Date = Date(),
        exchange: ExchangeOperation
    ) async -> LicenseRefreshResult {
        var updatedState = evaluator.securityStateForExistingLegacyCache(from: securityState, now: now)
        updatedState.lastRefreshAttemptAt = Self.string(from: now)

        do {
            let response = try await exchange(LicenseExchangeRequest(
                email: record.email,
                licenseKey: record.licenseKey,
                machineId: expected.machineID,
                appVersion: expected.appVersion,
                currentReceipt: updatedState.signedReceipt
            ))
            guard response.ok else {
                throw LicenseRefreshError.serverRefused(response.message ?? "License refresh refused.")
            }
            guard response.mode == "secure" else {
                // Rollback responses are intentionally not promoted to trusted state.
                // The pre-existing cache remains available only through bounded grace.
                throw LicenseRefreshError.unsignedRollbackNotAccepted
            }
            guard response.receiptFormat == "JWS-Compact" else {
                throw LicenseRefreshError.invalidSecureReceiptFormat
            }
            let receiptAlias = response.receipt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tokenAlias = response.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !receiptAlias.isEmpty, !tokenAlias.isEmpty, receiptAlias != tokenAlias {
                throw LicenseRefreshError.secureReceiptAliasesDiffer
            }
            let receipt = receiptAlias.isEmpty ? tokenAlias : receiptAlias
            guard !receipt.isEmpty else { throw LicenseRefreshError.secureReceiptMissing }
            _ = try verifier.verify(compactJWS: receipt, expected: expected, now: now)

            updatedState.signedReceipt = receipt
            updatedState.lastRefreshSucceededAt = Self.string(from: now)
            let decision = evaluator.evaluate(
                record: record,
                securityState: updatedState,
                expected: expected,
                now: now
            )
            return LicenseRefreshResult(
                record: record,
                securityState: updatedState,
                decision: decision,
                refreshError: nil
            )
        } catch {
            let decision = evaluator.evaluate(
                record: record,
                securityState: updatedState,
                expected: expected,
                now: now
            )
            return LicenseRefreshResult(
                record: record,
                securityState: updatedState,
                decision: decision,
                refreshError: error.localizedDescription
            )
        }
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct LicenseRecordStore: Sendable {
    let legacyRecordURL: URL
    let securityStateURL: URL
    let legacyBackupURL: URL

    init(legacyRecordURL: URL, securityStateURL: URL? = nil, legacyBackupURL: URL? = nil) {
        self.legacyRecordURL = legacyRecordURL
        self.securityStateURL = securityStateURL
            ?? legacyRecordURL.deletingLastPathComponent().appendingPathComponent("license-security.json")
        self.legacyBackupURL = legacyBackupURL
            ?? legacyRecordURL.deletingLastPathComponent().appendingPathComponent("license-presecure-backup.json")
    }

    func loadLegacyRecord() throws -> LegacyLicenseRecord {
        try JSONDecoder().decode(LegacyLicenseRecord.self, from: Data(contentsOf: legacyRecordURL))
    }

    func loadSecurityState() -> LicenseSecurityState {
        guard let data = try? Data(contentsOf: securityStateURL),
              let state = try? JSONDecoder().decode(LicenseSecurityState.self, from: data),
              state.schemaVersion == LicenseSecurityState.currentSchemaVersion else {
            return LicenseSecurityState()
        }
        return state
    }

    func saveSecurityState(_ state: LicenseSecurityState) throws {
        let directory = securityStateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(state).write(to: securityStateURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: securityStateURL.path)
    }

    func saveLegacyRecordPreservingExisting(_ record: LegacyLicenseRecord) throws {
        let directory = legacyRecordURL.deletingLastPathComponent()
        let encodedRecord = try JSONEncoder().encode(record)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        if let existing = try? Data(contentsOf: legacyRecordURL),
           existing != encodedRecord,
           !FileManager.default.fileExists(atPath: legacyBackupURL.path) {
            try existing.write(to: legacyBackupURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyBackupURL.path)
        }

        try encodedRecord.write(to: legacyRecordURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyRecordURL.path)
    }

    func repairPermissionsIfPresent() throws {
        let directory = legacyRecordURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        if FileManager.default.fileExists(atPath: legacyRecordURL.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyRecordURL.path)
        }
        if FileManager.default.fileExists(atPath: securityStateURL.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: securityStateURL.path)
        }
        if FileManager.default.fileExists(atPath: legacyBackupURL.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyBackupURL.path)
        }
    }
}
