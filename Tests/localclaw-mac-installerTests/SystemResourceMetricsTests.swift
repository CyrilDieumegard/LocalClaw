import Foundation
import Testing
@testable import localclaw_mac_installer

struct SystemResourceMetricsTests {
    private func vmStat(pageSize: Int = 16384, cache: Int = 400_000) -> String {
        """
        Mach Virtual Memory Statistics: (page size of \(pageSize) bytes)
        Pages free: 10000.
        Pages active: 300000.
        Pages inactive: 400000.
        Pages speculative: 50000.
        Pages wired down: 100000.
        Pages purgeable: 20000.
        File-backed pages: \(cache).
        Anonymous pages: 350000.
        Pages stored in compressor: 800000.
        Pages occupied by compressor: 40000.
        """
    }

    @Test func reclaimableCacheIsAvailableAndNotCountedAsUsed() {
        let result = SystemResourceMetrics.memory(fromVMStat: vmStat(), totalBytes: 16 * 1_073_741_824)
        let available = Double(430_000 * 16384) / 1_073_741_824
        #expect(result.availableGB == available)
        #expect(result.usedGB == 16 - available)
        #expect(result.usedGB + result.availableGB == 16)
        // A larger logical compressor or different active/inactive split must not
        // inflate the physical total or count speculative cache a second time.
        let changed = vmStat().replacingOccurrences(of: "800000.", with: "900000.")
        #expect(SystemResourceMetrics.memory(fromVMStat: changed, totalBytes: 16 * 1_073_741_824).usedGB == result.usedGB)
    }

    @Test func intelPagesUseReportedSize() {
        let intel = SystemResourceMetrics.memory(fromVMStat: vmStat(pageSize: 4096), totalBytes: 16 * 1_073_741_824)
        let silicon = SystemResourceMetrics.memory(fromVMStat: vmStat(), totalBytes: 16 * 1_073_741_824)
        #expect(intel.availableGB * 4 == silicon.availableGB)
        #expect(intel.usedGB + intel.availableGB == 16)
    }

    @Test func invalidMemoryOutputDoesNotInventUsage() {
        #expect(SystemResourceMetrics.memory(fromVMStat: "vm_stat failed", totalBytes: 16 * 1_073_741_824).usedGB == 0)
        #expect(SystemResourceMetrics.memory(fromVMStat: "", totalBytes: 0).availableGB == 0)
        let sample = vmStat().replacingOccurrences(of: "Pages purgeable: 20000.", with: "Pages purgeable: 99999999.")
        let result = SystemResourceMetrics.memory(fromVMStat: sample, totalBytes: 16 * 1_073_741_824)
        #expect(result.usedGB == 0)
        #expect(result.availableGB == 16)
    }

    @Test func bareNodeAndRenamedOpenClawAreCountedWithoutPath() {
        let sample = """
        101 1 2048 node
        102 1 4096 /opt/homebrew/bin/node
        103 1 8192 openclaw-gateway
        104 103 1024 /usr/bin/helper
        105 1 1024 /opt/homebrew/bin/node
        """
        let result = SystemResourceMetrics.processMemory(fromPS: sample, arguments: "102 /opt/homebrew/bin/node /Users/me/.local/lib/node_modules/openclaw/openclaw.mjs gateway")
        #expect(result.nodeMB == 15)
        #expect(result.openclawMB == 13)
        #expect(result.lmStudioMB == 0)
    }

    @Test func lmStudioHelpersIncludedAndPIDsNotDoubleCounted() {
        let sample = """
        203 202 512 /tmp/model-worker
        202 201 512 /Applications/LM Studio.app/Contents/Frameworks/LM Studio Helper.app/Contents/MacOS/LM Studio Helper
        201 1 1024 /Applications/LM Studio.app/Contents/MacOS/LM Studio
        204 203 1024 /Users/me/.lmstudio/.internal/utils/node
        201 1 1024 /Applications/LM Studio.app/Contents/MacOS/LM Studio
        """
        let result = SystemResourceMetrics.processMemory(fromPS: sample)
        #expect(result.lmStudioMB == 3)
        #expect(result.nodeMB == 1)
    }

    @Test func incidentalNamesAndMalformedRowsAreNotProcesses() {
        let sample = """
        1 0 999999 /bin/zsh
        2 1 999999 grep
        3 1 999999 /bin/echo
        4 1 999999 /usr/bin/node
        5 1 -100 node
        invalid row
        """
        let result = SystemResourceMetrics.processMemory(fromPS: sample, arguments: "1 /bin/zsh -c /openclaw /node /LM Studio.app/Contents/MacOS/LM Studio\n4 /usr/bin/node /tmp/server.js --message openclaw.mjs")
        #expect(result.openclawMB == 0)
        #expect(result.lmStudioMB == 0)
        #expect(result.nodeMB == 999999 / 1024)
    }
}
