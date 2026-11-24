import Foundation

@main struct NavigationTests {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            if !value { fatalError(message) }
            checks += 1
        }
        let rows = [("one", "page.pdf", "Office"), ("two", "receipt.pdf", "Home"), ("removed", "old.pdf", "Archive")]
        func count(_ selected: SidebarSelection?, _ query: String = "") -> Int {
            rows.filter { HistoryFilter.includes(printerID:$0.0,filename:$0.1,alias:$0.2,selection:selected,query:query) }.count
        }
        expect(count(.allHistory) == 3, "All history must include every printer, including removed printers")
        expect(count(.printer("one")) == 1, "A printer selection must filter by its ID")
        expect(count(.printer("unknown")) == 0, "Unknown printer must not show another printer's records")
        expect(count(nil) == 3, "No selection falls back to all history")
        expect(count(.allHistory, "PDF") == 3, "Search remains case insensitive across all history")
        expect(count(.allHistory, "home") == 1, "All-history search must match aliases")
        expect(count(.printer("one"), "home") == 0, "Search must preserve printer scope")
        expect(SidebarSelection.allHistory.printerID == nil, "All history has no printer ID")
        expect(SidebarSelection.printer("one").printerID == "one", "Printer selection exposes its ID")
        expect(!WindowVisibilityRules.shouldShowDock([]), "No windows means menu-bar-only mode")
        expect(WindowVisibilityRules.shouldShowDock([WindowPresence(visible:true,minimized:false,closing:false)]), "Visible windows must be accessible in Dock and app switcher")
        expect(WindowVisibilityRules.shouldShowDock([WindowPresence(visible:false,minimized:true,closing:false)]), "Minimized windows must remain accessible")
        expect(!WindowVisibilityRules.shouldShowDock([WindowPresence(visible:true,minimized:false,closing:true)]), "Closing the last window must hide Dock before isVisible updates")
        expect(WindowVisibilityRules.shouldShowDock([WindowPresence(visible:true,minimized:false,closing:true),WindowPresence(visible:true,minimized:false,closing:false)]), "Closing one window must not hide another visible window")
        var receipts = ReceiptBatch()
        expect(receipts.accept("first"), "New completion must notify")
        expect(!receipts.accept("first"), "Repeated completion must not notify twice")
        expect(receipts.accept("second"), "Another completed file must notify")
        print("Navigation and window policy: \(checks) checks passed")
    }
}
