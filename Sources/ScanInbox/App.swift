import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowCoordinator.shared.refresh()
        if NSRunningApplication.runningApplications(withBundleIdentifier:"tw.local.SharpScanner").count > 1 { NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { ScannerModel.shared.requestQuit() }
}
@main @MainActor struct ScanInboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ScannerModel.shared
    var body: some Scene {
        Window("掃描接收",id:"main") { ReceiverView(model:model).buttonBorderShape(.capsule).background(WindowPresenceTracker()) }.defaultSize(width:1100,height:720)
        Window("共用設定",id:"settings") { SharedSettings(model:model).background(WindowPresenceTracker()) }.windowResizability(.contentSize)
        MenuBarExtra {
            ScannerMenu(model:model)
        } label: { Image(systemName:model.running ? "scanner.fill" : "scanner").accessibilityLabel("ScanInbox 掃描接收") }
    }
}
struct ScannerMenu: View {
    @ObservedObject var model: ScannerModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.phase)
        Text("\(model.enabledCount) 台啟用 · \(model.transfers.count) 筆傳輸中")
        Divider()
        Button("開啟管理視窗") { WindowCoordinator.shared.showInDock(); openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }
        Button("共用設定…") { WindowCoordinator.shared.showInDock(); openWindow(id:"settings"); NSApp.activate(ignoringOtherApps:true) }
        Divider()
        Button(model.serviceAlive ? "停止接收服務" : "開始接收服務") { if model.serviceAlive { model.stop() } else { model.start() } }.disabled(model.busy)
        if let p = model.selectedPrinter { Button("開啟 \(p.alias) 輸出資料夾") { model.openFolder(p.directory) } }
        Divider()
        Button("結束 ScanInbox") { NSApp.terminate(nil) }
    }
}
