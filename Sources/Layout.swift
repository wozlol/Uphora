import AppKit

extension NSAttributedString.Key {
    static let uphoraTable = NSAttributedString.Key("uphoraTable")
    static let uphoraImage = NSAttributedString.Key("uphoraImage")
    static let uphoraLink = NSAttributedString.Key("uphoraLink")
    static let uphoraTableBlock = NSAttributedString.Key("uphoraTableBlock")
}

extension Notification.Name {
    static let imageLoaded = Notification.Name("UphoraImageLoaded")
}

/// An image shown under its Markdown line.
final class ImageRef: NSObject {
    let url: String
    let base: URL?
    let size: NSSize
    init(url: String, base: URL?, size: NSSize) {
        self.url = url
        self.base = base
        self.size = size
    }
}

/// Sizes of a rendered table: cells wrap inside columns, like a table on GitHub.
struct TableLayout {
    static let hPad: CGFloat = 12
    static let vPad: CGFloat = 6
    var colWidths: [CGFloat] = []
    var rowHeights: [CGFloat] = []
    var width: CGFloat { colWidths.reduce(0, +) + 1 }
    var height: CGFloat { rowHeights.reduce(0, +) + 1 }

    init(cells: [[NSAttributedString]], available: CGFloat) {
        let cols = cells.first?.count ?? 0
        guard cols > 0 else { return }
        let hp = TableLayout.hPad
        var minW = [CGFloat](repeating: 0, count: cols)
        var maxW = [CGFloat](repeating: 0, count: cols)
        for row in cells {
            for (c, cell) in row.enumerated() {
                let multi = cell.string.contains("\n")
                maxW[c] = max(maxW[c], multi ? cell.boundingRect(with: NSSize(width: 1e6, height: 1e6), options: [.usesLineFragmentOrigin]).width : cell.size().width)
                let ns = cell.string as NSString
                var start = 0
                for i in 0...ns.length {
                    if i == ns.length || ns.character(at: i) == 32 || ns.character(at: i) == 10 {
                        if i > start {
                            minW[c] = max(minW[c], cell.attributedSubstring(from: NSRange(location: start, length: i - start)).size().width)
                        }
                        start = i + 1
                    }
                }
            }
        }
        let room = max(60, available - 2)
        for c in 0..<cols {
            minW[c] = min(ceil(minW[c]), max(60, room * 0.45))
            maxW[c] = max(ceil(maxW[c]), minW[c])
        }
        let natural = maxW.reduce(0) { $0 + $1 + 2 * hp }
        var widths = [CGFloat](repeating: 0, count: cols)
        if natural <= room {
            for c in 0..<cols { widths[c] = maxW[c] + 2 * hp }
        } else {
            for c in 0..<cols { widths[c] = minW[c] + 2 * hp }
            var left = room - widths.reduce(0, +)
            if left > 0 {
                let extra = (0..<cols).map { maxW[$0] - minW[$0] }
                let total = extra.reduce(0, +)
                if total > 0 {
                    let share = min(1, left / total)
                    for c in 0..<cols { widths[c] += extra[c] * share }
                    left -= total * share
                }
            }
        }
        colWidths = widths.map { ceil($0) }
        // Whole pixels can add up to a little more than the room. Take the excess from the widest column so the right border stays inside.
        let over = colWidths.reduce(0, +) - room
        if over > 0, let widest = colWidths.indices.max(by: { colWidths[$0] < colWidths[$1] }) { colWidths[widest] -= over }
        rowHeights = cells.map { row in
            let h = row.enumerated().map { c, cell in
                ceil(cell.boundingRect(with: NSSize(width: colWidths[c] - 2 * hp, height: 1e6), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            }.max() ?? 0
            return max(h, 17) + 2 * TableLayout.vPad
        }
    }
}

/// A table drawn as a grid under its hidden Markdown lines.
final class TableRef: NSObject {
    let cells: [[NSAttributedString]]
    let aligns: [Align]
    let layout: TableLayout
    init(cells: [[NSAttributedString]], aligns: [Align], available: CGFloat) {
        self.cells = cells
        self.aligns = aligns
        self.layout = TableLayout(cells: cells, available: available)
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private var pending: Set<String> = []

    private func resolve(_ ref: String, base: URL?) -> URL? {
        let decoded = ref.removingPercentEncoding ?? ref
        if ref.hasPrefix("http://") || ref.hasPrefix("https://") || ref.hasPrefix("file://") { return URL(string: ref) }
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        guard let base = base else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    func image(_ ref: String, base: URL?) -> NSImage? {
        guard let url = resolve(ref, base: base) else { return nil }
        let key = url.absoluteString
        if let i = images[key] { return i }
        if missing.contains(key) { return nil }
        if url.isFileURL {
            if let i = NSImage(contentsOf: url) {
                images[key] = i
                return i
            }
            missing.insert(key)
            return nil
        }
        if pending.contains(key) { return nil }
        pending.insert(key)
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                self.pending.remove(key)
                if let d = data, let i = NSImage(data: d) {
                    self.images[key] = i
                    NotificationCenter.default.post(name: .imageLoaded, object: nil)
                } else {
                    self.missing.insert(key)
                }
            }
        }.resume()
        return nil
    }
}

/// Draws table grids and images behind the text.
final class EditorLayoutManager: NSLayoutManager {
    private var gridColor: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.5) }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let tc = textContainers.first, storage.length > 0 else { return }
        let text = storage.string as NSString
        var cr = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        cr = text.lineRange(for: cr)

        storage.enumerateAttribute(.uphoraTable, in: cr, options: []) { value, r, _ in
            guard let n = value as? Int else { return }
            drawTableRow(role: n & 3, range: r, text: text, tc: tc, origin: origin)
        }
        storage.enumerateAttribute(.uphoraTableBlock, in: cr, options: []) { value, r, _ in
            guard let ref = value as? TableRef, let rect = tableRect(ref, range: r, origin: origin) else { return }
            drawTableBlock(ref, in: rect)
        }
        storage.enumerateAttribute(.uphoraImage, in: cr, options: []) { value, r, _ in
            guard let ref = value as? ImageRef, let img = ImageCache.shared.image(ref.url, base: ref.base) else { return }
            let gr = glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard gr.length > 0 else { return }
            let used = lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)
            let rect = NSRect(x: origin.x + used.minX, y: origin.y + used.maxY + 6, width: ref.size.width, height: ref.size.height)
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }

    /// Where a rendered table is drawn, in the coordinates of the text view.
    func tableRect(_ ref: TableRef, range r: NSRange, origin: NSPoint) -> NSRect? {
        let gr = glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        guard gr.length > 0 else { return nil }
        let used = lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)
        return NSRect(x: origin.x + used.minX, y: origin.y + used.maxY + 4, width: ref.layout.width, height: ref.layout.height)
    }

    private func drawTableBlock(_ ref: TableRef, in rect: NSRect) {
        let L = ref.layout
        let line = NSColor.secondaryLabelColor.withAlphaComponent(0.45)
        var y = rect.minY
        for (r, row) in ref.cells.enumerated() {
            let h = L.rowHeights[r]
            if r > 0, r % 2 == 0 {
                NSColor.secondaryLabelColor.withAlphaComponent(0.09).setFill()
                NSRect(x: rect.minX, y: y, width: rect.width, height: h).fill()
            }
            var x = rect.minX
            for (c, cell) in row.enumerated() {
                let cw = L.colWidths[c]
                let box = NSRect(x: x + TableLayout.hPad, y: y + TableLayout.vPad, width: cw - 2 * TableLayout.hPad, height: h - 2 * TableLayout.vPad)
                cell.draw(with: box, options: [.usesLineFragmentOrigin])
                x += cw
            }
            line.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += h
        }
        line.setFill()
        NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
        var x = rect.minX
        for cw in L.colWidths + [0] {
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
            x += cw
        }
    }

    private func drawTableRow(role: Int, range r: NSRange, text: NSString, tc: NSTextContainer, origin: NSPoint) {
        let gr = glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        guard gr.length > 0 else { return }
        let frag = lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
        // The separator row is drawn tiny, so it borrows the pipe positions of the header above it.
        var source = r
        if role == 1, r.location > 0 {
            let prev = text.lineRange(for: NSRange(location: r.location - 1, length: 0))
            var e = NSMaxRange(prev)
            while e > prev.location, [10, 13].contains(text.character(at: e - 1)) { e -= 1 }
            source = NSRange(location: prev.location, length: e - prev.location)
        }
        let xs: [CGFloat] = Table.pipes(in: text, line: source).compactMap { p in
            let g = glyphRange(forCharacterRange: NSRange(location: p, length: 1), actualCharacterRange: nil)
            let b = boundingRect(forGlyphRange: g, in: tc)
            return b.width > 0 ? b.midX + origin.x : nil
        }
        guard let x0 = xs.first, let x1 = xs.last, x1 > x0 else { return }
        gridColor.setFill()
        switch role {
        case 0:
            NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
            NSRect(x: x0, y: frag.minY, width: x1 - x0, height: frag.height).fill()
            gridColor.setFill()
            NSRect(x: x0, y: frag.minY - 0.5, width: x1 - x0, height: 1).fill()
        case 1:
            NSRect(x: x0, y: frag.midY - 0.75, width: x1 - x0, height: 1.5).fill()
            return
        default:
            NSRect(x: x0, y: frag.maxY - 0.5, width: x1 - x0, height: 1).fill()
        }
        for x in xs { NSRect(x: x - 0.5, y: frag.minY, width: 1, height: frag.height).fill() }
    }
}

final class EditorTextView: NSTextView {
    var markdownMode = true
    var openLink: ((String) -> Void)?

    /// Links show a pointing hand when a click would open them.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard markdownMode, Prefs.clickOpensLinks, let storage = textStorage, let lm = layoutManager, let tc = textContainer, storage.length > 0 else { return }
        let o = textContainerOrigin
        let caretLine = (string as NSString).lineRange(for: selectedRange())
        storage.enumerateAttribute(.uphoraLink, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
            guard v != nil, NSIntersectionRange(r, caretLine).length == 0, !(r.location >= caretLine.location && r.location <= NSMaxRange(caretLine)) else { return }
            let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: o.x, dy: o.y), cursor: .pointingHand)
            }
        }
    }

    private func index(at event: NSEvent) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let o = textContainerOrigin
        let pt = NSPoint(x: p.x - o.x, y: p.y - o.y)
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: pt, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        guard idx < storage.length else { return nil }
        let g = lm.glyphIndexForCharacter(at: idx)
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: -2, dy: -2).contains(pt) else { return nil }
        return idx
    }

    /// Clicking a rendered table puts the caret in the Markdown source of the clicked cell.
    private func clickTable(_ event: NSEvent) -> Bool {
        guard let storage = textStorage, let lm = layoutManager as? EditorLayoutManager, storage.length > 0 else { return false }
        let pt = convert(event.locationInWindow, from: nil)
        var found: (TableRef, NSRange, NSRect)?
        storage.enumerateAttribute(.uphoraTableBlock, in: NSRange(location: 0, length: storage.length), options: []) { v, r, stop in
            if let ref = v as? TableRef, let rect = lm.tableRect(ref, range: r, origin: textContainerOrigin), rect.contains(pt) {
                found = (ref, r, rect)
                stop.pointee = true
            }
        }
        guard let (ref, r, rect) = found else { return false }
        let L = ref.layout
        var col = 0
        var x = rect.minX
        for (i, w) in L.colWidths.enumerated() { if pt.x >= x { col = i }; x += w }
        var row = 0
        var y = rect.minY
        for (i, h) in L.rowHeights.enumerated() { if pt.y >= y { row = i }; y += h }
        if event.clickCount == 1, event.modifierFlags.contains(.command) || Prefs.clickOpensLinks {
            let colX = rect.minX + L.colWidths.prefix(col).reduce(0, +)
            let rowY = rect.minY + L.rowHeights.prefix(row).reduce(0, +)
            let local = NSPoint(x: pt.x - colX - TableLayout.hPad, y: pt.y - rowY - TableLayout.vPad)
            let st = NSTextStorage(attributedString: ref.cells[row][col])
            let lm2 = NSLayoutManager()
            let tc2 = NSTextContainer(size: NSSize(width: L.colWidths[col] - 2 * TableLayout.hPad, height: 1e6))
            tc2.lineFragmentPadding = 0
            lm2.addTextContainer(tc2)
            st.addLayoutManager(lm2)
            if st.length > 0, local.x >= 0, local.y >= 0 {
                var f: CGFloat = 0
                let i = lm2.characterIndex(for: local, in: tc2, fractionOfDistanceBetweenInsertionPoints: &f)
                if i < st.length,
                   lm2.boundingRect(forGlyphRange: NSRange(location: lm2.glyphIndexForCharacter(at: i), length: 1), in: tc2).insetBy(dx: -1, dy: -1).contains(local),
                   let link = st.attribute(.uphoraLink, at: i, effectiveRange: nil) as? String {
                    openLink?(link)
                    return true
                }
            }
        }
        let text = string as NSString
        guard let block = Table.find(in: text).first(where: { $0.lines[0].location == r.location }) else { return false }
        let lr = block.lines[row == 0 ? 0 : row + 1]
        let line = text.substring(with: lr) as NSString
        let cells = Table.splitCells(line)
        let cell = cells[min(col, cells.count - 1)]
        var lead = 0
        while lead < cell.length, [32, 9].contains(line.character(at: cell.location + lead)) { lead += 1 }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: lr.location + cell.location + min(lead, cell.length), length: 0))
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if markdownMode, clickTable(event) { return }
        if markdownMode, event.clickCount == 1, let idx = index(at: event), let storage = textStorage {
            if let s = storage.attribute(.uphoraLink, at: idx, effectiveRange: nil) as? String {
                let lineHasCaret = (string as NSString).lineRange(for: selectedRange()).contains(idx)
                if event.modifierFlags.contains(.command) || (Prefs.clickOpensLinks && !lineHasCaret) {
                    openLink?(s)
                    return
                }
            }
            if toggleTask(at: idx) { return }
        }
        super.mouseDown(with: event)
    }

    private func toggleTask(at idx: Int) -> Bool {
        let s = string as NSString
        let lr = s.lineRange(for: NSRange(location: idx, length: 0))
        let line = s.substring(with: lr)
        guard let re = try? NSRegularExpression(pattern: "^([ \\t]*[-*+][ \\t]+)\\[([ xX])\\]"),
              let m = re.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return false }
        let box = lr.location + m.range(at: 1).length
        guard idx >= box, idx < box + 3 else { return false }
        let state = (line as NSString).substring(with: m.range(at: 2))
        let r = NSRange(location: box + 1, length: 1)
        let new = state == " " ? "x" : " "
        if shouldChangeText(in: r, replacementString: new) {
            textStorage?.replaceCharacters(in: r, with: new)
            didChangeText()
        }
        return true
    }

    override func paste(_ sender: Any?) {
        let sel = selectedRange()
        if markdownMode, sel.length > 0,
           let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.contains(" "), !s.contains("\n"),
           let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") {
            let new = "[\((string as NSString).substring(with: sel))](\(s))"
            if shouldChangeText(in: sel, replacementString: new) {
                textStorage?.replaceCharacters(in: sel, with: new)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + (new as NSString).length, length: 0))
            }
            return
        }
        super.paste(sender)
    }
}
