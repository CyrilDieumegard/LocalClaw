import AppKit
import SwiftUI

/// A multiline editor with the usual chat keys on every supported macOS
/// version. NSTextView handles input methods and text selection as usual.
struct RoutedChatComposer: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let onSend: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let editor = SendingTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        editor.onSend = onSend
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SendingTextView else { return }
        editor.onSend = onSend
        editor.isEditable = isEditable
        if editor.string != text {
            let location = min(editor.selectedRange().location, (text as NSString).length)
            editor.string = text
            editor.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
        }
    }
}

private final class SendingTextView: NSTextView {
    var onSend: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn && !hasMarkedText() &&
            !modifiers.contains(.shift) && !modifiers.contains(.option) &&
            !modifiers.contains(.control) {
            onSend?(string)
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if !hasMarkedText() && !modifiers.contains(.shift) &&
            !modifiers.contains(.option) && !modifiers.contains(.control) {
            onSend?(string)
        } else {
            super.insertNewline(sender)
        }
    }
}
