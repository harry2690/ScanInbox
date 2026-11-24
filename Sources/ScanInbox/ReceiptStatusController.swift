import AppKit
import SwiftUI
import Combine

// A transient receipt panel is deliberately excluded from WindowPresenceTracker.
@MainActor final class ReceiptStatusController: NSObject, NSMenuDelegate {
    static let shared = ReceiptStatusController()
    var openWindow: ((String) -> Void)?
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var dismissTask: Task<Void, Never>?
    private var batch = ReceiptBatch()
    private var pending: [(String, String)] = []
    private var showingPrinter: String?
    private var count = 0
    private var alias = ""

    func install() {
        guard item == nil else { return }
        let status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item = status
        status.button?.target = self
        status.button?.action = #selector(showMenu)
        status.button?.setAccessibilityLabel("ScanInbox 掃描接收")
        popover.behavior = .transient
        popover.animates = true
        subscription = ScannerModel.shared.$running.sink { [weak self] running in
            self?.item?.button?.image = NSImage(systemSymbolName:running ? "scanner.fill" : "scanner", accessibilityDescription:"ScanInbox")
        }
    }

    @objc private func showMenu() {
        popover.close()
        let model = ScannerModel.shared
        let menu = NSMenu()
        menu.delegate = self
        func add(_ title:String, _ action:Selector? = nil, enabled:Bool = true) {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target = self; entry.isEnabled = enabled; menu.addItem(entry)
        }
        menu.autoenablesItems = false
        add(model.phase, enabled:false)
        add("\(model.enabledCount) 台啟用 · \(model.transfers.count) 筆傳輸中", enabled:false)
        menu.addItem(.separator())
        add("開啟管理視窗", #selector(openMain))
        add("共用設定…", #selector(openSettings))
        menu.addItem(.separator())
        add(model.serviceAlive ? "停止接收服務" : "開始接收服務", #selector(toggleService), enabled:!model.busy)
        if let p = model.selectedPrinter { add("開啟 \(p.alias) 輸出資料夾", #selector(openFolder)) }
        menu.addItem(.separator())
        add("結束 ScanInbox", #selector(quit))
        item?.menu = menu
        item?.button?.performClick(nil)
    }
    func menuDidClose(_ menu:NSMenu) { item?.menu = nil }
    private func showWindow(_ id:String) {
        WindowCoordinator.shared.showInDock()
        openWindow?(id)
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func openMain() { showWindow("main") }
    @objc private func openSettings() { showWindow("settings") }
    @objc private func toggleService() {
        let model = ScannerModel.shared
        if model.serviceAlive { model.stop() } else { model.start() }
    }
    @objc private func openFolder() {
        if let p = ScannerModel.shared.selectedPrinter { ScannerModel.shared.openFolder(p.directory) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func received(id:String, printerID:String, alias:String) {
        guard batch.accept(id) else { return }
        if showingPrinter == nil { showingPrinter = printerID; self.alias = alias; count = 1 }
        else if showingPrinter == printerID { count += 1; self.alias = alias }
        else { pending.append((printerID,alias)); return }
        present()
    }
    private func present() {
        guard let button = item?.button else { return }
        popover.contentViewController = NSHostingController(rootView:
            HStack(spacing:12) {
                Image(systemName:"checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment:.leading,spacing:4) {
                    Text("已收到掃描檔案").font(.headline)
                    Text("\(alias) · \(count) 個檔案").font(.subheadline).lineLimit(3)
                }
                Spacer(minLength:0)
            }.padding(18).frame(width:290)
        )
        if !popover.isShown { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY) }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(5)) } catch { return }
            self?.finish()
        }
    }
    private func finish() {
        popover.close(); showingPrinter = nil; count = 0
        guard let first = pending.first else { return }
        pending.removeFirst()
        showingPrinter = first.0; alias = first.1; count = 1
        let matching = pending.filter { $0.0 == first.0 }
        count += matching.count
        pending.removeAll { $0.0 == first.0 }
        present()
    }
}
