import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement
import SystemConfiguration

struct Printer: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var alias: String
    var ip: String
    var directory: String
    var enabled = true
}
struct Configuration: Codable, Equatable {
    var printers: [Printer] = []
    var port = 4687
    var autoReceive = true
    var retentionDays = 30
    var diagnostic = false
}
struct ScanRecord: Codable, Identifiable {
    var id: String
    var printerID: String
    var alias: String
    var ip: String
    var path: String
    var size: Int64
    var status: String
    var time: Double
    var error: String
    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
    var date: Date { Date(timeIntervalSince1970: time) }
    var succeeded: Bool { status == "success" }
}
struct Address: Identifiable, Equatable {
    var interface: String
    var name: String
    var ip: String
    var id: String { interface + ":" + ip }
}
struct ReceiverEvent: Decodable {
    var type: String
    var printerID: String?
    var transferID: String?
    var message: String?
    var record: ScanRecord?
}

@MainActor final class ScannerModel: ObservableObject {
    static let shared = ScannerModel()
    @Published var configuration = Configuration()
    @Published var selected: SidebarSelection? = .allHistory
    @Published var records: [ScanRecord] = []
    @Published var addresses: [Address] = []
    @Published var phase = "已停止"
    @Published var running = false
    @Published var busy = false
    @Published var transfers: [String: String] = [:]
    @Published var lastErrors: Set<String> = []
    @Published var errorMessage: String? = nil
    @Published var diagnosticText = ""
    @Published var loginStatus = ""
    private var child: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var pendingData = Data()
    private var restart = false
    private var intentionalStop = false
    private var terminating = false
    private var timer: Timer?
    @Published private(set) var deletingRecordIDs = Set<String>()
    private var deletedRecordIDs = Set<String>()
    private var historyRequest = 0
    private var lastHistoryRefresh = Date.distantPast
    private let fm = FileManager.default
    let dataDirectory: URL
    var configURL: URL { dataDirectory.appendingPathComponent("settings.json") }
    var logURL: URL { dataDirectory.appendingPathComponent("Logs/receiver.log") }
    var canChangeConfiguration: Bool { transfers.isEmpty && !busy }
    var serviceAlive: Bool { child != nil }
    var selectedPrinter: Printer? { configuration.printers.first { $0.id == selected?.printerID } }
    var enabledCount: Int { configuration.printers.filter(\.enabled).count }
    var loginAgentURL: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/tw.local.SharpScanner.login.plist") }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled || fm.fileExists(atPath:loginAgentURL.path) }

    private init() {
        dataDirectory = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SharpScanner")
        let existing = fm.fileExists(atPath: configURL.path)
        var validSaved = false
        if existing {
            do { configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL)); try validate(configuration); validSaved = true }
            catch { errorMessage = "設定讀取失敗，未自動啟動：\(error.localizedDescription)" }
        }
        selected = configuration.printers.first.map { .printer($0.id) } ?? .allHistory
        refreshAddresses()
        migrateExistingLoginPath()
        refreshLoginStatus()
        loadHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAddresses()
                self?.refreshLoginStatus()
                if let self, Date().timeIntervalSince(self.lastHistoryRefresh) > 3600 { self.loadHistory() }
            }
        }
        if validSaved && configuration.autoReceive { start() }
    }
    func fail(_ message: String) { errorMessage = message }
    func validate(_ config: Configuration) throws {
        func reject(_ message: String) throws { throw NSError(domain:"ScanInbox",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        guard (1024...65535).contains(config.port), !(50000...50009).contains(config.port) else { try reject("連接埠須為 1024–65535，並避開資料埠 50000–50009。"); return }
        guard [0,30,90,365].contains(config.retentionDays) else { try reject("紀錄保留期間不正確。"); return }
        var ips = Set<String>(), ids = Set<String>()
        for p in config.printers {
            var address = in_addr()
            guard p.ip.withCString({ inet_pton(AF_INET,$0,&address) }) == 1, p.ip != "0.0.0.0", !p.ip.hasPrefix("127."), p.ip != "255.255.255.255" else { try reject("印表機 IP 不正確：\(p.ip)"); return }
            guard ips.insert(p.ip).inserted, ids.insert(p.id).inserted else { try reject("每台印表機必須使用不同 IP。"); return }
            guard !p.alias.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, p.alias.count <= 80 else { try reject("印表機別名須為 1 至 80 字。"); return }
            let root = URL(fileURLWithPath:p.directory).standardizedFileURL.resolvingSymlinksInPath()
            let home = fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
            let state = dataDirectory.resolvingSymlinksInPath().path
            guard p.directory.hasPrefix("/"), root.path != "/", root.path != home, root.path != state, !state.hasPrefix(root.path + "/"), !root.path.hasPrefix(state + "/") else { try reject("請為 \(p.alias) 選擇獨立輸出資料夾，不可使用家目錄根層或程式資料目錄。"); return }
        }
    }
    @discardableResult func commit(_ next: Configuration) -> Bool {
        guard canChangeConfiguration else { fail("目前正在傳輸或啟停服務，請稍後再套用設定。"); return false }
        do {
            try validate(next)
            for p in next.printers where p.enabled {
                try fm.createDirectory(atPath:p.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                guard fm.isWritableFile(atPath:p.directory) else { throw NSError(domain:"ScanInbox",code:2,userInfo:[NSLocalizedDescriptionKey:"輸出資料夾無法寫入：\(p.directory)"]) }
            }
            try fm.createDirectory(at:dataDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(next).write(to:configURL,options:.atomic)
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:configURL.path)
            let wasAlive = serviceAlive
            configuration = next
            if let id = selected?.printerID, !next.printers.contains(where:{$0.id == id}) { selected = next.printers.first.map { .printer($0.id) } ?? .allHistory }
            lastErrors = lastErrors.intersection(Set(next.printers.map(\.id)))
            if wasAlive { restart = enabledCount > 0; stopChild() }
            loadHistory()
            return true
        } catch { fail(error.localizedDescription); return false }
    }
    @discardableResult func savePrinter(_ printer: Printer) -> Bool {
        var next = configuration
        var clean = printer
        clean.alias = clean.alias.trimmingCharacters(in:.whitespacesAndNewlines)
        clean.ip = clean.ip.trimmingCharacters(in:.whitespacesAndNewlines)
        clean.directory = URL(fileURLWithPath:(clean.directory as NSString).expandingTildeInPath).standardizedFileURL.path
        if let i = next.printers.firstIndex(where:{$0.id == clean.id}) { next.printers[i] = clean } else { next.printers.append(clean) }
        guard commit(next) else { return false }
        selected = .printer(clean.id)
        return true
    }
    func removePrinter(_ id: String) -> Bool {
        var next = configuration; next.printers.removeAll { $0.id == id }; return commit(next)
    }
    func togglePrinter(_ id: String) {
        var next = configuration
        guard let i = next.printers.firstIndex(where:{$0.id == id}) else { return }
        next.printers[i].enabled.toggle()
        _ = commit(next)
    }
    func state(for printer: Printer) -> String {
        if !printer.enabled { return "已暫停" }
        if transfers.values.contains(printer.id) { return "接收中" }
        if !running { return busy ? "服務切換中" : "服務已停止" }
        if lastErrors.contains(printer.id) { return "上次接收失敗" }
        return "待命"
    }
    func pythonURL() -> URL? {
        ["/opt/homebrew/bin/python3.13","/opt/homebrew/bin/python3.14"].first(where:fm.isExecutableFile(atPath:)).map { URL(fileURLWithPath:$0) }
    }
    var bootstrap: URL? { Bundle.main.resourceURL?.appendingPathComponent("Receiver/bootstrap.py") }
    func start() {
        guard child == nil, !terminating else { return }
        guard enabledCount > 0 else { fail("請先新增並啟用至少一台印表機。"); return }
        guard let python = pythonURL(), let script = bootstrap else { fail("找不到 Homebrew Python 3.13 或 3.14。請依 README 安裝接收環境。"); return }
        // 第一次啟動也將設定驗證並存入私人目錄。
        guard commit(configuration) else { return }
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = python
        process.arguments = ["-I","-B","-u",script.path,"--config",configURL.path,"--data-dir",dataDirectory.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = out; process.standardError = err
        pendingData = Data(); intentionalStop = false; phase = "正在啟動…"; busy = true
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(data) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.appendDiagnostic(String(decoding:data,as:UTF8.self)) }
        }
        process.terminationHandler = { [weak self] process in Task { @MainActor in self?.ended(process) } }
        child = process; outputPipe = out; errorPipe = err
        do { try process.run() }
        catch {
            out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
            child = nil; outputPipe = nil; errorPipe = nil; busy = false; phase = "啟動失敗"; fail(error.localizedDescription)
        }
    }
    private func consume(_ data: Data) {
        pendingData.append(data)
        while let i = pendingData.firstIndex(of:10) {
            let line = pendingData[..<i]; pendingData.removeSubrange(...i)
            guard let event = try? JSONDecoder().decode(ReceiverEvent.self,from:Data(line)) else { continue }
            switch event.type {
            case "ready": if !intentionalStop { running = true; busy = false; phase = "接收服務運作中" }
            case "receiving": if let transfer = event.transferID, let id = event.printerID { transfers[transfer] = id }
            case "transferEnded": if let transfer = event.transferID { transfers.removeValue(forKey:transfer) }
            case "record":
                if let record = event.record, !deletedRecordIDs.contains(record.id) {
                    records.removeAll { $0.id == record.id }; records.insert(record,at:0)
                    if records.count > 5000 { records.removeLast(records.count - 5000) }
                    if record.succeeded { lastErrors.remove(record.printerID); ReceiptStatusController.shared.received(id:record.id, printerID:record.printerID, alias:record.alias) } else { lastErrors.insert(record.printerID) }
                }
            case "error": phase = "接收服務發生錯誤"; fail(event.message ?? "未知接收錯誤")
            default: break
            }
        }
    }
    private func appendDiagnostic(_ text: String) {
        diagnosticText += text
        if diagnosticText.count > 24000 { diagnosticText = String(diagnosticText.suffix(16000)) }
    }
    func stop() { restart = false; stopChild() }
    private func stopChild() {
        guard let p = child else { return }
        intentionalStop = true; running = false; busy = true; phase = "正在停止…"
        if p.isRunning { p.terminate() }
        DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self, weak p] in
            guard let self, let p, self.child === p, p.isRunning else { return }
            kill(p.processIdentifier,SIGKILL)
        }
    }
    private func ended(_ process: Process) {
        guard child === process else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil; errorPipe?.fileHandleForReading.readabilityHandler = nil
        child = nil; outputPipe = nil; errorPipe = nil; transfers = [:]; running = false; busy = false
        phase = intentionalStop || process.terminationStatus == 0 ? "已停止" : "接收服務已結束，請查看記錄"
        loadHistory()
        if terminating { NSApp.reply(toApplicationShouldTerminate:true); return }
        if restart { restart = false; start() }
    }
    func requestQuit() -> NSApplication.TerminateReply {
        if !transfers.isEmpty {
            let alert = NSAlert(); alert.messageText = "目前有掃描文件正在傳輸"; alert.informativeText = "結束程式會中斷接收，未完成檔案將移除。"; alert.addButton(withTitle:"繼續接收"); alert.addButton(withTitle:"停止並結束")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        guard child != nil else { return .terminateNow }
        terminating = true; restart = false; stopChild(); return .terminateLater
    }
    func loadHistory() {
        guard let python = pythonURL(), let script = bootstrap else { return }
        historyRequest += 1
        let request = historyRequest, directory = dataDirectory.path, days = configuration.retentionDays
        lastHistoryRefresh = Date()
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let task = Process(), pipe = Pipe()
            task.executableURL = python; task.arguments = ["-I","-B",script.path,"--data-dir",directory,"--history","--retention-days",String(days)]
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice; task.standardInput = FileHandle.nullDevice
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                guard task.terminationStatus == 0 else { return }
                let loaded = try JSONDecoder().decode([ScanRecord].self,from:data)
                Task { @MainActor in
                    guard let self, self.historyRequest == request else { return }
                    // 與讀取期間新進的結果合併，避免非同步查詢覆蓋剛收到的事件。
                    var merged = Dictionary(uniqueKeysWithValues:loaded.filter { !self.deletedRecordIDs.contains($0.id) }.map { ($0.id,$0) })
                    let cutoff = days > 0 ? Date().timeIntervalSince1970 - Double(days)*86400 : 0
                    for r in self.records where r.time >= cutoff { merged[r.id] = r }
                    self.records = Array(merged.values.sorted { $0.time > $1.time }.prefix(5000))
                }
            } catch { Task { @MainActor in self?.appendDiagnostic("紀錄讀取失敗：\(error.localizedDescription)\n") } }
        }
    }
    func refreshAddresses() {
        var names: [String:String] = [:]
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?, let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? { names[bsd] = name }
            }
        }
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }
        var result: [Address] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let value = item.pointee
            guard let addr = value.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET,
                  value.ifa_flags & UInt32(IFF_UP) != 0, value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST) == 0 {
                let name = String(cString:value.ifa_name), ip = String(cString:buffer)
                if !ip.hasPrefix("169.254.") { result.append(Address(interface:name,name:names[name] ?? name,ip:ip)) }
            }
        }
        let next = result.sorted { $0.interface == $1.interface ? $0.ip < $1.ip : $0.interface < $1.interface }
        if addresses != next { addresses = next }
    }
    private func migrateExistingLoginPath() {
        // 僅更新使用者已啟用的本 App 登入排程；不建立新的登入設定。
        guard fm.fileExists(atPath:loginAgentURL.path) else { return }
        do {
            let data = try Data(contentsOf:loginAgentURL)
            guard var plist = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
                  plist["Label"] as? String == "tw.local.SharpScanner.login",
                  var args = plist["ProgramArguments"] as? [String], args.count == 3,
                  args[0] == "/usr/bin/open", args[1] == "-g",
                  ["SharpScanner.app","ScanInbox.app"].contains(URL(fileURLWithPath:args[2]).lastPathComponent),
                  args[2] != Bundle.main.bundleURL.path else { return }
            args[2] = Bundle.main.bundleURL.path; plist["ProgramArguments"] = args
            try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:loginAgentURL,options:.atomic)
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:loginAgentURL.path)
        } catch { errorMessage = "原有登入啟動路徑無法更新，請在共用設定重新儲存：\(error.localizedDescription)" }
    }
    func refreshLoginStatus() {
        if fm.fileExists(atPath:loginAgentURL.path) { loginStatus = "已啟用"; return }
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "已啟用"
        case .requiresApproval: loginStatus = "等待系統核准"
        default: loginStatus = "未啟用"
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            let status = SMAppService.mainApp.status
            if enabled {
                if status == .notFound {
                    // 本機臨時簽章不一定可註冊 SMAppService；僅於使用者勾選後
                    // 建立此 App 專用的登入排程。不是規避 requiresApproval 狀態。
                    let plist: [String:Any] = ["Label":"tw.local.SharpScanner.login", "ProgramArguments":["/usr/bin/open","-g",Bundle.main.bundleURL.path], "RunAtLoad":true, "KeepAlive":false]
                    let data = try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0)
                    try fm.createDirectory(at:loginAgentURL.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try data.write(to:loginAgentURL,options:.atomic)
                    try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:loginAgentURL.path)
                } else if status != .enabled {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .enabled && fm.fileExists(atPath:loginAgentURL.path) { try fm.removeItem(at:loginAgentURL) }
                if SMAppService.mainApp.status == .requiresApproval { fail("登入啟動仍待系統核准，請到系統設定的「登入項目」允許 ScanInbox。"); SMAppService.openSystemSettingsLoginItems() }
            } else {
                if fm.fileExists(atPath:loginAgentURL.path) { try fm.removeItem(at:loginAgentURL) }
                if status == .enabled || status == .requiresApproval { try SMAppService.mainApp.unregister() }
            }
            refreshLoginStatus()
        } catch { refreshLoginStatus(); fail("接收設定已儲存，但登入啟動未完成：\(error.localizedDescription)") }
    }
    func openFolder(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath:path)) }
    func openFile(_ record: ScanRecord) {
        guard record.succeeded else { fail("這筆紀錄未成功接收檔案。"); return }
        guard fm.fileExists(atPath:record.path) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "檔案已移動或刪除，是否刪除這筆紀錄？"
            alert.informativeText = "找不到「\(record.filename)」。刪除紀錄只會移除掃描歷史，不會刪除任何實際檔案。"
            alert.addButton(withTitle:"保留")
            let deleteButton = alert.addButton(withTitle:"刪除")
            deleteButton.hasDestructiveAction = true
            if alert.runModal() == .alertSecondButtonReturn { deleteRecords([record.id]) }
            return
        }
        if !NSWorkspace.shared.open(URL(fileURLWithPath:record.path)) { fail("無法開啟檔案，請確認已安裝可開啟此類檔案的應用程式。") }
    }
    func openContainingFolder(_ record: ScanRecord) {
        let file = URL(fileURLWithPath:record.path)
        if fm.fileExists(atPath:record.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            let folder = file.deletingLastPathComponent()
            guard fm.fileExists(atPath:folder.path) else { fail("檔案所在資料夾已搬移或刪除。"); return }
            if !NSWorkspace.shared.open(folder) { fail("無法開啟檔案所在資料夾。") }
        }
    }
    func deleteRecords(_ ids:Set<String>) {
        let targets = ids.subtracting(deletingRecordIDs).intersection(Set(records.map(\.id)))
        guard !targets.isEmpty else { return }
        guard let python = pythonURL(), let script = bootstrap else { fail("找不到接收核心，無法刪除紀錄。"); return }
        deletingRecordIDs.formUnion(targets)
        let directory = dataDirectory.path
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let task = Process()
            task.executableURL = python
            task.arguments = ["-I","-B",script.path,"--data-dir",directory,"--delete-record"] + targets.sorted()
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice; task.standardInput = FileHandle.nullDevice
            do {
                try task.run(); task.waitUntilExit()
                let succeeded = task.terminationStatus == 0
                Task { @MainActor in
                    guard let self else { return }
                    self.deletingRecordIDs.subtract(targets)
                    guard succeeded else { self.fail("刪除紀錄失敗，請稍後再試；原始檔案未變更。"); return }
                    self.deletedRecordIDs.formUnion(targets)
                    self.records.removeAll { targets.contains($0.id) }
                    self.loadHistory()
                }
            } catch {
                Task { @MainActor in
                    self?.deletingRecordIDs.subtract(targets)
                    self?.fail("刪除紀錄失敗：\(error.localizedDescription)")
                }
            }
        }
    }
}
