import Foundation
import Testing
@testable import localclaw_mac_installer

struct SecretRedactorTests {
    @Test func redactsCredentialsInsideStructuredErrorMessages() throws {
        let raw = #"{"error":{"message":"Provider rejected sk-exampleCloudTokenValue123456789"},"details":["Bearer short-value"],"status":"failed"}"#
        let result = SecretRedactor.redactConfigText(raw)
        #expect(!result.contains("sk-exampleCloudTokenValue123456789"))
        #expect(!result.contains("short-value"))
        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        #expect(json?["status"] as? String == "failed")
    }

    @Test func matchesAuthorizationAndAPIKeyHeadersWithoutCaseSensitivity() {
        let raw = #"{"headers":{"Authorization":"Basic fixture-auth","X-API-Key":"fixture-key"},"model":"openai/gpt-6"}"#
        let result = SecretRedactor.redactConfigText(raw)
        #expect(!result.contains("fixture-auth"))
        #expect(!result.contains("fixture-key"))
        #expect(result.contains("gpt-6"))
    }

    @Test func redactsEntireQuotedEnvironmentSecrets() {
        let raw = #"API_KEY="first second \"third\"" PASSWORD='another value' MODEL=openai/gpt-6"#
        let result = SecretRedactor.redactConfigText(raw)
        for part in ["first", "second", "third", "another", "value"] {
            #expect(!result.contains(part))
        }
        #expect(result.contains("MODEL=openai/gpt-6"))
    }

    @Test func redactsCompoundKeysInMixedJSONDiagnostics() {
        let raw = #"Update error: {"access_token":"first\"second","clientSecret":"private-value","status":"failed"}"#
        let result = SecretRedactor.redactConfigText(raw)
        #expect(!result.contains("first"))
        #expect(!result.contains("second"))
        #expect(!result.contains("private-value"))
        #expect(result.contains(#""status":"failed""#))
    }

    @Test func redactsBasicAndShortBearerHeaders() {
        let raw = "Authorization: Basic YTpi\nProxy-Authorization: Bearer short\nHTTP 401"
        let result = SecretRedactor.redactConfigText(raw)
        #expect(!result.contains("YTpi"))
        #expect(!result.contains("short"))
        #expect(result.contains("HTTP 401"))
    }

    @Test func preservesNonsecretURLParametersAndPlainDiagnostics() {
        let result = SecretRedactor.redactConfigText("https://example.test/?access_token=fixture-value&model=test\nGateway unavailable on port 18789")
        #expect(!result.contains("fixture-value"))
        #expect(result.contains("&model=test"))
        #expect(result.contains("Gateway unavailable on port 18789"))
    }
}
