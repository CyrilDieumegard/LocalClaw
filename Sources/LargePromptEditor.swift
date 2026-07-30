import AppKit
import SwiftUI

enum PromptTextPolicy {
    static let largePromptThreshold = 8_000

    static func isLarge(_ text: String) -> Bool {
        text.utf8.count >= largePromptThreshold
    }

    static func hasContent(_ text: String) -> Bool {
        text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil
    }

    static func compactPreview(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let sample = String(text.prefix(limit * 2))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sample.prefix(limit))
    }

    static func sizeLabel(_ text: String) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }
}

private final class LargePromptTextView: NSTextView {
    var placeholder = ""
    var onCommandReturn: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        placeholder.draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "\r" {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

struct LargePromptEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 14
    var onSubmit: (() -> Void)?

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LargePromptEditor
        var isApplyingExternalUpdate = false

        init(parent: LargePromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = LargePromptTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.onCommandReturn = onSubmit
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.string = text
        textView.setAccessibilityLabel(placeholder)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LargePromptTextView else { return }
        context.coordinator.parent = self
        textView.placeholder = placeholder
        textView.onCommandReturn = onSubmit
        textView.font = NSFont.systemFont(ofSize: fontSize)
        if textView.string != text {
            context.coordinator.isApplyingExternalUpdate = true
            textView.string = text
            context.coordinator.isApplyingExternalUpdate = false
        }
        textView.needsDisplay = true
    }
}

struct PromptSizeIndicator: View {
    let text: String

    var body: some View {
        if PromptTextPolicy.isLarge(text) {
            Label("Large prompt · \(PromptTextPolicy.sizeLabel(text))", systemImage: "doc.text.magnifyingglass")
                .font(AppFont.bodySemi(10))
                .foregroundStyle(Color(NSColor.systemOrange))
        }
    }
}
