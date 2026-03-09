import AppKit
import SwiftUI

final class PanelController {
    private var panel: FloatingPanel?
    private let service = TranslationService()
    private var clickMonitor: Any?

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
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY + screenFrame.height / 6
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

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
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        let rect = NSRect(x: 0, y: 0, width: 680, height: 60)
        let newPanel = FloatingPanel(contentRect: rect, content: visualEffect)
        self.panel = newPanel
        return newPanel
    }
}
