import AppKit
import SwiftUI

extension View {
    func neutralGlass() -> some View { buttonStyle(.glass).tint(.white).foregroundStyle(.primary) }
}
struct ReceiverView: View {
    @ObservedObject var model: ScannerModel
    @State private var search = ""
    @State private var editing: Printer?
    @State private var selectedRecords = Set<String>()
    @State private var showLog = false
    @Environment(\.openWindow) private var openWindow
    private var displayed: [ScanRecord] {
        model.records.filter { HistoryFilter.includes(printerID:$0.printerID,filename:$0.filename,alias:$0.alias,selection:model.selected,query:search) }
    }
    private var selection: ScanRecord? { displayed.first { selectedRecords.contains($0.id) } }
    private func statusColor(_ p: Printer) -> Color {
        if !p.enabled || !model.running { return .secondary }
        if model.lastErrors.contains(p.id) { return .orange }
        return model.transfers.values.contains(p.id) ? .blue : .green
    }
    var body: some View {
        NavigationSplitView {
            List(selection:$model.selected) {
                Section("印表機") {
                    ForEach(model.configuration.printers) { p in
                        Label {
                            VStack(alignment:.leading,spacing:5) {
                                Text(p.alias).lineLimit(1)
                                Text(p.ip).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing:5) { Circle().fill(statusColor(p)).frame(width:6,height:6); Text(model.state(for:p)).font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: { Image(systemName:"scanner") }
                        .padding(.vertical,5).tag(SidebarSelection.printer(p.id))
                        .contextMenu {
                            Button("編輯設定") { editing = p }
                            Button(p.enabled ? "暫停這台印表機" : "啟用這台印表機") { model.togglePrinter(p.id) }.disabled(!model.canChangeConfiguration)
                            Button("開啟輸出資料夾") { model.openFolder(p.directory) }
                        }
                    }
                }
                Section { Label("全部掃描紀錄",systemImage:"clock").tag(SidebarSelection.allHistory) }
            }
            .navigationSplitViewColumnWidth(min:220,ideal:250,max:340)
            .safeAreaInset(edge:.bottom) {
                Button { WindowCoordinator.shared.showInDock(); openWindow(id:"settings"); NSApp.activate(ignoringOtherApps:true) } label: { Label("共用設定",systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain).padding(18)
            }
        } detail: {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text(model.selectedPrinter?.alias ?? "全部掃描紀錄").font(.title2.bold())
                        Text(model.selectedPrinter?.ip ?? "查看所有印表機的接收結果").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let p = model.selectedPrinter { Label(model.state(for:p),systemImage:model.transfers.values.contains(p.id) ? "arrow.down.circle" : "circle.fill").foregroundStyle(statusColor(p)) }
                }
                if let p = model.selectedPrinter {
                    HStack { Image(systemName:"folder").foregroundStyle(.blue); Text(p.directory.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2); Spacer() }
                }
                Divider()
                HStack { Text("掃描紀錄").font(.headline); Spacer(); Text("\(displayed.count) 筆").font(.caption).foregroundStyle(.secondary) }
                Table(displayed,selection:$selectedRecords) {
                    TableColumn("時間") { record in Text(record.date.formatted(.dateTime.month().day().hour().minute())).monospacedDigit() }.width(min:100,ideal:120)
                    TableColumn("檔案名稱") { record in
                        VStack(alignment:.leading,spacing:3) {
                            Text(record.filename).lineLimit(1)
                            if model.selected?.printerID == nil { Text(record.alias).font(.caption).foregroundStyle(.secondary) }
                        }.help(record.error.isEmpty ? record.path : record.error)
                    }
                    TableColumn("大小") { record in Text(record.succeeded ? ByteCountFormatter.string(fromByteCount:record.size,countStyle:.file) : "—") }.width(80)
                    TableColumn("結果") { record in Label(record.succeeded ? "成功" : "未完成",systemImage:record.succeeded ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(record.succeeded ? .green : .orange).help(record.error) }.width(95)
                }.tableStyle(.inset)
                .overlay { if displayed.isEmpty { ContentUnavailableView(search.isEmpty ? "尚無掃描紀錄" : "找不到符合的紀錄",systemImage:"doc.text.magnifyingglass",description:Text(search.isEmpty ? "開始接收後，結果會顯示在這裡。" : "請嘗試其他檔名。")) } }
                .contextMenu {
                    Button("在 Finder 中顯示") { if let record = selection { model.reveal(record) } }.disabled(selection == nil || selection?.succeeded != true)
                    Button("查看結果詳細資料") { if let r = selection { model.fail(r.error.isEmpty ? "\(r.filename)\n\(r.path)\n傳輸完成；文件內容請開啟確認。" : "\(r.filename)\n\(r.error)") } }.disabled(selection == nil)
                }
                HStack {
                    Label(model.phase,systemImage:model.running ? "circle.fill" : "pause.circle").foregroundStyle(model.running ? .green : .secondary)
                    Spacer()
                    Text("\(model.configuration.printers.count) 台印表機 · \(model.enabledCount) 台啟用").foregroundStyle(.secondary)
                }.font(.caption)
            }.padding(24)
            .navigationTitle("掃描接收")
            .toolbar {
                ToolbarItemGroup {
                    Button { editing = model.selectedPrinter } label: { Label("編輯",systemImage:"pencil") }.disabled(model.selectedPrinter == nil || !model.canChangeConfiguration)
                    Button { if let p = model.selectedPrinter { model.togglePrinter(p.id) } } label: { Label(model.selectedPrinter?.enabled == true ? "暫停" : "啟用",systemImage:model.selectedPrinter?.enabled == true ? "pause" : "play") }.disabled(model.selectedPrinter == nil || !model.canChangeConfiguration)
                    Button { if let p = model.selectedPrinter { model.openFolder(p.directory) } } label: { Label("開啟資料夾",systemImage:"folder") }.disabled(model.selectedPrinter == nil)
                }
                ToolbarItem { Button { editing = Printer(alias:"",ip:"",directory:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/SharpScan").path) } label: { Label("新增印表機",systemImage:"plus") }.disabled(!model.canChangeConfiguration) }
                ToolbarItem { Button { if model.serviceAlive { model.stop() } else { model.start() } } label: { Label(model.serviceAlive ? "停止接收服務" : "開始接收服務",systemImage:model.serviceAlive ? "stop.circle" : "play.circle") }.disabled(model.busy) }
                ToolbarItem { Button { showLog = true } label: { Label("診斷記錄",systemImage:"text.alignleft") } }
            }
            .searchable(text:$search,prompt:"搜尋檔名或別名")
        }
        .frame(minWidth:1000,minHeight:640)
        .sheet(item:$editing) { printer in PrinterEditor(model:model,printer:printer) }
        .sheet(isPresented:$showLog) { DiagnosticView(model:model) }
        .alert("ScanInbox",isPresented:Binding(get:{model.errorMessage != nil && editing == nil && !showLog},set:{if !$0 {model.errorMessage = nil}})) { Button("好") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
        .onChange(of:model.selected) { _,_ in selectedRecords = [] }
    }
}

struct PrinterEditor: View {
    @ObservedObject var model: ScannerModel
    @State private var draft: Printer
    private let original: Printer
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false
    @State private var localError: String?
    init(model:ScannerModel,printer:Printer) { self.model = model; original = printer; _draft = State(initialValue:printer) }
    private var existing: Bool { model.configuration.printers.contains { $0.id == draft.id } }
    private var valid: Bool { !draft.alias.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !draft.ip.isEmpty && !draft.directory.isEmpty }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(existing ? "編輯印表機" : "新增印表機").font(.title2.bold())
            Form {
                TextField("印表機別名",text:$draft.alias)
                TextField("印表機 IP",text:$draft.ip)
                LabeledContent("輸出資料夾") {
                    HStack {
                        Text(draft.directory.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).foregroundStyle(.secondary).lineLimit(2).help(draft.directory)
                        Button("選擇…") { chooseFolder() }.neutralGlass()
                    }
                }
                Toggle("啟用這台印表機",isOn:$draft.enabled).toggleStyle(.switch)
            }.formStyle(.grouped)
            Text("別名僅供本機辨識，不會修改影印機通訊錄。移除設定不會刪除已掃描文件。").font(.caption).foregroundStyle(.secondary)
            if !model.transfers.isEmpty { Label("文件傳輸中，請等接收完成後再儲存。",systemImage:"info.circle").font(.caption).foregroundStyle(.orange) }
            HStack {
                if existing { Button("移除印表機…",role:.destructive) { confirmRemoval = true }.neutralGlass().disabled(!model.canChangeConfiguration) }
                Spacer()
                Button("取消") { dismiss() }.neutralGlass().keyboardShortcut(.cancelAction)
                Button("儲存") { if model.savePrinter(draft) { dismiss() } else { localError = model.errorMessage; model.errorMessage = nil } }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(!valid || !model.canChangeConfiguration || (existing && draft == original))
            }
        }.padding(28).frame(width:620).buttonBorderShape(.capsule)
        .alert("移除這台印表機？",isPresented:$confirmRemoval) {
            Button("取消",role:.cancel) {}
            Button("移除設定",role:.destructive) { if model.removePrinter(draft.id) { dismiss() } else { localError = model.errorMessage; model.errorMessage = nil } }
        } message: { Text("將停止接受 \(draft.alias) 的新掃描。已掃描文件與接收紀錄會保留。") }
        .alert("無法儲存設定",isPresented:Binding(get:{localError != nil},set:{if !$0 { localError = nil }})) { Button("好") { localError = nil } } message: { Text(localError ?? "") }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "選擇輸出資料夾"
        panel.directoryURL = URL(fileURLWithPath:draft.directory)
        if panel.runModal() == .OK, let url = panel.url { draft.directory = url.path }
    }
}

struct SharedSettings: View {
    @ObservedObject var model: ScannerModel
    @State private var draft: Configuration
    @State private var port: String
    @State private var login: Bool
    @State private var localError: String?
    @Environment(\.dismiss) private var dismiss
    init(model:ScannerModel) { self.model = model; _draft = State(initialValue:model.configuration); _port = State(initialValue:String(model.configuration.port)); _login = State(initialValue:model.loginEnabled) }
    private var changed: Bool { draft != model.configuration || port != String(model.configuration.port) || login != model.loginEnabled }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Form {
                Section {
                    HStack { Text("自動偵測所有可用的網路介面"); Spacer(); Button("重新偵測",systemImage:"arrow.clockwise") { model.refreshAddresses() }.neutralGlass() }
                    ForEach(model.addresses) { address in
                        LabeledContent("\(address.name)（\(address.interface)）") { Text(address.ip).monospacedDigit().textSelection(.enabled); Text("可用").foregroundStyle(.green) }
                    }
                    if model.addresses.isEmpty { Text("尚未偵測到可用的 IPv4 網路介面").foregroundStyle(.orange) }
                    TextField("接收連接埠",text:$port)
                } header: { Text("網路接收") } footer: { Text("自動監聽所有 IPv4 介面，只接受已啟用的印表機 IP。請在影印機目的地填入可連通的其中一個 Mac 位址；本程式不會自動修改通訊錄。") }
                Section {
                    Toggle("登入 Mac 後啟動",isOn:$login).toggleStyle(.switch)
                    Toggle("程式啟動時開始接收",isOn:$draft.autoReceive).toggleStyle(.switch)
                } header: { Text("啟動與常駐") } footer: { Text("僅在選單列常駐；Mac 休眠或登出時無法接收。登入啟動：\(model.loginStatus)") }
                Section {
                    Picker("紀錄保留期間",selection:$draft.retentionDays) { Text("30 天").tag(30); Text("90 天").tag(90); Text("1 年").tag(365); Text("不自動清除").tag(0) }
                    Toggle("診斷記錄",isOn:$draft.diagnostic).toggleStyle(.switch)
                    HStack { Text("接收記錄檔"); Spacer(); Button("開啟記錄資料夾") { model.openFolder(model.dataDirectory.appendingPathComponent("Logs").path) }.neutralGlass() }
                } header: { Text("紀錄與診斷") } footer: { Text("保留期間只影響掃描紀錄，不刪除文件；最多顯示最新 5,000 筆。記錄可能包含檔名與 IP，分享前請遮蔽。") }
            }.formStyle(.grouped)
            HStack {
                Text("儲存設定會重新啟動正在執行的接收服務。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.neutralGlass().keyboardShortcut(.cancelAction)
                Button("儲存設定") {
                    guard let value = Int(port) else { localError = "請填寫有效的接收連接埠。"; return }
                    draft.port = value
                    // 視窗開啟期間其他管理視窗可能調整印表機，不覆蓋最新清單。
                    draft.printers = model.configuration.printers
                    if model.commit(draft) {
                        if login != model.loginEnabled { model.setLogin(login) }
                        if model.errorMessage == nil { dismiss() }
                        else { localError = model.errorMessage; model.errorMessage = nil }
                    } else { localError = model.errorMessage; model.errorMessage = nil }
                }.buttonStyle(.glassProminent).disabled(!changed || !model.canChangeConfiguration)
            }.padding(.horizontal,20).padding(.bottom,16)
        }.frame(width:760,height:760).buttonBorderShape(.capsule).navigationTitle("共用設定")
        .alert("ScanInbox",isPresented:Binding(get:{localError != nil},set:{if !$0 {localError = nil}})) { Button("好") { localError = nil } } message: { Text(localError ?? "") }
    }
}
struct DiagnosticView: View {
    @ObservedObject var model: ScannerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("接收診斷記錄").font(.title2.bold())
            ScrollView { Text(model.diagnosticText.isEmpty ? "尚無記錄" : model.diagnosticText).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(minHeight:300)
            HStack { Button("開啟記錄資料夾") { model.openFolder(model.dataDirectory.appendingPathComponent("Logs").path) }.neutralGlass(); Spacer(); Button("關閉") { dismiss() }.buttonStyle(.glassProminent) }
        }.padding(24).frame(width:800,height:500).buttonBorderShape(.capsule)
    }
}
