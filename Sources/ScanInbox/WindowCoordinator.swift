import AppKit
import SwiftUI

// Track only actual user windows, not the status-item or transient system panels.
@MainActor final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var closing = Set<ObjectIdentifier>()
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                Task { @MainActor in
                    guard let self, self.windows.contains(window) else { return }
                    self.closing.remove(ObjectIdentifier(window))
                    self.refresh()
                }
            })
        }
        observers.append(center.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                guard let self, self.windows.contains(window) else { return }
                self.closing.insert(ObjectIdentifier(window))
                self.refresh()
            }
        })
    }
    func register(_ window: NSWindow) {
        windows.add(window)
        closing.remove(ObjectIdentifier(window))
        // A new window may not have been ordered onscreen yet.
        showInDock()
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func showInDock() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
    func refresh() {
        let presence = windows.allObjects.map {
            WindowPresence(visible:$0.isVisible,minimized:$0.isMiniaturized,closing:closing.contains(ObjectIdentifier($0)))
        }
        let policy: NSApplication.ActivationPolicy = WindowVisibilityRules.shouldShowDock(presence) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
}

struct WindowPresenceTracker: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowCoordinator.shared.register(window) }
        }
    }
    func makeNSView(context:Context) -> Probe { Probe() }
    func updateNSView(_ nsView:Probe,context:Context) {}
}
