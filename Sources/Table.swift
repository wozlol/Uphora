import AppKit

enum Align { case none, left, center, right }

struct TableBlock {
    /// Content range of every line (newline excluded). Line 0 is the header, line 1 the separator.
    var lines: [NSRange]
    var range: NSRange { NSRange(location: lines[0].location, length: NSMaxRange(lines.last!) - lines[0].location) }
}

struct TableModel {
    /// rows[0] is the header, the separator row is not stored.
    var rows: [[String]]
    var aligns: [Align]
    var cols: Int { aligns.count }
}

struct CaretCell {
    var row: Int
    var col: Int
    /// Characters from the start of the cell text (leading spaces skipped) to the caret.
    var offset: Int
}

enum Table {
    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }

    /// Cell ranges of one line, relative to the line start. Pipes at the very start and end are optional.
    static func splitCells(_ s: NSString) -> [NSRange] {
        let n = s.length
        var start = 0
        var i = 0
        while i < n, isSpace(s.character(at: i)) { i += 1 }
        if i < n, s.character(at: i) == 124 { start = i + 1 }
        var end = n
        var j = n
        while j > start, isSpace(s.character(at: j - 1)) { j -= 1 }
        if j > start, s.character(at: j - 1) == 124, !(j - 2 >= 0 && s.character(at: j - 2) == 92) { end = j - 1 }
        var cells: [NSRange] = []
        var cs = start
        var k = start
        while k < end {
            let c = s.character(at: k)
            if c == 92 { k += 2; continue }
            if c == 124 {
                cells.append(NSRange(location: cs, length: k - cs))
                cs = k + 1
            }
            k += 1
        }
        cells.append(NSRange(location: cs, length: max(0, end - cs)))
        return cells
    }

    static func isSeparator(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }
        let ns = line as NSString
        for r in splitCells(ns) {
            var t = ns.substring(with: r).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(":") { t.removeFirst() }
            if t.hasSuffix(":") { t.removeLast() }
            if t.isEmpty || t.contains(where: { $0 != "-" }) { return false }
        }
        return true
    }

    static func find(in text: NSString) -> [TableBlock] {
        var lines: [NSRange] = []
        var loc = 0
        while loc < text.length {
            let lr = text.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(lr)
            var e = NSMaxRange(lr)
            while e > lr.location, [10, 13].contains(text.character(at: e - 1)) { e -= 1 }
            lines.append(NSRange(location: lr.location, length: e - lr.location))
        }
        var blocks: [TableBlock] = []
        var inFence = false
        var i = 0
        while i < lines.count {
            let l = text.substring(with: lines[i])
            if l.hasPrefix("```") || l.hasPrefix("~~~") {
                inFence.toggle()
                i += 1
                continue
            }
            if !inFence, l.contains("|"), i + 1 < lines.count {
                let s = text.substring(with: lines[i + 1])
                if isSeparator(s), splitCells(l as NSString).count == splitCells(s as NSString).count {
                    var rows = [lines[i], lines[i + 1]]
                    var j = i + 2
                    while j < lines.count, text.substring(with: lines[j]).contains("|") {
                        rows.append(lines[j])
                        j += 1
                    }
                    blocks.append(TableBlock(lines: rows))
                    i = j
                    continue
                }
            }
            i += 1
        }
        return blocks
    }

    /// Aligns every table in a string. Used when a file is opened so the grid lines up.
    static func tidy(_ s: String, maxChars: Int = Int.max) -> String {
        var out = s as NSString
        for b in find(in: out).reversed() {
            let new = render(parse(b, text: out), maxChars: maxChars).text
            if new != out.substring(with: b.range) { out = out.replacingCharacters(in: b.range, with: new) as NSString }
        }
        return out as String
    }

    /// Locations of the unescaped pipes in one line.
    static func pipes(in text: NSString, line: NSRange) -> [Int] {
        var out: [Int] = []
        var k = line.location
        let e = NSMaxRange(line)
        while k < e {
            let c = text.character(at: k)
            if c == 92 { k += 2; continue }
            if c == 124 { out.append(k) }
            k += 1
        }
        return out
    }

    private static func alignOf(_ s: String) -> Align {
        let t = s.trimmingCharacters(in: .whitespaces)
        switch (t.hasPrefix(":"), t.hasSuffix(":")) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        default: return .none
        }
    }

    private static func leftTrim(_ s: String) -> String { String(s.drop { $0 == " " || $0 == "\t" }) }
    private static func rightTrim(_ s: String) -> String {
        var t = s
        while let l = t.last, l == " " || l == "\t" { t.removeLast() }
        return t
    }

    /// Reads a table into a model. With `caret`, trailing spaces up to the caret in that cell are kept so typing a space works.
    static func parse(_ b: TableBlock, text: NSString, caret: CaretCell? = nil) -> TableModel {
        var rows: [[String]] = []
        var aligns: [Align] = []
        for (li, lr) in b.lines.enumerated() {
            let line = text.substring(with: lr) as NSString
            let cells = splitCells(line)
            if li == 1 {
                aligns = cells.map { alignOf(line.substring(with: $0)) }
                continue
            }
            let modelRow = li == 0 ? 0 : li - 1
            var out: [String] = []
            for (ci, cr) in cells.enumerated() {
                var t = leftTrim(line.substring(with: cr))
                if let c = caret, c.row == modelRow, c.col == ci {
                    let u = t as NSString
                    let o = min(c.offset, u.length)
                    t = u.substring(to: o) + rightTrim(u.substring(from: o))
                } else {
                    t = rightTrim(t)
                }
                out.append(t)
            }
            rows.append(out)
        }
        let cols = max(aligns.count, rows.map { $0.count }.max() ?? 0, 1)
        while aligns.count < cols { aligns.append(.none) }
        rows = rows.map { r in
            var r = r
            while r.count < cols { r.append("") }
            return r
        }
        return TableModel(rows: rows, aligns: aligns)
    }

    /// Writes a model as aligned text. Also returns the content range of every cell, relative to the start of the table.
    static func render(_ m: TableModel, maxChars: Int = Int.max) -> (text: String, cells: [[NSRange]]) {
        let widths = (0..<m.cols).map { c in max(3, m.rows.map { $0[c].count }.max() ?? 0) }
        // Padding every cell to the widest one only helps when the table fits. Otherwise keep each cell as short as it is.
        let compact = 1 + widths.reduce(0, { $0 + $1 + 3 }) > maxChars
        var lines: [String] = []
        var cellRanges: [[NSRange]] = []
        var base = 0
        for (ri, row) in m.rows.enumerated() {
            var s = "|"
            var rs: [NSRange] = []
            for c in 0..<m.cols {
                let t = row[c]
                let pad = compact ? 0 : widths[c] - t.count
                let left: Int
                let right: Int
                switch m.aligns[c] {
                case .right: left = pad; right = 0
                case .center: left = pad / 2; right = pad - pad / 2
                default: left = 0; right = pad
                }
                rs.append(NSRange(location: base + (s as NSString).length + 1 + left, length: (t as NSString).length))
                s += " " + String(repeating: " ", count: left) + t + String(repeating: " ", count: right) + " |"
            }
            lines.append(s)
            cellRanges.append(rs)
            base += (s as NSString).length + 1
            if ri == 0 {
                var sep = "|"
                for c in 0..<m.cols {
                    let w = compact ? 3 : widths[c]
                    switch m.aligns[c] {
                    case .left: sep += ":" + String(repeating: "-", count: w + 1)
                    case .right: sep += String(repeating: "-", count: w + 1) + ":"
                    case .center: sep += ":" + String(repeating: "-", count: w) + ":"
                    case .none: sep += String(repeating: "-", count: w + 2)
                    }
                    sep += "|"
                }
                lines.append(sep)
                base += (sep as NSString).length + 1
            }
        }
        return (lines.joined(separator: "\n"), cellRanges)
    }

    /// Which line and cell a caret position is in. The separator line (index 1) has no cell.
    static func caretCell(_ b: TableBlock, text: NSString, at pos: Int) -> (lineIdx: Int, cell: CaretCell?)? {
        for (li, lr) in b.lines.enumerated() where pos >= lr.location && pos <= NSMaxRange(lr) {
            if li == 1 { return (1, nil) }
            let line = text.substring(with: lr) as NSString
            let cells = splitCells(line)
            let cc = pos - lr.location
            var col = cells.count - 1
            for (ci, r) in cells.enumerated() where cc <= NSMaxRange(r) {
                col = ci
                break
            }
            let r = cells[col]
            let raw = line.substring(with: r) as NSString
            var lead = 0
            while lead < raw.length, isSpace(raw.character(at: lead)) { lead += 1 }
            let o = max(0, cc - (r.location + lead))
            return (li, CaretCell(row: li == 0 ? 0 : li - 1, col: col, offset: o))
        }
        return nil
    }
}
