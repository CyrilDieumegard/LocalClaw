import CryptoKit
import Foundation
import Testing
@testable import localclaw_mac_installer

struct LicenseSecurityTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let expected = LicenseReceiptExpectation(
        email: " Client@Example.com ",
        licenseKey: " lcw-paid-0001 ",
        machineID: "MAC-123",
        appVersion: "1.0.202"
    )

    @Test func productionTrustEmbedsOnlyTheExpectedThirtyTwoBytePublicKey() throws {
        let raw = try #require(LicenseBase64URL.decode(LicenseProductionTrust.currentPublicKeyBase64URL))

        #expect(LicenseProductionTrust.currentKeyID == "localclaw-license-2026-09-01")
        #expect(raw.count == 32)
        _ = try LicenseProductionTrust.keyRing()
    }

    @Test func fixtureUsingProductionKidIsNeverTrustedByProductionKeyRing() throws {
        let fixture = try SigningFixture(kid: LicenseProductionTrust.currentKeyID)
        let fixtureReceipt = try fixture.receipt(expected: expected, now: now)
        let productionVerifier = try LicenseProductionTrust.verifier()

        #expect(throws: LicenseReceiptValidationError.invalidSignature) {
            try productionVerifier.verify(compactJWS: fixtureReceipt, expected: expected, now: now)
        }
    }

    @Test func validSignedReceiptVerifiesAllBindingsAndLifetimeSeparately() throws {
        let fixture = try SigningFixture()
        let receipt = try fixture.receipt(expected: expected, now: now)

        let verified = try fixture.verifier.verify(
            compactJWS: receipt,
            expected: expected,
            now: now
        )

        #expect(verified.header.kid == fixture.kid)
        #expect(verified.claims.audience == "io.localclaw.installer")
        #expect(verified.isLifetimeEntitlement)
        #expect(verified.entitlementExpiration == nil)
        #expect(verified.receiptExpiration > now)
    }

    @Test func expiredReceiptIsRejectedEvenForLifetimeLicense() throws {
        let fixture = try SigningFixture()
        let receipt = try fixture.receipt(
            expected: expected,
            now: now,
            issuedAt: Int64(now.timeIntervalSince1970) - 7_200,
            expiresAt: Int64(now.timeIntervalSince1970) - 600
        )

        #expect(throws: LicenseReceiptValidationError.receiptExpired) {
            try fixture.verifier.verify(compactJWS: receipt, expected: expected, now: now)
        }
    }

    @Test func previouslyValidReceiptGetsOnlyFourteenDaysOfflineRefreshGrace() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(
            verifier: fixture.verifier,
            policy: LicenseMigrationPolicy(expiredReceiptGraceInterval: 14 * 24 * 60 * 60)
        )
        let oneDayExpired = try fixture.receipt(
            expected: expected,
            now: now,
            issuedAt: Int64(now.timeIntervalSince1970) - 200 * 24 * 60 * 60,
            expiresAt: Int64(now.timeIntervalSince1970) - 24 * 60 * 60
        )
        let state = LicenseSecurityState(signedReceipt: oneDayExpired)

        let decision = evaluator.evaluate(
            record: legacyRecord(token: "opaque-existing-token"),
            securityState: state,
            expected: expected,
            now: now
        )

        #expect(decision.mode == .verifiedReceiptRefreshRecommended)
        #expect(decision.allowsUse)
        #expect(decision.shouldRefresh)
    }

    @Test func expiredSignedReceiptDoesNotFallBackToUnlimitedLegacyAfterRefreshGrace() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(
            verifier: fixture.verifier,
            policy: LicenseMigrationPolicy(expiredReceiptGraceInterval: 14 * 24 * 60 * 60)
        )
        let thirtyDaysExpired = try fixture.receipt(
            expected: expected,
            now: now,
            issuedAt: Int64(now.timeIntervalSince1970) - 220 * 24 * 60 * 60,
            expiresAt: Int64(now.timeIntervalSince1970) - 30 * 24 * 60 * 60
        )
        let state = LicenseSecurityState(signedReceipt: thirtyDaysExpired)

        let decision = evaluator.evaluate(
            record: legacyRecord(token: "opaque-existing-token"),
            securityState: state,
            expected: expected,
            now: now
        )

        #expect(decision.mode == .denied)
        #expect(!decision.allowsUse)
        #expect(decision.shouldRefresh)
    }

    @Test func validReceiptForAnotherMachineIsRejected() throws {
        let fixture = try SigningFixture()
        let receipt = try fixture.receipt(expected: expected, now: now)
        let anotherMac = LicenseReceiptExpectation(
            email: expected.email,
            licenseKey: expected.licenseKey,
            machineID: "MAC-OTHER",
            appVersion: expected.appVersion
        )

        #expect(throws: LicenseReceiptValidationError.machineMismatch) {
            try fixture.verifier.verify(compactJWS: receipt, expected: anotherMac, now: now)
        }
    }

    @Test func receiptWithWrongSignatureIsRejected() throws {
        let trusted = try SigningFixture(kid: "rotation-current")
        let attacker = try SigningFixture(kid: "rotation-current")
        let forged = try attacker.receipt(expected: expected, now: now)

        #expect(throws: LicenseReceiptValidationError.invalidSignature) {
            try trusted.verifier.verify(compactJWS: forged, expected: expected, now: now)
        }
    }

    @Test func unknownRotationKidIsRejected() throws {
        let trusted = try SigningFixture(kid: "rotation-current")
        let next = try SigningFixture(kid: "rotation-next")
        let receipt = try next.receipt(expected: expected, now: now)

        #expect(throws: LicenseReceiptValidationError.unknownKeyIdentifier) {
            try trusted.verifier.verify(compactJWS: receipt, expected: expected, now: now)
        }
    }

    @Test func keyRingAcceptsCurrentAndPreviousRotationKeys() throws {
        let currentPrivate = Curve25519.Signing.PrivateKey()
        let previousPrivate = Curve25519.Signing.PrivateKey()
        let ring = try LicenseReceiptKeyRing(keys: [
            LicenseReceiptKey(kid: "current", rawPublicKey: currentPrivate.publicKey.rawRepresentation),
            LicenseReceiptKey(kid: "previous", rawPublicKey: previousPrivate.publicKey.rawRepresentation)
        ])
        let previous = SigningFixture(kid: "previous", privateKey: previousPrivate, keyRing: ring)
        let receipt = try previous.receipt(expected: expected, now: now)

        _ = try previous.verifier.verify(compactJWS: receipt, expected: expected, now: now)
    }

    @Test(arguments: ["offline-token", "customer-override-token", "eyJvayI6dHJ1ZX0="])
    func existingLegacyCachesRemainActiveDuringMigration(token: String) throws {
        let fixture = try SigningFixture()
        let policy = LicenseMigrationPolicy(legacyGraceInterval: 30 * 24 * 60 * 60)
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier, policy: policy)
        let record = legacyRecord(token: token)
        let state = evaluator.securityStateForExistingLegacyCache(from: LicenseSecurityState(), now: now)

        let decision = evaluator.evaluate(
            record: record,
            securityState: state,
            expected: expected,
            now: now
        )

        #expect(decision.mode == .legacyMigrationPreserved)
        #expect(decision.allowsUse)
        #expect(decision.shouldRefresh)
        #expect(decision.legacyGraceUntil == nil)
    }

    @Test func existingLegacyCacheRemainsActiveAfterOneYearOffline() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)
        let record = legacyRecord(token: "opaque-existing-token")
        let migrationStarted = now.addingTimeInterval(-365 * 24 * 60 * 60)
        let state = LicenseSecurityState(
            signedReceipt: nil,
            legacyGraceStartedAt: ISO8601DateFormatter().string(from: migrationStarted),
            legacyGraceUntil: nil,
            lastRefreshAttemptAt: ISO8601DateFormatter().string(from: migrationStarted),
            lastRefreshSucceededAt: nil
        )

        let decision = evaluator.evaluate(
            record: record,
            securityState: state,
            expected: expected,
            now: now
        )

        #expect(decision.mode == .legacyMigrationPreserved)
        #expect(decision.allowsUse)
        #expect(decision.shouldRefresh)
        #expect(decision.legacyGraceUntil == nil)
    }

    @Test func existingLegacyCacheForAnotherMachineIsRefusedWithoutMutation() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)
        let record = legacyRecord(token: "opaque-existing-token")
        let anotherMac = LicenseReceiptExpectation(
            email: expected.email,
            licenseKey: expected.licenseKey,
            machineID: "MAC-OTHER",
            appVersion: expected.appVersion
        )

        let decision = evaluator.evaluate(
            record: record,
            securityState: LicenseSecurityState(),
            expected: anotherMac,
            now: now
        )

        #expect(!decision.allowsUse)
        #expect(decision.mode == .denied)
        #expect(record.machineId == "MAC-123")
        #expect(record.licenseKey == "LCW-PAID-0001")
    }

    @Test func unavailableNetworkPreservesLegacyRecordAndAllowsGrace() async throws {
        let fixture = try SigningFixture()
        let coordinator = LicenseMigrationCoordinator(
            verifier: fixture.verifier,
            policy: LicenseMigrationPolicy(legacyGraceInterval: 30 * 24 * 60 * 60)
        )
        let record = legacyRecord(token: "customer-override-token")

        let result = await coordinator.refresh(
            record: record,
            securityState: LicenseSecurityState(),
            expected: expected,
            now: now
        ) { _ in
            throw URLError(.notConnectedToInternet)
        }

        #expect(result.record == record)
        #expect(result.securityState.signedReceipt == nil)
        #expect(result.securityState.legacyGraceStartedAt != nil)
        #expect(result.decision.mode == .legacyMigrationPreserved)
        #expect(result.decision.allowsUse)
        #expect(result.refreshError != nil)
    }

    @Test func invalidMigrationReceiptFallsBackToUnmodifiedLegacyGrace() async throws {
        let trusted = try SigningFixture(kid: "trusted")
        let attacker = try SigningFixture(kid: "trusted")
        let forged = try attacker.receipt(expected: expected, now: now)
        let coordinator = LicenseMigrationCoordinator(verifier: trusted.verifier)
        let record = legacyRecord(token: "opaque-existing-token")

        let result = await coordinator.refresh(
            record: record,
            securityState: LicenseSecurityState(),
            expected: expected,
            now: now
        ) { _ in
            LicenseExchangeResponse(
                ok: true,
                mode: "secure",
                token: forged,
                receipt: forged,
                receiptFormat: "JWS-Compact",
                expiresAt: nil,
                license: nil,
                message: "Activated"
            )
        }

        #expect(result.record == record)
        #expect(result.securityState.signedReceipt == nil)
        #expect(result.decision.mode == .legacyMigrationPreserved)
        #expect(result.refreshError != nil)
    }

    @Test func tamperedReceiptAlreadyStoredAfterMigrationIsAuthoritativeAndDenied() throws {
        let fixture = try SigningFixture(kid: "trusted")
        let receipt = try fixture.receipt(expected: expected, now: now)
        var segments = receipt.split(separator: ".").map(String.init)
        var signature = try #require(LicenseBase64URL.decode(segments[2]))
        signature[signature.startIndex] ^= 0x01
        segments[2] = LicenseBase64URL.encode(signature)
        let tampered = segments.joined(separator: ".")
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)

        let decision = evaluator.evaluate(
            record: legacyRecord(token: "opaque-pre-migration-token"),
            securityState: LicenseSecurityState(signedReceipt: tampered),
            expected: expected,
            now: now
        )

        #expect(decision.mode == .denied)
        #expect(!decision.allowsUse)
        #expect(decision.shouldRefresh)
    }

    @Test func unknownKidAlreadyStoredAfterMigrationCannotFallBackToLegacy() throws {
        let trusted = try SigningFixture(kid: "trusted")
        let rotatedUnknown = try SigningFixture(kid: "unknown")
        let receipt = try rotatedUnknown.receipt(expected: expected, now: now)
        let evaluator = LicenseMigrationEvaluator(verifier: trusted.verifier)

        let decision = evaluator.evaluate(
            record: legacyRecord(token: "opaque-pre-migration-token"),
            securityState: LicenseSecurityState(signedReceipt: receipt),
            expected: expected,
            now: now
        )

        #expect(decision.mode == .denied)
        #expect(!decision.allowsUse)
        #expect(decision.shouldRefresh)
    }

    @Test func missingSidecarRecoversAndVerifiesCompactJWSToken() throws {
        let fixture = try SigningFixture()
        let receipt = try fixture.receipt(expected: expected, now: now)
        let record = legacyRecord(token: receipt)
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)
        let recovered = evaluator.securityStateRecoveringCompactReceipt(
            from: LicenseSecurityState(),
            legacyRecord: record,
            expected: expected,
            now: now
        )

        let decision = evaluator.evaluate(
            record: record,
            securityState: recovered,
            expected: expected,
            now: now
        )

        #expect(recovered.signedReceipt == receipt)
        #expect(decision.mode == .verifiedReceipt)
        #expect(decision.allowsUse)
    }

    @Test func missingSidecarWithForgedCompactTokenIsSecureDenied() throws {
        let trusted = try SigningFixture(kid: "trusted")
        let attacker = try SigningFixture(kid: "trusted")
        let forged = try attacker.receipt(expected: expected, now: now)
        let record = legacyRecord(token: forged)
        let evaluator = LicenseMigrationEvaluator(verifier: trusted.verifier)
        let recovered = evaluator.securityStateRecoveringCompactReceipt(
            from: LicenseSecurityState(),
            legacyRecord: record,
            expected: expected,
            now: now
        )

        let decision = evaluator.evaluate(
            record: record,
            securityState: recovered,
            expected: expected,
            now: now
        )

        #expect(recovered.signedReceipt == nil)
        #expect(decision.mode == .denied)
        #expect(!decision.allowsUse)
        #expect(decision.shouldRefresh)
    }

    @Test func validNewJWSTokenReplacesStaleSidecarFromPreviousIdentity() throws {
        let fixture = try SigningFixture()
        let oldExpectation = LicenseReceiptExpectation(
            email: "old@example.com",
            licenseKey: "LCW-OLD-0001",
            machineID: expected.machineID,
            appVersion: expected.appVersion
        )
        let staleReceipt = try fixture.receipt(expected: oldExpectation, now: now)
        let currentReceipt = try fixture.receipt(expected: expected, now: now)
        let record = legacyRecord(token: currentReceipt)
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)

        let recovered = evaluator.securityStateRecoveringCompactReceipt(
            from: LicenseSecurityState(signedReceipt: staleReceipt),
            legacyRecord: record,
            expected: expected,
            now: now
        )
        let decision = evaluator.evaluate(
            record: record,
            securityState: recovered,
            expected: expected,
            now: now
        )

        #expect(recovered.signedReceipt == currentReceipt)
        #expect(decision.mode == .verifiedReceipt)
        #expect(decision.allowsUse)
    }

    @Test func signedReceiptRefreshDoesNotReplaceLegacyKeyOrToken() async throws {
        let fixture = try SigningFixture()
        let receipt = try fixture.receipt(expected: expected, now: now)
        let coordinator = LicenseMigrationCoordinator(verifier: fixture.verifier)
        let record = legacyRecord(token: "opaque-existing-token")

        let result = await coordinator.refresh(
            record: record,
            securityState: LicenseSecurityState(),
            expected: expected,
            now: now
        ) { request in
            #expect(request.licenseKey == record.licenseKey)
            #expect(request.currentReceipt == nil)
            return LicenseExchangeResponse(
                ok: true,
                mode: "secure",
                token: receipt,
                receipt: receipt,
                receiptFormat: "JWS-Compact",
                expiresAt: ISO8601DateFormatter().string(from: self.now.addingTimeInterval(180 * 24 * 60 * 60)),
                license: .init(id: UUID().uuidString, status: "active", entitlement: "lifetime", machineLimit: 3),
                message: "Activated"
            )
        }

        #expect(result.record == record)
        #expect(result.securityState.signedReceipt == receipt)
        #expect(result.decision.allowsUse)
        #expect(result.refreshError == nil)
    }

    @Test func migrationSidecarAndPermissionRepairNeverRewriteLegacyJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-license-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("license.json")
        let original = Data(#"{"email":"client@example.com","licenseKey":"LCW-PAID-0001","token":"opaque","machineId":"MAC-123","activatedAt":"2033-05-18T03:33:20Z","expiresAt":null,"supportNote":"must survive"}"#.utf8)
        try original.write(to: legacyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyURL.path)
        let store = LicenseRecordStore(legacyRecordURL: legacyURL)

        let loaded = try store.loadLegacyRecord()
        #expect(loaded.licenseKey == "LCW-PAID-0001")
        try store.saveSecurityState(LicenseSecurityState(
            signedReceipt: nil,
            legacyGraceStartedAt: "2033-05-18T03:33:20Z",
            legacyGraceUntil: "2033-06-17T03:33:20Z",
            lastRefreshAttemptAt: nil,
            lastRefreshSucceededAt: nil
        ))
        try store.repairPermissionsIfPresent()

        #expect(try Data(contentsOf: legacyURL) == original)
        let legacyMode = try #require(FileManager.default.attributesOfItem(atPath: legacyURL.path)[.posixPermissions] as? NSNumber)
        let securityMode = try #require(FileManager.default.attributesOfItem(atPath: store.securityStateURL.path)[.posixPermissions] as? NSNumber)
        #expect(legacyMode.intValue & 0o777 == 0o600)
        #expect(securityMode.intValue & 0o777 == 0o600)
    }

    @Test func boundedRollbackExpirationDeniesButDoesNotMutateOrDeleteRecord() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)
        let record = legacyRecord(token: "opaque-existing-token")
        let expiredState = evaluator.securityStateStartingBoundedRollback(
            from: LicenseSecurityState(),
            expected: expected,
            now: now.addingTimeInterval(-60 * 24 * 60 * 60)
        )

        let decision = evaluator.evaluate(
            record: record,
            securityState: expiredState,
            expected: expected,
            now: now
        )

        #expect(!decision.allowsUse)
        #expect(decision.shouldRefresh)
        #expect(record.licenseKey == expected.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    @Test func boundedRollbackSidecarForNewIdentityCannotDowngradeOldCachedIdentity() throws {
        let fixture = try SigningFixture()
        let evaluator = LicenseMigrationEvaluator(verifier: fixture.verifier)
        let newExpectation = LicenseReceiptExpectation(
            email: "new@example.com",
            licenseKey: "LCW-NEW-0002",
            machineID: expected.machineID,
            appVersion: expected.appVersion
        )
        let newBoundedState = evaluator.securityStateStartingBoundedRollback(
            from: LicenseSecurityState(),
            expected: newExpectation,
            now: now.addingTimeInterval(-60 * 24 * 60 * 60)
        )

        let oldDecision = evaluator.evaluate(
            record: legacyRecord(token: "opaque-existing-token"),
            securityState: newBoundedState,
            expected: expected,
            now: now
        )

        #expect(oldDecision.mode == .legacyMigrationPreserved)
        #expect(oldDecision.allowsUse)
        #expect(oldDecision.legacyGraceUntil == nil)
    }

    private func legacyRecord(token: String) -> LegacyLicenseRecord {
        LegacyLicenseRecord(
            email: LicenseReceiptVerifier.normalizeEmail(expected.email),
            licenseKey: LicenseReceiptVerifier.normalizeLicenseKey(expected.licenseKey),
            token: token,
            machineId: expected.machineID,
            activatedAt: ISO8601DateFormatter().string(from: now),
            expiresAt: nil
        )
    }
}

private struct SigningFixture {
    let kid: String
    let privateKey: Curve25519.Signing.PrivateKey
    let verifier: LicenseReceiptVerifier

    init(kid: String = "fixture-only", privateKey: Curve25519.Signing.PrivateKey? = nil) throws {
        let signingKey = privateKey ?? Curve25519.Signing.PrivateKey()
        let ring = try LicenseReceiptKeyRing(keys: [
            LicenseReceiptKey(kid: kid, rawPublicKey: signingKey.publicKey.rawRepresentation)
        ])
        self.init(kid: kid, privateKey: signingKey, keyRing: ring)
    }

    init(kid: String, privateKey: Curve25519.Signing.PrivateKey, keyRing: LicenseReceiptKeyRing) {
        self.kid = kid
        self.privateKey = privateKey
        self.verifier = LicenseReceiptVerifier(keyRing: keyRing, clockSkew: 0)
    }

    func receipt(
        expected: LicenseReceiptExpectation,
        now: Date,
        issuedAt: Int64? = nil,
        expiresAt: Int64? = nil
    ) throws -> String {
        let issued = issuedAt ?? Int64(now.timeIntervalSince1970) - 60
        let expiration = expiresAt ?? Int64(now.timeIntervalSince1970) + 180 * 24 * 60 * 60
        let licenseID = UUID().uuidString.lowercased()
        let header = #"{"alg":"EdDSA","typ":"localclaw-license+jwt","kid":"\#(kid)"}"#
        let claims = LicenseReceiptClaims(
            issuer: LicenseReceiptVerifier.issuer,
            audience: LicenseReceiptVerifier.audience,
            schema: LicenseReceiptVerifier.schema,
            jti: UUID().uuidString.lowercased(),
            subject: "license:\(licenseID)",
            issuedAt: issued,
            notBefore: issued - 60,
            expiresAt: expiration,
            licenseID: licenseID,
            licenseVersion: 1,
            product: LicenseReceiptVerifier.product,
            entitlement: "lifetime",
            entitlementExpiresAt: nil,
            status: "active",
            source: "legacy_migration",
            machineHash: LicenseReceiptVerifier.boundHash(
                domain: "localclaw:machine:v1",
                normalizedValue: LicenseReceiptVerifier.normalizeMachineID(expected.machineID)
            ),
            emailHash: LicenseReceiptVerifier.boundHash(
                domain: "localclaw:email:v1",
                normalizedValue: LicenseReceiptVerifier.normalizeEmail(expected.email)
            ),
            keyHash: LicenseReceiptVerifier.boundHash(
                domain: "localclaw:key:v1",
                normalizedValue: LicenseReceiptVerifier.normalizeLicenseKey(expected.licenseKey)
            ),
            appVersion: expected.appVersion,
            minimumAppVersion: "1.0.0"
        )
        let headerSegment = LicenseBase64URL.encode(Data(header.utf8))
        let payloadSegment = LicenseBase64URL.encode(try JSONEncoder().encode(claims))
        let signingInput = Data("\(headerSegment).\(payloadSegment)".utf8)
        let signature = try privateKey.signature(for: signingInput)
        return "\(headerSegment).\(payloadSegment).\(LicenseBase64URL.encode(signature))"
    }
}
