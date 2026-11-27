import AppKit

/// Applies live markdown styling to a text storage. The text itself is never changed.
/// Marker characters (#, **, `, and so on) are hidden except on the line the caret is on.
final class MarkdownStyler {
    let storage: NSTextStorage
    let text: NSString
    let size: CGFloat
    let selection: NSRange
    let baseURL: URL?
    let maxImageWidth: CGFloat
    let maxTableChars: Int
    let inlineOnly: Bool
    var codeRanges: [NSRange] = []
    var protectedRanges: [NSRange] = []

    init(storage: NSTextStorage, size: CGFloat, selection: NSRange, baseURL: URL? = nil, maxImageWidth: CGFloat = 600,
         maxTableChars: Int = Int.max, inlineOnly: Bool = false) {
        self.storage = storage
        self.text = storage.string as NSString
        self.size = size
        self.selection = selection
        self.baseURL = baseURL
        self.maxImageWidth = maxImageWidth
        self.maxTableChars = maxTableChars
        self.inlineOnly = inlineOnly
    }

    static func paragraph(size: CGFloat) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = size * 0.3
        p.paragraphSpacing = size * 0.25
        return p
    }

    private var mono: NSFont { NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular) }
    private var codeBackground: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(0.14) }

    private func marker(_ r: NSRange, active: Bool) {
        guard r.length > 0 else { return }
        if active {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
        } else {
            storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.1)], range: r)
        }
    }

    func addTrait(_ trait: NSFontTraitMask, _ r: NSRange) {
        var edits: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: r) { value, range, _ in
            if let f = value as? NSFont {
                edits.append((range, NSFontManager.shared.convert(f, toHaveTrait: trait)))
            }
        }
        for (range, font) in edits { storage.addAttribute(.font, value: font, range: range) }
    }

    private func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private lazy var reHeading = regex("^(#{1,6})[ \\t]+")
    private lazy var reQuote = regex("^[ \\t]*>[ \\t]?")
    private lazy var reRule = regex("^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$")
    private lazy var reList = regex("^([ \\t]*)([-*+]|\\d+[.)])[ \\t]+(\\[[ xX]\\][ \\t]+)?")
    private lazy var reImageLine = regex("^[ \\t]*!\\[([^\\]\\n]*)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"]*\")?\\)[ \\t]*$")
    private lazy var reCode = regex("`([^`\\n]+)`")
    private lazy var reEscape = regex("\\\\([\\\\`*_{}\\[\\]()#+\\-.!|~>])")
    private lazy var reBold = regex("(?<!\\\\)(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private lazy var reItalic = regex("(?<![*_\\w\\\\])(\\*|_)(?=[^\\s*_])(.+?)(?<=[^\\s*_])\\1(?![*_\\w])")
    private lazy var reStrike = regex("(~~)(?=\\S)(.+?)(?<=\\S)~~")
    private lazy var reLink = regex("(!?)\\[([^\\]\\n]+)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"]*\")?\\)")
    private lazy var reAutolink = regex("<(https?://[^>\\s]+)>")
    private lazy var reBareURL = regex("(?<![\\w(\\[<\"'/=])https?://[^\\s<>\\]\\)\"']*[^\\s<>\\]\\)\"'.,;:!?]")

    func run() {
        let full = NSRange(location: 0, length: text.length)
        let base = NSFont.systemFont(ofSize: size)
        storage.beginEditing()
        storage.setAttributes([
            .font: base,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownStyler.paragraph(size: size),
        ], range: full)

        if inlineOnly {
            var l = 0
            while l < text.length {
                let lr = text.lineRange(for: NSRange(location: l, length: 0))
                l = NSMaxRange(lr)
                var len = lr.length
                while len > 0, [10, 13].contains(text.character(at: lr.location + len - 1)) { len -= 1 }
                inlineStyle(line: NSRange(location: lr.location, length: len), active: false)
            }
            storage.endEditing()
            return
        }

        // mode 0: drawn as a table, 1: aligned grid while editing, 2: plain source while editing (too wide for a grid)
        var tableLine: [Int: (mode: Int, role: Int, ref: TableRef?)] = [:]
        for b in Table.find(in: text) {
            let r = b.range
            let active = selection.location <= NSMaxRange(r) && NSMaxRange(selection) >= r.location
            if !active {
                let ref = makeTableRef(b)
                for (i, lr) in b.lines.enumerated() { tableLine[lr.location] = (0, i, i == 0 ? ref : nil) }
            } else {
                let mode = (b.lines.map { $0.length }.max() ?? 0) <= maxTableChars ? 1 : 2
                for (i, lr) in b.lines.enumerated() { tableLine[lr.location] = (mode, i == 0 ? 0 : (i == 1 ? 1 : 2), nil) }
            }
        }

        var loc = 0
        var inFence = false
        while loc < text.length {
            let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(lineRange)
            var len = lineRange.length
            while len > 0, [10, 13].contains(text.character(at: lineRange.location + len - 1)) { len -= 1 }
            let line = NSRange(location: lineRange.location, length: len)
            let active = selection.location <= NSMaxRange(line) && NSMaxRange(selection) >= line.location

            let lineText = text.substring(with: line)
            if lineText.hasPrefix("```") || lineText.hasPrefix("~~~") {
                inFence.toggle()
                storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: line)
                let ticks = lineText.prefix { $0 == "`" || $0 == "~" }.count
                marker(NSRange(location: line.location, length: ticks), active: active)
                if line.length > ticks {
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                         range: NSRange(location: line.location + ticks, length: line.length - ticks))
                }
                continue
            }
            if inFence {
                storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: line)
                continue
            }
            if line.length == 0 { continue }

            if let t = tableLine[line.location] {
                switch t.mode {
                case 0: hideTableLine(line, ref: t.ref)
                case 1: styleTableRow(line: line, role: t.role)
                default: styleTableSource(line: line, role: t.role)
                }
                continue
            }
            if blockStyle(line: line, active: active) { continue }
            inlineStyle(line: line, active: active)
        }
        storage.endEditing()
    }

    private func makeTableRef(_ b: TableBlock) -> TableRef {
        let model = Table.parse(b, text: text)
        let cells = model.rows.enumerated().map { ri, row in
            row.enumerated().map { ci, t in cellString(t, header: ri == 0, align: model.aligns[ci]) }
        }
        return TableRef(cells: cells, aligns: model.aligns, available: maxImageWidth)
    }

    private func cellString(_ raw: String, header: Bool, align: Align) -> NSAttributedString {
        let t = raw.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let st = NSTextStorage(string: t)
        let sty = MarkdownStyler(storage: st, size: size, selection: NSRange(location: Int.max / 2, length: 0), inlineOnly: true)
        sty.run()
        let full = NSRange(location: 0, length: st.length)
        if header { sty.addTrait(.boldFontMask, full) }
        let p = NSMutableParagraphStyle()
        p.lineSpacing = size * 0.12
        p.lineBreakMode = .byWordWrapping
        switch align {
        case .center: p.alignment = .center
        case .right: p.alignment = .right
        default: p.alignment = .left
        }
        st.addAttribute(.paragraphStyle, value: p, range: full)
        return st
    }

    /// The Markdown lines of a table that is drawn as a grid are squeezed to almost nothing. The header line carries the grid's height.
    private func hideTableLine(_ line: NSRange, ref: TableRef?) {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 0
        p.paragraphSpacing = ref.map { $0.layout.height + 10 } ?? 0
        p.minimumLineHeight = 1
        p.maximumLineHeight = 1
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: p], range: line)
        if let ref = ref { storage.addAttribute(.uphoraTableBlock, value: ref, range: line) }
    }

    private func styleTableSource(line: NSRange, role: Int) {
        let font = NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: role == 0 ? .bold : .regular)
        storage.addAttributes([.font: font, .paragraphStyle: MarkdownStyler.paragraph(size: size)], range: line)
        if role == 1 {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: line)
            return
        }
        inlineStyle(line: line, active: true)
        for pipe in Table.pipes(in: text, line: line) {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: pipe, length: 1))
        }
    }

    private func styleTableRow(line: NSRange, role: Int) {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byClipping
        if role == 1 {
            p.lineSpacing = 0
            p.paragraphSpacing = 0
            p.maximumLineHeight = 4
            p.minimumLineHeight = 4
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: 1),
                .foregroundColor: NSColor.clear,
                .paragraphStyle: p,
                .uphoraTable: line.location * 4 + 1,
            ], range: line)
            return
        }
        p.paragraphSpacingBefore = size * 0.3
        p.lineSpacing = size * 0.3
        p.paragraphSpacing = 0
        let font = NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: role == 0 ? .bold : .regular)
        storage.addAttributes([.font: font, .paragraphStyle: p, .uphoraTable: line.location * 4 + role], range: line)
        inlineStyle(line: line, active: true)
        for pipe in Table.pipes(in: text, line: line) {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: pipe, length: 1))
        }
    }

    /// Returns true when the line needs no inline styling.
    private func blockStyle(line: NSRange, active: Bool) -> Bool {
        let s = storage.string
        if let m = reImageLine.firstMatch(in: s, range: line) {
            let url = text.substring(with: m.range(at: 2))
            if let img = ImageCache.shared.image(url, base: baseURL), img.size.width > 0 {
                let w = min(img.size.width, maxImageWidth)
                let h = min(img.size.height * w / img.size.width, 700)
                let w2 = h < img.size.height * w / img.size.width ? img.size.width * h / img.size.height : w
                let p = MarkdownStyler.paragraph(size: size)
                p.paragraphSpacing = h + 14
                storage.addAttributes([
                    .paragraphStyle: p,
                    .uphoraImage: ImageRef(url: url, base: baseURL, size: NSSize(width: w2, height: h)),
                ], range: line)
                marker(line, active: active)
                return true
            }
        }
        if let m = reHeading.firstMatch(in: s, range: line) {
            let level = m.range(at: 1).length
            let scale: [CGFloat] = [1.9, 1.6, 1.35, 1.15, 1.05, 1.0]
            let f = NSFont.systemFont(ofSize: size * scale[level - 1], weight: .bold)
            storage.addAttribute(.font, value: f, range: line)
            marker(m.range, active: active)
            return false
        }
        if reRule.firstMatch(in: s, range: line) != nil {
            if active {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: line)
            } else {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .strikethroughStyle: NSUnderlineStyle.thick.rawValue,
                    .strikethroughColor: NSColor.separatorColor,
                ], range: line)
            }
            return true
        }
        if let m = reQuote.firstMatch(in: s, range: line) {
            let p = MarkdownStyler.paragraph(size: size)
            p.firstLineHeadIndent = 14
            p.headIndent = 14
            storage.addAttributes([.paragraphStyle: p, .foregroundColor: NSColor.secondaryLabelColor], range: line)
            marker(m.range, active: active)
            return false
        }
        if let m = reList.firstMatch(in: s, range: line) {
            let lead = CGFloat(m.range(at: 1).length) * size * 0.5
            let p = MarkdownStyler.paragraph(size: size)
            p.firstLineHeadIndent = lead
            p.headIndent = lead + size * 1.5
            storage.addAttribute(.paragraphStyle, value: p, range: line)
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 2))
            let box = m.range(at: 3)
            if box.location != NSNotFound {
                storage.addAttributes([.foregroundColor: NSColor.controlAccentColor,
                                       .font: NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular)], range: box)
                let done = text.substring(with: box).lowercased().contains("x")
                let rest = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(line) - NSMaxRange(m.range))
                if done, rest.length > 0 {
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            }
        }
        return false
    }

    private func overlaps(_ r: NSRange, _ list: [NSRange]) -> Bool {
        list.contains { NSIntersectionRange($0, r).length > 0 }
    }

    private func inlineStyle(line: NSRange, active: Bool) {
        codeRanges = []
        protectedRanges = []
        let s = storage.string

        for m in reCode.matches(in: s, range: line) {
            codeRanges.append(m.range)
            storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: m.range)
            marker(NSRange(location: m.range.location, length: 1), active: active)
            marker(NSRange(location: NSMaxRange(m.range) - 1, length: 1), active: active)
        }

        for m in reEscape.matches(in: s, range: line) where !overlaps(m.range, codeRanges) {
            marker(NSRange(location: m.range.location, length: 1), active: active)
        }

        func pairs(_ re: NSRegularExpression, trait: NSFontTraitMask?, strike: Bool = false) {
            for m in re.matches(in: s, range: line) where !overlaps(m.range, codeRanges) {
                let mk = m.range(at: 1).length
                let inner = m.range(at: 2)
                if let t = trait { addTrait(t, inner) }
                if strike {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
                }
                marker(NSRange(location: m.range.location, length: mk), active: active)
                marker(NSRange(location: NSMaxRange(m.range) - mk, length: mk), active: active)
            }
        }
        pairs(reBold, trait: .boldFontMask)
        pairs(reItalic, trait: .italicFontMask)
        pairs(reStrike, trait: nil, strike: true)

        func linkStyle(_ r: NSRange, url: String) {
            storage.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .uphoraLink: url,
            ], range: r)
        }

        for m in reLink.matches(in: s, range: line) where !overlaps(m.range, codeRanges) {
            protectedRanges.append(m.range)
            let label = m.range(at: 2)
            linkStyle(label, url: text.substring(with: m.range(at: 3)))
            marker(NSRange(location: m.range.location, length: label.location - m.range.location), active: active)
            let tail = NSMaxRange(label)
            marker(NSRange(location: tail, length: NSMaxRange(m.range) - tail), active: active)
        }
        for m in reAutolink.matches(in: s, range: line) where !overlaps(m.range, codeRanges + protectedRanges) {
            protectedRanges.append(m.range)
            linkStyle(m.range(at: 1), url: text.substring(with: m.range(at: 1)))
            marker(NSRange(location: m.range.location, length: 1), active: active)
            marker(NSRange(location: NSMaxRange(m.range) - 1, length: 1), active: active)
        }
        for m in reBareURL.matches(in: s, range: line) where !overlaps(m.range, codeRanges + protectedRanges) {
            linkStyle(m.range, url: text.substring(with: m.range))
        }
    }
}
