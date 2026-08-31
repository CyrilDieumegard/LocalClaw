import AppKit
import SwiftUI
import Testing
@testable import localclaw_mac_installer

struct StorageRecoveryViewTests {
    @MainActor @Test func rendersStorageRecoveryWithoutTouchingTheLiveRuntime() throws {
        for dark in [false, true] {
            let model = StorageRecoveryModel(home: URL(fileURLWithPath: "/private/tmp/localclaw-storage-render-fixture"))
            model.snapshot = .init(available: 0, required: 24_000_000_000, cacheBytes: 9_000_000_000,
                                   backupBytes: 24_000_000_000,
                                   detail: "Conservative offline backup estimate plus update reserve. Actual free space is checked again before repair.")
            model.busy = true // Keep this rendering fixture independent of the machine's disk.
            let view = StorageRecoveryView(model: model, diagnostic: "npm error ENOSPC: no space left on device", retry: {})
                .background(Color(nsColor: dark ? NSColor(calibratedWhite: 0.14, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)))
                .preferredColorScheme(dark ? .dark : .light)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            defer { window.orderOut(nil); window.contentView = nil }
            host.frame = NSRect(x: 0, y: 0, width: 620, height: 520)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(data.count > 5_000)
            try data.write(to: URL(fileURLWithPath: "/private/tmp/localclaw-storage-recovery-\(dark ? "dark" : "light").png"))
        }
    }
}
