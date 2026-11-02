import SwiftUI
import AppKit

/// Handle Return after IME composition, so selecting a Chinese candidate never sends.
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void
    var transparentBackground = false
    var onCompositionChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = ChatTextView()
        editor.isRichText = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.backgroundColor = .textBackgroundColor
        editor.drawsBackground = !transparentBackground
        editor.textContainerInset = NSSize(width: 6, height: 7)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onSend = onSend
        editor.onCompositionChange = onCompositionChange
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ChatTextView else { return }
        editor.onSend = onSend
        editor.onCompositionChange = onCompositionChange
        editor.drawsBackground = !transparentBackground
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(_ parent: ChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.onCompositionChange?(editor.hasMarkedText())
        }
    }
}

final class ChatTextView: NSTextView {
    var onSend: (() -> Void)?
    var onCompositionChange: ((Bool) -> Void)?
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }
    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(hasMarkedText())
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && !hasMarkedText() {
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSend?()
            }
            return
        }
        super.keyDown(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}
