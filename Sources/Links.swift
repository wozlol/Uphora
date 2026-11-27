import AppKit

private func githubSlug(_ raw: String) -> String {
    var t = raw.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
    t = t.replacingOccurrences(of: "[*`~]", with: "", options: .regularExpression)
    t = t.trimmingCharacters(in: .whitespaces).lowercased()
    let keep = t.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " || $0 == "-" || $0 == "_" }
    return String(String.UnicodeScalarView(keep)).replacingOccurrences(of: " ", with: "-")
}

extension EditorController {
    /// Opens a link: a web address in the browser, `#heading` as a jump inside this document, a file next to this document in Uphora or its own app.
    func openLink(_ link: String) {
        if link.hasPrefix("#") {
            goToAnchor(String(link.dropFirst()))
            return
        }
        if let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }
        var path = link
        if path.hasPrefix("file://"), let u = URL(string: path) { path = u.path }
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        path = path.removingPercentEncoding ?? path
        let base = mdDocument?.fileURL?.deletingLastPathComponent()
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if path.hasPrefix("~") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else if let base = base {
            url = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        } else {
            NSSound.beep()
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        if ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Jumps to the heading GitHub would give this anchor.
    func goToAnchor(_ anchor: String) {
        let target = (anchor.removingPercentEncoding ?? anchor).lowercased()
        let t = text
        var counts: [String: Int] = [:]
        var inFence = false
        var loc = 0
        while loc < t.length {
            let lr = t.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(lr)
            let line = t.substring(with: lr).trimmingCharacters(in: .newlines)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle() }
            if inFence { continue }
            guard let m = try? NSRegularExpression(pattern: "^#{1,6}[ \\t]+(.*?)[ \\t#]*$").firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { continue }
            let base = githubSlug((line as NSString).substring(with: m.range(at: 1)))
            let n = counts[base, default: 0]
            counts[base] = n + 1
            let slug = n == 0 ? base : "\(base)-\(n)"
            if slug == target {
                textView.setSelectedRange(NSRange(location: lr.location, length: 0))
                textView.scrollRangeToVisible(NSRange(location: lr.location, length: 0))
                textView.showFindIndicator(for: NSRange(location: lr.location, length: max(1, line.utf16.count)))
                return
            }
        }
        NSSound.beep()
    }
}
