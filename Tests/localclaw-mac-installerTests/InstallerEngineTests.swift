import Testing
@testable import localclaw_mac_installer

struct InstallerEngineTests {
    @Test func recommendationForLowMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M1", memoryGB: 8, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3 8B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForMidMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M2", memoryGB: 16, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3 14B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForHighMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M4", memoryGB: 36, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3 32B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func versionInfoFallbackWhenCommandMissing() {
        let engine = InstallerEngine()
        let version = engine.installedVersion(for: "definitely-not-a-command")
        #expect(version == "Not installed")
    }
}
