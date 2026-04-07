import AppKit
import HotKey

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let panelController: PanelController
    let updateChecker: UpdateChecker
    private var hotKey: HotKey?
    private var runningPeer: NSRunningApplication?
    private var duplicateLaunchRelayWorkItem: DispatchWorkItem?
    private var handledExternalLaunchRequest = false

    private static let showPanelNotificationName = "com.bilalbayram.turkeng.showPanel"
    private static let showPanelWithTextNotificationName = "com.bilalbayram.turkeng.showPanelWithText"
    private static let textNotificationKey = "text"

    override init() {
        let settings = AppSettings.shared
        self.settings = settings
        self.panelController = PanelController(settings: settings)
        self.updateChecker = UpdateChecker()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        runningPeer = findRunningPeer()

        NSApp.setActivationPolicy(.accessory)

        registerHotKey()
        registerServicesProvider()
        observeSettings()
        listenForPanelNotifications()
        scheduleDuplicateLaunchRelayIfNeeded()

        Task { await updateChecker.checkOnLaunchIfNeeded() }
    }

    /// Called when the user re-opens the app (e.g. from Dock or Finder)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !panelController.isVisible else { return false }
        panelController.show()
        return false
    }

    // MARK: - Single Instance

    private func findRunningPeer() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let others = running.filter { $0 != NSRunningApplication.current }
        return others.first
    }

    private func listenForPanelNotifications() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleShowPanelNotification),
            name: .init(Self.showPanelNotificationName),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleShowPanelWithTextNotification),
            name: .init(Self.showPanelWithTextNotificationName),
            object: nil
        )
    }

    @objc private func handleShowPanelNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.panelController.show()
        }
    }

    @objc private func handleShowPanelWithTextNotification(_ notification: Notification) {
        let text = notification.userInfo?[Self.textNotificationKey] as? String
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let text, !text.isEmpty {
                self.panelController.show(with: text)
            } else {
                self.panelController.show()
            }
        }
    }

    func togglePanel() {
        panelController.toggle()
    }

    func checkForUpdates() async {
        await updateChecker.checkForUpdates()
    }

    @objc func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handledExternalLaunchRequest = true
        duplicateLaunchRelayWorkItem?.cancel()

        let selectedText =
            pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let selectedText, !selectedText.isEmpty else {
            error.pointee = "No text selection was provided." as NSString
            return
        }

        if let runningPeer {
            postPanelNotification(with: selectedText)
            runningPeer.activate()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }

        panelController.show(with: selectedText)
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        hotKey = nil // unregister previous

        hotKey = HotKey(
            key: settings.hotkeyLetter.hotKey,
            modifiers: settings.hotkeyModifier.eventFlags
        )
        hotKey?.keyDownHandler = { [weak self] in
            self?.panelController.toggle()
        }
    }

    private func registerServicesProvider() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    private func scheduleDuplicateLaunchRelayIfNeeded() {
        guard let runningPeer else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.handledExternalLaunchRequest else { return }
            self.postPanelNotification()
            runningPeer.activate()
            NSApp.terminate(nil)
        }
        duplicateLaunchRelayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func postPanelNotification(with text: String? = nil) {
        let center = DistributedNotificationCenter.default()
        if let text, !text.isEmpty {
            center.postNotificationName(
                .init(Self.showPanelWithTextNotificationName),
                object: nil,
                userInfo: [Self.textNotificationKey: text],
                deliverImmediately: true
            )
        } else {
            center.postNotificationName(
                .init(Self.showPanelNotificationName),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.hotkeyModifier
            _ = settings.hotkeyLetter
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.registerHotKey()
                self?.observeSettings()
            }
        }
    }
}

private extension HotkeyLetter {
    var hotKey: Key {
        switch self {
        case .a: .a
        case .b: .b
        case .c: .c
        case .d: .d
        case .e: .e
        case .f: .f
        case .g: .g
        case .h: .h
        case .i: .i
        case .j: .j
        case .k: .k
        case .l: .l
        case .m: .m
        case .n: .n
        case .o: .o
        case .p: .p
        case .q: .q
        case .r: .r
        case .s: .s
        case .t: .t
        case .u: .u
        case .v: .v
        case .w: .w
        case .x: .x
        case .y: .y
        case .z: .z
        }
    }
}

private extension HotkeyModifier {
    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .option:
            .option
        case .command:
            .command
        case .control:
            .control
        case .shift:
            .shift
        }
    }
}
