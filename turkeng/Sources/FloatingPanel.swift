import AppKit

final class FloatingPanel: NSPanel {

    /// Returns `true` when ghost text was accepted, `false` if nothing to accept.
    var onAcceptGhostText: (() -> Bool)?

    init(contentRect: NSRect, content: NSView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: contentRect)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.addSubview(content)

        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        contentView = container
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // TAB — always accept ghost text if available
            if event.keyCode == 48 {
                if onAcceptGhostText?() == true { return }
            }
            // Right arrow — accept ghost text only when cursor is at end of text
            if event.keyCode == 124 {
                if let editor = firstResponder as? NSTextView,
                   editor.selectedRange.location == editor.string.count,
                   onAcceptGhostText?() == true {
                    return
                }
            }
        }
        super.sendEvent(event)
    }

    // resignKey intentionally NOT overridden — the Translation framework's
    // ViewBridge remote service can momentarily steal key status, which would
    // dismiss the panel mid-translation. Click-outside is handled by a global
    // event monitor in PanelController instead.
}
