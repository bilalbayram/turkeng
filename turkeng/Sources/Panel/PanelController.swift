import AppKit
import SwiftUI

final class PanelController {
    private var panel: FloatingPanel?
    private let service: TranslationService
    private var clickMonitor: Any?
    private var sizeObservation: NSKeyValueObservation?

    init(settings: AppSettings) {
        self.service = TranslationService(
            settingsProvider: { settings.translationSettings },
            clipboardWriter: PasteboardTranslationClipboardWriter()
        )
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        service.reset()

        let panel = ensurePanel()
        guard let screen = NSScreen.main else { return }

        // Size the panel using SwiftUI intrinsic content size
        let contentSize = panel.contentView?.fittingSize ?? NSSize(width: 680, height: 60)
        let panelWidth: CGFloat = 680
        let panelHeight = max(contentSize.height, 60)

        // Center horizontally, position in upper third of screen
        let screenFrame = screen.visibleFrame
        let panelOriginX = screenFrame.midX - panelWidth / 2
        let panelOriginY = screenFrame.midY + screenFrame.height / 6
        panel.setFrame(
            NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: panelHeight),
            display: true
        )

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel

        // Global monitor fires on mouse clicks outside our app's windows
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let panelView = TranslationPanelView(service: service)
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])

        let rect = NSRect(x: 0, y: 0, width: 680, height: 60)
        let newPanel = FloatingPanel(contentRect: rect, content: visualEffect)
        newPanel.onAcceptGhostText = { [weak self] in
            self?.service.acceptGhostText() ?? false
        }

        // KVO-observe intrinsic size changes to dynamically resize the panel
        sizeObservation = hostingView.observe(\.intrinsicContentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.adjustPanelSize()
            }
        }

        self.panel = newPanel
        return newPanel
    }

    private func adjustPanelSize() {
        guard let panel, panel.isVisible else { return }
        guard let contentView = panel.contentView else { return }

        let fittingSize = contentView.fittingSize
        let panelWidth: CGFloat = 680
        let maxHeight: CGFloat = (NSScreen.main?.visibleFrame.height ?? 800) * 0.85
        let newHeight = min(max(fittingSize.height, 60), maxHeight)

        let oldFrame = panel.frame
        // Pin top edge: in AppKit y=0 is bottom, so adjust origin.y
        let topEdge = oldFrame.origin.y + oldFrame.size.height
        let newY = topEdge - newHeight

        let newFrame = NSRect(x: oldFrame.origin.x, y: newY, width: panelWidth, height: newHeight)
        panel.animator().setFrame(newFrame, display: true)
    }
}
