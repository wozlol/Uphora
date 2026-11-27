import AppKit

enum LineKind { case bullet, number, task, quote }

private func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
private let reTask = rx("^([ \\t]*)[-*+][ \\t]+\\[[ xX]\\][ \\t]+")
private let reBullet = rx("^([ \\t]*)[-*+][ \\t]+")
private let reNumber = rx("^([ \\t]*)\\d+[.)][ \\t]+")
private let reQuote = rx("^([ \\t]*)>[ \\t]?")
private let reListFull = rx("^([ \\t]*)([-*+]|\\d+[.)])[ \\t]+(\\[[ xX]\\][ \\t]+)?")
private let reQuoteFull = rx("^[ \\t]*(>[ \\t]*)+")

private extension String {
    var ns: NSString { self as NSString }
    var full: NSRange { NSRange(location: 0, length: ns.length) }
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}

private func classify(_ l: String) -> (LineKind, NSTextCheckingResult)? {
    let table: [(LineKind, NSRegularExpression)] = [(.task, reTask), (.bullet, reBullet), (.number, reNumber), (.quote, reQuote)]
    for (k, re) in table {
        if let m = re.firstMatch(in: l, range: l.full) { return (k, m) }
    }
    return nil
}

private func splitIndent(_ l: String) -> (indent: String, body: String) {
    if let (_, m) = classify(l) {
        return (l.ns.substring(with: m.range(at: 1)), l.ns.substring(from: m.range.length))
    }
    let ws = String(l.prefix { $0 == " " || $0 == "\t" })
    return (ws, String(l.dropFirst(ws.count)))
}

private func headingLevel(_ l: String) -> Int {
    let hashes = l.prefix { $0 == "#" }.count
    guard hashes >= 1, hashes <= 6, l.count > hashes else { return 0 }
    let next = l[l.index(l.startIndex, offsetBy: hashes)]
    return (next == " " || next == "\t") ? hashes : 0
}

private func stripHeading(_ l: String) -> String {
    let n = headingLevel(l)
    guard n > 0 else { return l }
    return String(l.dropFirst(n).drop { $0 == " " || $0 == "\t" })
}

extension EditorController {
    var text: NSString { textView.string as NSString }

    // MARK: editing helpers

    func edit(_ range: NSRange, _ new: String, select: NSRange? = nil) {
        guard textView.shouldChangeText(in: range, replacementString: new) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: new)
        textView.didChangeText()
        if let s = select { textView.setSelectedRange(s) }
    }

    func selectedLinesRange() -> NSRange {
        var r = textView.selectedRange()
        if r.length > 0, text.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        return text.lineRange(for: r)
    }

    func mapLines(_ f: ([String]) -> [String]) {
        let sel = textView.selectedRange()
        let r = selectedLinesRange()
        var block = text.substring(with: r)
        let hadNL = block.hasSuffix("\n")
        if hadNL { block.removeLast() }
        let out = f(block.components(separatedBy: "\n")).joined(separator: "\n")
        let delta = out.ns.length - block.ns.length
        let newSel: NSRange
        if sel.length == 0 {
            newSel = NSRange(location: max(r.location, sel.location + delta), length: 0)
        } else {
            newSel = NSRange(location: r.location, length: out.ns.length)
        }
        edit(r, out + (hadNL ? "\n" : ""), select: newSel)
    }

    // MARK: inline formats

    private func toggleInline(_ m: String) {
        var sel = textView.selectedRange()
        let ml = m.ns.length
        if sel.length == 0 {
            let w = textView.selectionRange(forProposedRange: sel, granularity: .selectByWord)
            var wr = w
            while wr.length > 0, text.substring(with: NSRange(location: NSMaxRange(wr) - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { wr.length -= 1 }
            if wr.length > 0, sel.location >= wr.location, sel.location <= NSMaxRange(wr) { sel = wr }
        }
        if sel.length == 0 {
            edit(sel, m + m, select: NSRange(location: sel.location + ml, length: 0))
            return
        }
        let t = text.substring(with: sel)
        let before = sel.location - ml
        let after = NSMaxRange(sel)
        func isMarkerAt(_ loc: Int) -> Bool {
            loc >= 0 && loc + ml <= text.length && text.substring(with: NSRange(location: loc, length: ml)) == m
        }
        var doubled = false
        if ml == 1 {
            let c = m.utf16.first!
            doubled = (before - 1 >= 0 && text.character(at: before - 1) == c) || (after + 1 < text.length && text.character(at: after + 1) == c)
        }
        if isMarkerAt(before), isMarkerAt(after), !doubled {
            edit(NSRange(location: before, length: sel.length + 2 * ml), t, select: NSRange(location: before, length: sel.length))
        } else if t.hasPrefix(m), t.hasSuffix(m), t.ns.length >= 2 * ml {
            let inner = t.ns.substring(with: NSRange(location: ml, length: t.ns.length - 2 * ml))
            edit(sel, inner, select: NSRange(location: sel.location, length: inner.ns.length))
        } else {
            edit(sel, m + t + m, select: NSRange(location: sel.location + ml, length: sel.length))
        }
    }

    @objc func fmtBold(_ s: Any?) { toggleInline("**") }
    @objc func fmtItalic(_ s: Any?) { toggleInline("*") }
    @objc func fmtStrike(_ s: Any?) { toggleInline("~~") }
    @objc func fmtCode(_ s: Any?) { toggleInline("`") }

    @objc func fmtLink(_ s: Any?) {
        let sel = textView.selectedRange()
        if sel.length > 0 {
            let t = text.substring(with: sel)
            edit(sel, "[\(t)](url)", select: NSRange(location: sel.location + t.ns.length + 3, length: 3))
        } else {
            edit(sel, "[text](url)", select: NSRange(location: sel.location + 1, length: 4))
        }
    }

    // MARK: block formats

    @objc func fmtHeading(_ s: Any?) {
        let level = (s as? NSPopUpButton)?.selectedItem?.tag ?? (s as? NSMenuItem)?.tag ?? 0
        mapLines { lines in
            lines.map { l in
                let t = stripHeading(l)
                return level > 0 ? String(repeating: "#", count: level) + " " + t : t
            }
        }
        textView.window?.makeFirstResponder(textView)
    }

    private func toggleList(_ kind: LineKind) {
        mapLines { lines in
            let filled = lines.filter { !$0.isBlank }
            let allKind = !filled.isEmpty && filled.allSatisfy { classify($0)?.0 == kind }
            var n = 0
            return lines.map { l in
                if l.isBlank && lines.count > 1 { return l }
                let (indent, body) = splitIndent(l)
                if allKind { return indent + body }
                n += 1
                switch kind {
                case .bullet: return indent + "- " + body
                case .number: return indent + "\(n). " + body
                case .task: return indent + "- [ ] " + body
                case .quote: return indent + "> " + body
                }
            }
        }
    }

    @objc func fmtBullet(_ s: Any?) { toggleList(.bullet) }
    @objc func fmtNumber(_ s: Any?) { toggleList(.number) }
    @objc func fmtTask(_ s: Any?) { toggleList(.task) }
    @objc func fmtQuote(_ s: Any?) { toggleList(.quote) }

    @objc func fmtCodeBlock(_ s: Any?) {
        let r = selectedLinesRange()
        var block = text.substring(with: r)
        if !block.hasSuffix("\n") { block += "\n" }
        if block.isBlank {
            edit(r, "```\n\n```\n", select: NSRange(location: r.location + 4, length: 0))
        } else {
            let out = "```\n" + block + "```\n"
            edit(r, out, select: NSRange(location: r.location + out.ns.length, length: 0))
        }
    }

    @objc func fmtRule(_ s: Any?) {
        let sel = textView.selectedRange()
        let lr = text.lineRange(for: sel)
        var contentEnd = NSMaxRange(lr)
        while contentEnd > lr.location, [10, 13].contains(text.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let line = text.substring(with: NSRange(location: lr.location, length: contentEnd - lr.location))
        if line.isBlank {
            edit(lr, "---\n\n", select: NSRange(location: lr.location + 5, length: 0))
        } else {
            let ins = "\n\n---\n\n"
            edit(NSRange(location: contentEnd, length: 0), ins, select: NSRange(location: contentEnd + ins.ns.length, length: 0))
        }
    }

    // MARK: Enter, Backspace, Tab

    private func insideFence(before loc: Int) -> Bool {
        var open = false
        for l in text.substring(to: loc).components(separatedBy: "\n") where l.hasPrefix("```") || l.hasPrefix("~~~") { open.toggle() }
        return open
    }

    private func currentLine() -> (content: NSRange, line: String, caret: Int)? {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return nil }
        let lr = text.lineRange(for: sel)
        var end = NSMaxRange(lr)
        while end > lr.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        let content = NSRange(location: lr.location, length: end - lr.location)
        guard sel.location <= end else { return nil }
        if insideFence(before: lr.location) { return nil }
        return (content, text.substring(with: content), sel.location - lr.location)
    }

    func handleEnter() -> Bool {
        guard let (content, line, caret) = currentLine() else { return false }
        if let m = reListFull.firstMatch(in: line, range: line.full) {
            let prefixLen = m.range.length
            guard caret >= prefixLen else { return false }
            let indent = line.ns.substring(with: m.range(at: 1))
            let rest = line.ns.substring(from: prefixLen)
            if rest.isBlank {
                if !indent.isEmpty {
                    let drop = indent.hasPrefix("\t") ? 1 : min(4, indent.count)
                    edit(NSRange(location: content.location, length: drop), "",
                         select: NSRange(location: content.location + line.ns.length - drop, length: 0))
                } else {
                    edit(content, "", select: NSRange(location: content.location, length: 0))
                }
                return true
            }
            let marker = line.ns.substring(with: m.range(at: 2))
            var next = marker
            if let d = marker.first, d.isNumber {
                next = "\((Int(marker.dropLast()) ?? 0) + 1)" + String(marker.last!)
            }
            let task = m.range(at: 3).location != NSNotFound ? "[ ] " : ""
            let ins = "\n" + indent + next + " " + task
            edit(NSRange(location: textView.selectedRange().location, length: 0), ins,
                 select: NSRange(location: textView.selectedRange().location + ins.ns.length, length: 0))
            return true
        }
        if let m = reQuoteFull.firstMatch(in: line, range: line.full) {
            let prefix = line.ns.substring(with: m.range)
            guard caret >= m.range.length else { return false }
            let rest = line.ns.substring(from: m.range.length)
            if rest.isBlank {
                edit(content, "", select: NSRange(location: content.location, length: 0))
                return true
            }
            let ins = "\n" + prefix
            let loc = textView.selectedRange().location
            edit(NSRange(location: loc, length: 0), ins, select: NSRange(location: loc + ins.ns.length, length: 0))
            return true
        }
        return false
    }

    func handleBackspace() -> Bool {
        guard let (content, line, caret) = currentLine(), caret == line.ns.length, line.ns.length > 0 else { return false }
        var prefixLen = -1
        if let m = reListFull.firstMatch(in: line, range: line.full) { prefixLen = m.range.length }
        else if let m = reQuoteFull.firstMatch(in: line, range: line.full) { prefixLen = m.range.length }
        guard prefixLen == line.ns.length else { return false }
        edit(content, "", select: NSRange(location: content.location, length: 0))
        return true
    }

    func indentLists(_ dir: Int) -> Bool {
        let r = selectedLinesRange()
        let block = text.substring(with: r)
        guard block.components(separatedBy: "\n").contains(where: { reListFull.firstMatch(in: $0, range: $0.full) != nil }) else { return false }
        mapLines { lines in
            lines.map { l in
                guard reListFull.firstMatch(in: l, range: l.full) != nil else { return l }
                if dir > 0 { return "    " + l }
                if l.hasPrefix("\t") { return String(l.dropFirst()) }
                let spaces = min(4, l.prefix { $0 == " " }.count)
                return String(l.dropFirst(spaces))
            }
        }
        return true
    }

    func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard mdDocument?.isMarkdown ?? true else { return false }
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): return tableEnter() || handleEnter()
        case #selector(NSResponder.deleteBackward(_:)): return handleBackspace()
        case #selector(NSResponder.insertTab(_:)): return tableTab(1) || indentLists(1)
        case #selector(NSResponder.insertBacktab(_:)): return tableTab(-1) || indentLists(-1)
        default: return false
        }
    }

    func updateStyleUI() {
        guard let popup = stylePopup else { return }
        popup.isEnabled = mdDocument?.isMarkdown ?? true
        let lr = text.lineRange(for: textView.selectedRange())
        let line = text.substring(with: lr).trimmingCharacters(in: .newlines)
        popup.selectItem(withTag: headingLevel(line))
    }
}

extension EditorController: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let a = item.action else { return true }
        let fmt: [Selector] = [#selector(fmtBold(_:)), #selector(fmtItalic(_:)), #selector(fmtStrike(_:)), #selector(fmtCode(_:)),
                               #selector(fmtLink(_:)), #selector(fmtHeading(_:)), #selector(fmtBullet(_:)), #selector(fmtNumber(_:)),
                               #selector(fmtTask(_:)), #selector(fmtQuote(_:)), #selector(fmtCodeBlock(_:)), #selector(fmtRule(_:))]
        if a == #selector(togglePreview(_:)) {
            (item as? NSMenuItem)?.state = previewing ? .on : .off
            return mdDocument?.isMarkdown ?? true
        }
        if fmt.contains(a) || a == #selector(fmtTable(_:)) || a == #selector(fmtImage(_:)) { return !previewing && (mdDocument?.isMarkdown ?? true) }
        let ops: [Selector] = [#selector(tblRowAbove(_:)), #selector(tblRowBelow(_:)), #selector(tblDeleteRow(_:)), #selector(tblColLeft(_:)),
                               #selector(tblColRight(_:)), #selector(tblDeleteCol(_:)), #selector(tblAlignLeft(_:)), #selector(tblAlignCenter(_:)),
                               #selector(tblAlignRight(_:)), #selector(tblAlignNone(_:)), #selector(tblDelete(_:))]
        if ops.contains(a) { return !previewing && tableContext() != nil }
        return true
    }
}

extension EditorController: NSToolbarDelegate {
    private static let ids = ["style", "bold", "italic", "strike", "code", "link", "bullet", "number", "task", "quote", "codeblock", "rule"]

    func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "UphoraToolbar")
        t.delegate = self
        t.displayMode = .iconOnly
        return t
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let i = NSToolbarItem.Identifier.self
        return [i.init("style"), .space, i.init("bold"), i.init("italic"), i.init("strike"), i.init("code"), i.init("link"), .space,
                i.init("bullet"), i.init("number"), i.init("task"), i.init("quote"), .space, i.init("codeblock"), i.init("rule"), .space,
                i.init("table"), i.init("tabletools"), i.init("image"), .space, i.init("preview")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        if id.rawValue == "style" {
            let p = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 26), pullsDown: false)
            p.addItem(withTitle: "Normal")
            p.lastItem?.tag = 0
            for n in 1...6 {
                p.addItem(withTitle: "Heading \(n)")
                p.lastItem?.tag = n
            }
            p.target = self
            p.action = #selector(fmtHeading(_:))
            stylePopup = p
            item.view = p
            item.label = "Style"
            item.toolTip = "Paragraph style"
            return item
        }
        if id.rawValue == "tabletools" {
            let mi = NSMenuToolbarItem(itemIdentifier: id)
            mi.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Table Tools")
            mi.label = "Table Tools"
            mi.toolTip = "Table Tools: add and delete rows and columns, align columns"
            mi.menu = tableMenu()
            mi.showsIndicator = true
            return mi
        }
        let table: [String: (String, String, Selector)] = [
            "table": ("tablecells", "Insert Table", #selector(fmtTable(_:))),
            "image": ("photo", "Insert Image", #selector(fmtImage(_:))),
            "preview": ("eye", "GitHub View", #selector(togglePreview(_:))),
            "bold": ("bold", "Bold", #selector(fmtBold(_:))),
            "italic": ("italic", "Italic", #selector(fmtItalic(_:))),
            "strike": ("strikethrough", "Strikethrough", #selector(fmtStrike(_:))),
            "code": ("chevron.left.forwardslash.chevron.right", "Inline Code", #selector(fmtCode(_:))),
            "link": ("link", "Link", #selector(fmtLink(_:))),
            "bullet": ("list.bullet", "Bulleted List", #selector(fmtBullet(_:))),
            "number": ("list.number", "Numbered List", #selector(fmtNumber(_:))),
            "task": ("checklist", "Task List", #selector(fmtTask(_:))),
            "quote": ("text.quote", "Quote", #selector(fmtQuote(_:))),
            "codeblock": ("curlybraces", "Code Block", #selector(fmtCodeBlock(_:))),
            "rule": ("minus", "Horizontal Rule", #selector(fmtRule(_:))),
        ]
        guard let (symbol, label, action) = table[id.rawValue] else { return nil }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }
}
