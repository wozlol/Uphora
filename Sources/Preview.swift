import AppKit
import JavaScriptCore
import WebKit

/// Finds bundled files, both inside the app and when running from the source folder.
enum Res {
    static func url(_ name: String) -> URL? {
        if let u = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension) { return u }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/\(name)")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func text(_ name: String) -> String {
        guard let u = url(name), let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }
}

struct PreviewTheme: Equatable {
    let name: String
    /// File name of a custom CSS file, nil for the built-in themes.
    let custom: String?
}

enum Themes {
    static let builtIn = ["GitHub (follows macOS)", "GitHub Light", "GitHub Dark"]

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Uphora/Themes", isDirectory: true)
    }

    /// Built-in themes first, then every .css file in the Themes folder.
    static func all() -> [PreviewTheme] {
        var list = builtIn.map { PreviewTheme(name: $0, custom: nil) }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for f in files.sorted() where f.lowercased().hasSuffix(".css") {
            list.append(PreviewTheme(name: (f as NSString).deletingPathExtension, custom: f))
        }
        return list
    }

    static var current: String {
        get { UserDefaults.standard.string(forKey: "previewTheme") ?? builtIn[0] }
        set { UserDefaults.standard.set(newValue, forKey: "previewTheme") }
    }

    static func css(for name: String) -> (css: String, background: String) {
        let hlLight = Res.text("hl-light.css")
        let hlDark = Res.text("hl-dark.css")
        switch name {
        case "GitHub Light":
            return (Res.text("github-light.css") + hlLight, "#ffffff")
        case "GitHub Dark":
            return (Res.text("github-dark.css") + hlDark, "#0d1117")
        default:
            let auto = Res.text("github-auto.css") + hlLight + "@media (prefers-color-scheme: dark){" + hlDark + "}"
            var extra = ""
            if let file = all().first(where: { $0.name == name })?.custom,
               let s = try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8) {
                extra = s
            }
            return (auto + extra, "")
        }
    }
}

/// Turns Markdown into GitHub-flavored HTML with marked and highlight.js, run in-process.
final class MarkdownHTML {
    static let shared = MarkdownHTML()
    private let ctx = JSContext()!

    private init() {
        ctx.exceptionHandler = { _, e in NSLog("Uphora JS: %@", e?.toString() ?? "") }
        ctx.evaluateScript(Res.text("marked.min.js"))
        ctx.evaluateScript(Res.text("highlight.min.js"))
        ctx.evaluateScript("""
        var __slugs = {};
        function __slug(raw) {
          var s = String(raw).replace(/<[^>]*>/g, '').toLowerCase().trim().replace(/[^\\p{L}\\p{N}\\s_-]/gu, '').replace(/\\s/g, '-');
          if (__slugs[s] === undefined) { __slugs[s] = 0; return s; }
          __slugs[s] += 1;
          return s + '-' + __slugs[s];
        }
        function __esc(t) { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
        marked.use({
          gfm: true,
          renderer: {
            heading: function (text, level, raw) {
              var id = __slug(raw);
              return '<h' + level + ' id="' + id + '">' + text + '</h' + level + '>\\n';
            },
            code: function (code, info) {
              var lang = (info || '').match(/^\\S*/)[0];
              var html;
              try {
                html = (lang && hljs.getLanguage(lang)) ? hljs.highlight(code, { language: lang }).value : __esc(code);
              } catch (e) { html = __esc(code); }
              return '<pre><code class="hljs' + (lang ? ' language-' + lang : '') + '">' + html + '</code></pre>\\n';
            }
          }
        });
        function __render(md) { __slugs = {}; return marked.parse(md); }
        """)
    }

    func html(_ markdown: String) -> String {
        ctx.objectForKeyedSubscript("__render").call(withArguments: [markdown])?.toString() ?? ""
    }
}

/// The GitHub-style rendered view of a document.
final class PreviewView: NSView, WKNavigationDelegate {
    let web: WKWebView
    private var tempFile: URL

    override init(frame: NSRect) {
        let cfg = WKWebViewConfiguration()
        // Scripts in the document are never run. Only Uphora's own rendering happens, outside the page.
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: frame, configuration: cfg)
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Uphora", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempFile = dir.appendingPathComponent("preview-\(UUID().uuidString).html")
        super.init(frame: frame)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        addSubview(web)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { try? FileManager.default.removeItem(at: tempFile) }

    func show(markdown: String, baseURL: URL?) {
        let body = MarkdownHTML.shared.html(markdown)
        let t = Themes.css(for: Themes.current)
        let bg = t.background.isEmpty
            ? "body{background:#ffffff}@media (prefers-color-scheme: dark){body{background:#0d1117}}"
            : "body{background:\(t.background)}"
        let base = baseURL.map { "<base href=\"\($0.absoluteString.hasSuffix("/") ? $0.absoluteString : $0.absoluteString + "/")\">" } ?? ""
        let page = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">\(base)
        <style>\(t.css)</style>
        <style>\(bg) body{margin:0} .markdown-body{box-sizing:border-box;min-width:200px;max-width:980px;margin:0 auto;padding:45px}
        table th:not([align]){text-align:left} table td,table th{vertical-align:top}
        @media (max-width: 767px){.markdown-body{padding:15px}}</style></head>
        <body class="markdown-body">\(body)</body></html>
        """
        try? page.write(to: tempFile, atomically: true, encoding: .utf8)
        web.loadFileURL(tempFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL, url.path == tempFile.path, url.fragment != nil {
            decisionHandler(.allow)
        } else {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
