import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowCoordinator.shared.refresh()
        ReceiptStatusController.shared.install()
        if NSRunningApplication.runningApplications(withBundleIdentifier:"tw.local.SharpScanner").count > 1 { NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { ScannerModel.shared.requestQuit() }
}
@main @MainActor struct ScanInboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ScannerModel.shared
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("掃描接收",id:"main") { ReceiverView(model:model).buttonBorderShape(.capsule).background(WindowPresenceTracker()).onAppear { ReceiptStatusController.shared.openWindow = { id in openWindow(id:id) } } }.defaultSize(width:1100,height:720)
        .commands {
            CommandGroup(replacing:.appTermination) {
                Button("隱藏管理視窗") { WindowCoordinator.shared.hideManagementWindows() }
                    .keyboardShortcut("q",modifiers:.command)
            }
        }
        Window("共用設定",id:"settings") { SharedSettings(model:model).background(WindowPresenceTracker()).onAppear { ReceiptStatusController.shared.openWindow = { id in openWindow(id:id) } } }.windowResizability(.contentSize)

    }
}
