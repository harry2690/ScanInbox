import Foundation

// A selectable row must not use nil, which List reserves for no selection.
enum SidebarSelection: Hashable {
    case allHistory
    case printer(String)

    var printerID: String? {
        if case .printer(let id) = self { return id }
        return nil
    }
    func includes(printerID: String) -> Bool {
        switch self {
        case .allHistory: return true
        case .printer(let id): return id == printerID
        }
    }
}

enum HistoryFilter {
    static func includes(printerID: String, filename: String, alias: String, selection: SidebarSelection?, query: String) -> Bool {
        let inScope = selection?.includes(printerID: printerID) ?? true
        return inScope && (query.isEmpty || filename.localizedCaseInsensitiveContains(query) || alias.localizedCaseInsensitiveContains(query))
    }
}

struct WindowPresence {
    var visible: Bool
    var minimized: Bool
    var closing: Bool
}
enum WindowVisibilityRules {
    static func shouldShowDock(_ windows: [WindowPresence]) -> Bool {
        windows.contains { !$0.closing && ($0.visible || $0.minimized) }
    }
}

// Bound deduplication memory while ignoring repeated live completion events.
struct ReceiptBatch {
    private var seen = Set<String>()
    private var order: [String] = []
    mutating func accept(_ id:String) -> Bool {
        guard seen.insert(id).inserted else { return false }
        order.append(id)
        if order.count > 5000 { seen.remove(order.removeFirst()) }
        return true
    }
}
