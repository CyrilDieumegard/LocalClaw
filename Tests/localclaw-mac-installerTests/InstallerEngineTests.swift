import Foundation
import Testing
@testable import localclaw_mac_installer

struct InstallerEngineTests {
    @Test func recommendationForLowMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M1", memoryGB: 8, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Nemotron 3 Nano 4B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForMidMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M2", memoryGB: 16, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Nemotron 3 Nano 4B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForHighMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M4", memoryGB: 36, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3.5 35B-A3B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func versionInfoFallbackWhenCommandMissing() {
        let engine = InstallerEngine()
        let version = engine.installedVersion(for: "definitely-not-a-command")
        #expect(version == "Not installed")
    }

    @Test func redactsSecretsFromConfigJSON() {
        let raw = """
        {
          "gateway": {
            "auth": {
              "token": "super-secret-token"
            }
          },
          "auth": {
            "profiles": {
              "openrouter:default": {
                "type": "api_key",
                "provider": "openrouter",
                "key": "sk-or-secret"
              }
            }
          },
          "agents": {
            "defaults": {
              "model": {
                "primary": "openrouter/moonshotai/kimi-k2.5"
              }
            }
          }
        }
        """

        let redacted = SecretRedactor.redactConfigText(raw)

        #expect(!redacted.contains("super-secret-token"))
        #expect(!redacted.contains("sk-or-secret"))
        #expect(redacted.contains("<redacted>"))
        #expect(redacted.contains("kimi-k2.5"))
    }

    @Test func computesSHA256ForDownloadedInstaller() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-sha-test-\(UUID().uuidString)")
        try "LocalClaw".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = try InstallerViewModel.sha256Hex(for: url)

        #expect(hash == "a1c2aaf18a271d28ac8433e25331c5ae53b09ff48b1db8b960c65e243545aea0")
    }

    @Test func shellSingleQuoteEscapesApostrophes() {
        let quoted = InstallerViewModel.shellSingleQuote("/Users/cyril/LocalClaw's update/localclaw.dmg")

        #expect(quoted == #"'/Users/cyril/LocalClaw'"'"'s update/localclaw.dmg'"#)
    }
}
