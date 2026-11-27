import AppKit

extension Notification.Name {
    static let prefsChanged = Notification.Name("UphoraPrefsChanged")
}

enum Prefs {
    static var wrap: Bool {
        get { UserDefaults.standard.object(forKey: "wrap") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "wrap")
            NotificationCenter.default.post(name: .prefsChanged, object: nil)
        }
    }
    static var size: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: "size")
            return v == 0 ? 17 : CGFloat(v)
        }
        set {
            UserDefaults.standard.set(Double(min(max(newValue, 9), 96)), forKey: "size")
            NotificationCenter.default.post(name: .prefsChanged, object: nil)
        }
    }
}

@objc(MDDocument)
final class MDDocument: NSDocument {
    var text = ""
    weak var controller: EditorController?

    override class var autosavesInPlace: Bool { true }

    var isMarkdown: Bool {
        guard let ext = fileURL?.pathExtension.lowercased() else { return true }
        return ["md", "markdown", "mdown", "mkd"].contains(ext)
    }

    override func makeWindowControllers() {
        let c = EditorController(document: self)
        controller = c
        addWindowController(c)
        c.refresh()
    }

    override func data(ofType typeName: String) throws -> Data {
        let s = controller?.textView.string ?? text
        return Data(s.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = s
        controller?.load(s)
    }
}

final class EditorController: NSWindowController, NSTextViewDelegate {
    let textView: NSTextView
    let scroll: NSScrollView
    var lastActive = NSRange(location: 0, length: 0)
    var stylePopup: NSPopUpButton?

    var mdDocument: MDDocument? { document as? MDDocument }

    init(document: MDDocument) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 800, height: 1e7))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), textContainer: container)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: 1e7, height: 1e7)
        tv.autoresizingMask = [.width]
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        textView = tv

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.drawsBackground = true
        sv.backgroundColor = .textBackgroundColor
        scroll = sv

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.contentView = sv
        w.minSize = NSSize(width: 360, height: 240)
        super.init(window: w)
        w.toolbar = makeToolbar()
        w.toolbarStyle = .unified
        shouldCascadeWindows = true
        tv.delegate = self

        sv.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSView.frameDidChangeNotification, object: sv.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: .prefsChanged, object: nil)
        load(document.text)
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(_ s: String) {
        textView.string = s
        textView.undoManager?.removeAllActions()
        refresh()
    }

    @objc func refresh() {
        layoutText()
        restyle()
    }

    private func layoutText() {
        let size = Prefs.size
        let w = scroll.contentSize.width
        let container = textView.textContainer!
        if Prefs.wrap {
            scroll.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            let column = size * 46
            let inset = max(32, (w - column) / 2)
            textView.textContainerInset = NSSize(width: inset, height: 28)
            container.widthTracksTextView = true
            textView.setFrameSize(NSSize(width: w, height: textView.frame.height))
            container.containerSize = NSSize(width: max(50, w - 2 * inset), height: 1e7)
        } else {
            scroll.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.textContainerInset = NSSize(width: 32, height: 28)
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: 1e7, height: 1e7)
        }
    }

    func restyle() {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let size = Prefs.size
        let sel = textView.selectedRange()
        if mdDocument?.isMarkdown ?? true {
            MarkdownStyler(storage: storage, size: size, selection: sel).run()
        } else {
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: MarkdownStyler.paragraph(size: size),
            ], range: NSRange(location: 0, length: storage.length))
        }
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownStyler.paragraph(size: size),
        ]
        lastActive = (storage.string as NSString).lineRange(for: sel)
        updateStyleUI()
    }

    func textDidChange(_ notification: Notification) { restyle() }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard mdDocument?.isMarkdown ?? true else { return }
        let sel = textView.selectedRange()
        let active = (textView.string as NSString).lineRange(for: sel)
        if active != lastActive { restyle() }
    }

    func undoManager(for view: NSTextView) -> UndoManager? { document?.undoManager }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) { buildMenu() }

    @objc func toggleWrap(_ sender: Any?) { Prefs.wrap.toggle() }
    @objc func bigger(_ sender: Any?) { Prefs.size += 1 }
    @objc func smaller(_ sender: Any?) { Prefs.size -= 1 }
    @objc func actualSize(_ sender: Any?) { Prefs.size = 17 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleWrap(_:)) { item.state = Prefs.wrap ? .on : .off }
        return true
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                     _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        i.tag = tag
        menu.addItem(i)
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let m = NSMenu(title: title)
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        main.addItem(i)
        return m
    }

    private func buildMenu() {
        let main = NSMenu()

        let app = submenu(main, "Uphora")
        add(app, "About Uphora", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, "Hide Uphora", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Uphora", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(main, "File")
        add(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Save", #selector(NSDocument.save(_:)), "s")
        add(file, "Save As…", #selector(NSDocument.saveAs(_:)), "S", [.command, .shift])
        add(file, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))

        let edit = submenu(main, "Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "Z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = Selector(("performTextFinderAction:"))
        add(edit, "Find…", find, "f", tag: 1)
        add(edit, "Find Next", find, "g", tag: 2)
        add(edit, "Find Previous", find, "G", [.command, .shift], tag: 3)

        let view = submenu(main, "View")
        add(view, "Word Wrap", #selector(toggleWrap(_:)), "w", [.command, .option], target: self)
        view.addItem(.separator())
        add(view, "Bigger Text", #selector(bigger(_:)), "+", target: self)
        add(view, "Smaller Text", #selector(smaller(_:)), "-", target: self)
        add(view, "Actual Size", #selector(actualSize(_:)), "0", target: self)

        let fmt = submenu(main, "Format")
        add(fmt, "Bold", #selector(EditorController.fmtBold(_:)), "b")
        add(fmt, "Italic", #selector(EditorController.fmtItalic(_:)), "i")
        add(fmt, "Strikethrough", #selector(EditorController.fmtStrike(_:)), "x", [.command, .shift])
        add(fmt, "Inline Code", #selector(EditorController.fmtCode(_:)), "e")
        add(fmt, "Link", #selector(EditorController.fmtLink(_:)), "k")
        fmt.addItem(.separator())
        add(fmt, "Normal Text", #selector(EditorController.fmtHeading(_:)), "0", [.command, .option], tag: 0)
        for n in 1...6 {
            add(fmt, "Heading \(n)", #selector(EditorController.fmtHeading(_:)), "\(n)", [.command, .option], tag: n)
        }
        fmt.addItem(.separator())
        add(fmt, "Bulleted List", #selector(EditorController.fmtBullet(_:)), "8", [.command, .shift])
        add(fmt, "Numbered List", #selector(EditorController.fmtNumber(_:)), "7", [.command, .shift])
        add(fmt, "Task List", #selector(EditorController.fmtTask(_:)), "9", [.command, .shift])
        add(fmt, "Quote", #selector(EditorController.fmtQuote(_:)), "q", [.command, .option])
        add(fmt, "Code Block", #selector(EditorController.fmtCodeBlock(_:)), "c", [.command, .option])
        add(fmt, "Horizontal Rule", #selector(EditorController.fmtRule(_:)), "-", [.command, .option])

        let window = submenu(main, "Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}
