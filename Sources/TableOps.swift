import AppKit

private extension String {
    var ns: NSString { self as NSString }
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}

struct TableContext {
    var block: TableBlock
    var lineIdx: Int
    var cell: CaretCell?
    var row: Int { cell?.row ?? 0 }
    var col: Int { cell?.col ?? 0 }
}

extension EditorController {
    /// How many characters of a table line fit across the window, so wide tables are not padded into a grid.
    var tableMaxChars: Int {
        guard Prefs.wrap, let w = textView.textContainer?.containerSize.width, w < 1e6 else { return Int.max }
        let f = NSFont.monospacedSystemFont(ofSize: Prefs.size * 0.9, weight: .regular)
        let adv = "0".size(withAttributes: [.font: f]).width
        return max(20, Int(w / adv) - 1)
    }

    func tableContext() -> TableContext? {
        guard mdDocument?.isMarkdown ?? true else { return nil }
        let pos = textView.selectedRange().location
        let t = text
        for b in Table.find(in: t) where pos >= b.range.location && pos <= NSMaxRange(b.range) {
            if let (li, cc) = Table.caretCell(b, text: t, at: pos) { return TableContext(block: b, lineIdx: li, cell: cc) }
        }
        return nil
    }

    /// Replaces the table with the model and puts the caret in a cell.
    func applyTable(_ b: TableBlock, _ m: TableModel, cell: (Int, Int)?, selectContent: Bool = true) {
        let (str, cells) = Table.render(m, maxChars: tableMaxChars)
        var sel: NSRange?
        if let (r, c) = cell, r < cells.count, c < cells[r].count {
            let cr = cells[r][c]
            sel = NSRange(location: b.range.location + cr.location + (selectContent ? 0 : cr.length), length: selectContent ? cr.length : 0)
        }
        if str == text.substring(with: b.range) {
            if let s = sel { textView.setSelectedRange(s) }
        } else {
            formatting = true
            edit(b.range, str, select: sel)
            formatting = false
        }
    }

    /// Keeps the table aligned while typing in it.
    func realignTable() {
        guard !formatting, !textView.hasMarkedText(), let t = tableContext(), t.lineIdx != 1, let cc = t.cell else { return }
        let m = Table.parse(t.block, text: text, caret: cc)
        let (str, cells) = Table.render(m, maxChars: tableMaxChars)
        if str == text.substring(with: t.block.range) { return }
        let r = cells[cc.row][min(cc.col, m.cols - 1)]
        formatting = true
        edit(t.block.range, str, select: NSRange(location: t.block.range.location + r.location + min(cc.offset, r.length), length: 0))
        formatting = false
    }

    // MARK: moving around

    func tableTab(_ dir: Int) -> Bool {
        guard let t = tableContext() else { return false }
        var m = Table.parse(t.block, text: text)
        var row = t.row
        var col = t.col + dir
        if col >= m.cols { col = 0; row += 1 }
        if col < 0 { col = m.cols - 1; row -= 1 }
        if row < 0 { row = 0; col = 0 }
        if row >= m.rows.count { m.rows.append(Array(repeating: "", count: m.cols)) }
        applyTable(t.block, m, cell: (row, col))
        return true
    }

    func tableEnter() -> Bool {
        guard let t = tableContext() else { return false }
        var m = Table.parse(t.block, text: text)
        let row = t.row
        if row > 0, row == m.rows.count - 1, m.rows[row].allSatisfy({ $0.isEmpty }) {
            m.rows.removeLast()
            let out = Table.render(m, maxChars: tableMaxChars).text + "\n\n"
            formatting = true
            edit(t.block.range, out, select: NSRange(location: t.block.range.location + out.ns.length, length: 0))
            formatting = false
            return true
        }
        if row + 1 >= m.rows.count { m.rows.append(Array(repeating: "", count: m.cols)) }
        applyTable(t.block, m, cell: (row + 1, t.col))
        return true
    }

    // MARK: menu and toolbar actions

    @objc func fmtTable(_ s: Any?) {
        guard tableContext() == nil else { return }
        let m = TableModel(rows: [["Column 1", "Column 2", "Column 3"], ["", "", ""], ["", "", ""]], aligns: [.none, .none, .none])
        let (str, cells) = Table.render(m, maxChars: tableMaxChars)
        let start = insertBlock(str)
        let first = cells[0][0]
        textView.setSelectedRange(NSRange(location: start + first.location, length: first.length))
    }

    /// Puts text on its own paragraph at the caret and returns where it starts.
    func insertBlock(_ s: String) -> Int {
        let sel = textView.selectedRange()
        let lr = text.lineRange(for: sel)
        var end = NSMaxRange(lr)
        while end > lr.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        let lineText = text.substring(with: NSRange(location: lr.location, length: end - lr.location))
        let range: NSRange
        let prefix: String
        if lineText.isBlank {
            range = NSRange(location: lr.location, length: end - lr.location)
            prefix = ""
        } else {
            range = NSRange(location: end, length: 0)
            prefix = "\n\n"
        }
        var suffix = ""
        let next = NSMaxRange(lr)
        if next < text.length {
            let nl = text.lineRange(for: NSRange(location: next, length: 0))
            if !text.substring(with: nl).isBlank { suffix = "\n" }
        }
        formatting = true
        edit(range, prefix + s + suffix)
        formatting = false
        return range.location + prefix.ns.length
    }

    private func editModel(_ change: (inout TableModel, TableContext) -> (Int, Int)?) {
        guard let t = tableContext() else { return }
        var m = Table.parse(t.block, text: text)
        let target = change(&m, t)
        applyTable(t.block, m, cell: target)
    }

    @objc func tblRowAbove(_ s: Any?) {
        editModel { m, t in
            let r = max(1, t.row)
            m.rows.insert(Array(repeating: "", count: m.cols), at: r)
            return (r, t.col)
        }
    }

    @objc func tblRowBelow(_ s: Any?) {
        editModel { m, t in
            m.rows.insert(Array(repeating: "", count: m.cols), at: t.row + 1)
            return (t.row + 1, t.col)
        }
    }

    @objc func tblDeleteRow(_ s: Any?) {
        editModel { m, t in
            guard t.row > 0 else { return (0, t.col) }
            m.rows.remove(at: t.row)
            return (min(t.row, m.rows.count - 1), t.col)
        }
    }

    @objc func tblColLeft(_ s: Any?) {
        editModel { m, t in
            for i in 0..<m.rows.count { m.rows[i].insert("", at: t.col) }
            m.aligns.insert(.none, at: t.col)
            return (t.row, t.col)
        }
    }

    @objc func tblColRight(_ s: Any?) {
        editModel { m, t in
            for i in 0..<m.rows.count { m.rows[i].insert("", at: t.col + 1) }
            m.aligns.insert(.none, at: t.col + 1)
            return (t.row, t.col + 1)
        }
    }

    @objc func tblDeleteCol(_ s: Any?) {
        editModel { m, t in
            guard m.cols > 1 else { return (t.row, t.col) }
            for i in 0..<m.rows.count { m.rows[i].remove(at: t.col) }
            m.aligns.remove(at: t.col)
            return (t.row, min(t.col, m.cols - 1))
        }
    }

    private func setAlign(_ a: Align) {
        editModel { m, t in
            m.aligns[t.col] = a
            return (t.row, t.col)
        }
    }

    @objc func tblAlignLeft(_ s: Any?) { setAlign(.left) }
    @objc func tblAlignCenter(_ s: Any?) { setAlign(.center) }
    @objc func tblAlignRight(_ s: Any?) { setAlign(.right) }
    @objc func tblAlignNone(_ s: Any?) { setAlign(.none) }

    @objc func tblDelete(_ s: Any?) {
        guard let t = tableContext() else { return }
        edit(t.block.range, "", select: NSRange(location: t.block.range.location, length: 0))
    }

    // MARK: images

    @objc func fmtImage(_ s: Any?) {
        guard let win = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: win) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self?.insertImage(url) }
        }
    }

    func insertImage(_ url: URL) {
        var path = url.path
        if let base = mdDocument?.fileURL?.deletingLastPathComponent().path, path.hasPrefix(base + "/") {
            path = String(path.dropFirst(base.count + 1))
        }
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let alt = url.deletingPathExtension().lastPathComponent
        let start = insertBlock("![\(alt)](\(enc))")
        textView.setSelectedRange(NSRange(location: start, length: 0))
    }

    func tableMenu() -> NSMenu {
        let m = NSMenu(title: "Table")
        func add(_ t: String, _ a: Selector) {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        add("Add Row Above", #selector(tblRowAbove(_:)))
        add("Add Row Below", #selector(tblRowBelow(_:)))
        add("Delete Row", #selector(tblDeleteRow(_:)))
        m.addItem(.separator())
        add("Add Column Left", #selector(tblColLeft(_:)))
        add("Add Column Right", #selector(tblColRight(_:)))
        add("Delete Column", #selector(tblDeleteCol(_:)))
        m.addItem(.separator())
        add("Align Column Left", #selector(tblAlignLeft(_:)))
        add("Align Column Center", #selector(tblAlignCenter(_:)))
        add("Align Column Right", #selector(tblAlignRight(_:)))
        add("Clear Column Alignment", #selector(tblAlignNone(_:)))
        m.addItem(.separator())
        add("Delete Table", #selector(tblDelete(_:)))
        return m
    }
}
