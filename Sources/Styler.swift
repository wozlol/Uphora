import AppKit

/// Applies live markdown styling to a text storage. The text itself is never changed.
/// Marker characters (#, **, `, and so on) are hidden except on the line the caret is on.
final class MarkdownStyler {
    let storage: NSTextStorage
    let text: NSString
    let size: CGFloat
    let selection: NSRange
    var codeRanges: [NSRange] = []

    init(storage: NSTextStorage, size: CGFloat, selection: NSRange) {
        self.storage = storage
        self.text = storage.string as NSString
        self.size = size
        self.selection = selection
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

    private func addTrait(_ trait: NSFontTraitMask, _ r: NSRange) {
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
    private lazy var reCode = regex("`([^`\\n]+)`")
    private lazy var reBold = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private lazy var reItalic = regex("(?<![*_\\w])(\\*|_)(?=[^\\s*_])(.+?)(?<=[^\\s*_])\\1(?![*_\\w])")
    private lazy var reStrike = regex("(~~)(?=\\S)(.+?)(?<=\\S)~~")
    private lazy var reLink = regex("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")

    func run() {
        let full = NSRange(location: 0, length: text.length)
        let base = NSFont.systemFont(ofSize: size)
        storage.beginEditing()
        storage.setAttributes([
            .font: base,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownStyler.paragraph(size: size),
        ], range: full)

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
                marker(line, active: active)
                continue
            }
            if inFence {
                storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: line)
                continue
            }
            if line.length == 0 { continue }

            blockStyle(line: line, active: active)
            inlineStyle(line: line, active: active)
        }
        storage.endEditing()
    }

    private func blockStyle(line: NSRange, active: Bool) {
        if let m = reHeading.firstMatch(in: storage.string, range: line) {
            let level = m.range(at: 1).length
            let scale: [CGFloat] = [1.9, 1.6, 1.35, 1.15, 1.05, 1.0]
            let f = NSFont.systemFont(ofSize: size * scale[level - 1], weight: .bold)
            storage.addAttribute(.font, value: f, range: line)
            marker(m.range, active: active)
            return
        }
        if reRule.firstMatch(in: storage.string, range: line) != nil {
            if active {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: line)
            } else {
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .strikethroughStyle: NSUnderlineStyle.thick.rawValue,
                    .strikethroughColor: NSColor.separatorColor,
                ], range: line)
            }
            return
        }
        if let m = reQuote.firstMatch(in: storage.string, range: line) {
            let p = MarkdownStyler.paragraph(size: size)
            p.firstLineHeadIndent = 14
            p.headIndent = 14
            storage.addAttributes([.paragraphStyle: p, .foregroundColor: NSColor.secondaryLabelColor], range: line)
            marker(m.range, active: active)
            return
        }
        if let m = reList.firstMatch(in: storage.string, range: line) {
            let lead = CGFloat(m.range(at: 1).length) * size * 0.5
            let p = MarkdownStyler.paragraph(size: size)
            p.firstLineHeadIndent = lead
            p.headIndent = lead + size * 1.5
            storage.addAttribute(.paragraphStyle, value: p, range: line)
            let markRange = NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length)
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: markRange)
            if m.range(at: 3).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 3))
            }
        }
    }

    private func overlapsCode(_ r: NSRange) -> Bool {
        codeRanges.contains { NSIntersectionRange($0, r).length > 0 }
    }

    private func inlineStyle(line: NSRange, active: Bool) {
        codeRanges = []
        let s = storage.string

        for m in reCode.matches(in: s, range: line) {
            codeRanges.append(m.range)
            storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: m.range)
            marker(NSRange(location: m.range.location, length: 1), active: active)
            marker(NSRange(location: NSMaxRange(m.range) - 1, length: 1), active: active)
        }

        func pairs(_ re: NSRegularExpression, trait: NSFontTraitMask?, strike: Bool = false) {
            for m in re.matches(in: s, range: line) where !overlapsCode(m.range) {
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

        for m in reLink.matches(in: s, range: line) where !overlapsCode(m.range) {
            let label = m.range(at: 1)
            storage.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: label)
            marker(NSRange(location: m.range.location, length: 1), active: active)
            let tailStart = NSMaxRange(label)
            marker(NSRange(location: tailStart, length: NSMaxRange(m.range) - tailStart), active: active)
        }
    }
}
