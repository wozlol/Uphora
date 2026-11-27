# Uphora

A small native Mac editor for Markdown and plain text files. Open source, no dependencies, Swift and AppKit only.

| Feature | How |
|---|---|
| Live Markdown styling | Headings, bold, italic, strikethrough, inline code, code blocks, links, quotes, lists, rules. Marker characters hide until the caret is on that line |
| Toolbar and Format menu | Style popup (Normal, Heading 1-6), Bold, Italic, Strikethrough, Inline Code, Link, Bulleted, Numbered and Task lists, Quote, Code Block, Rule |
| Shortcuts | Bold Cmd-B, Italic Cmd-I, Strikethrough Shift-Cmd-X, Code Cmd-E, Link Cmd-K, Normal Opt-Cmd-0, Heading 1-6 Opt-Cmd-1 to 6, Bullets Shift-Cmd-8, Numbers Shift-Cmd-7, Tasks Shift-Cmd-9, Quote Opt-Cmd-Q, Code Block Opt-Cmd-C, Rule Opt-Cmd-- |
| Lists and quotes | Enter continues the item, numbers count up. Enter on an empty item ends the list or quote. Backspace on an empty item clears it. Tab and Shift-Tab indent and outdent list items |
| Tables | Insert Table button or Opt-Cmd-T. Columns stay aligned as you type. Tab and Shift-Tab move between cells, Tab in the last cell adds a row, Enter moves down, Enter on an empty last row leaves the table. Table Tools button or Format > Table: add or delete rows and columns, align a column left, center or right, delete the table. Opening a file tidies its tables so the grid lines up. While the caret is outside a table it is drawn like a GitHub table with wrapping cells. Click it to edit its Markdown. A table too wide for the window is shown as plain wrapped Markdown while you edit |
| Images | Format > Insert Image, or type `![alt](path)` on its own line. The picture shows under the line. Local paths (relative to the file) and web addresses work |
| Checkboxes and links | Click a `[ ]` to check it. Click a link to open it (View > Click Opens Links turns this off, Command-click always works). Web addresses open in the browser, `#heading` links jump to that heading, and links to other files open them. Web addresses are links by themselves. Paste a web address over selected text to make a link |
| GitHub View | Eye button in the toolbar, or View > GitHub View (Opt-Cmd-P) switches the window to a read-only page that looks like GitHub, with real wrapping tables and code colors. Switch back to keep editing. View > GitHub View Theme picks GitHub (follows macOS), GitHub Light or GitHub Dark, and the choice is remembered |
| Your own themes | A theme is a plain CSS file. Put it in `~/Library/Application Support/Uphora/Themes` (View > GitHub View Theme > Open Themes Folder). It shows up in the theme menu and is added on top of the GitHub styling, so it only needs the rules you want to change. The page is a `.markdown-body` element |
| Word wrap | View > Word Wrap, Opt-Cmd-W |
| Text size | View > Bigger Text, Smaller Text, Actual Size (Cmd + - 0) |
| Files | .md and .markdown get styling and the toolbar, .txt and everything else stay plain |

## Install

This build is not notarized by Apple, so macOS shows a warning the first time. The warning is about the missing Apple signature, not about a problem found in the app. The source is in this repo.

1. Download `Uphora-1.0.zip` and double-click it. Drag `Uphora.app` into Applications.
2. Double-click Uphora. macOS says it cannot verify the app. Click Done (or OK).
3. Open System Settings > Privacy & Security and scroll to the Security section. Click Open Anyway next to the Uphora message, then enter your password and click Open.
4. After that it opens normally.

On macOS 14 and older you can instead right-click `Uphora.app`, choose Open, then choose Open again in the dialog.

If the message says the app is damaged, open Terminal and run `xattr -dr com.apple.quarantine /Applications/Uphora.app`, then open it again. This only removes the download flag from Uphora.

Needs an Apple silicon Mac (M1 or newer) and macOS 12 or newer. To build it yourself instead, run `./build.sh`.

Build: `./build.sh`, output is `build/Uphora.app`. Needs Xcode command line tools. Icon source is `icon/make_icon.swift`.

Third-party files in `Resources`: marked 12.0.2 (MIT), highlight.js 11.9.0 (BSD-3-Clause) and its GitHub themes, github-markdown-css 5.5.1 (MIT).
