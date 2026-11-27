# Uphora

A small native Mac editor for Markdown and plain text files. Open source, no dependencies, Swift and AppKit only.

| Feature | How |
|---|---|
| Live Markdown styling | Headings, bold, italic, strikethrough, inline code, code blocks, links, quotes, lists, rules. Marker characters hide until the caret is on that line |
| Toolbar and Format menu | Style popup (Normal, Heading 1-6), Bold, Italic, Strikethrough, Inline Code, Link, Bulleted, Numbered and Task lists, Quote, Code Block, Rule |
| Shortcuts | Bold Cmd-B, Italic Cmd-I, Strikethrough Shift-Cmd-X, Code Cmd-E, Link Cmd-K, Normal Opt-Cmd-0, Heading 1-6 Opt-Cmd-1 to 6, Bullets Shift-Cmd-8, Numbers Shift-Cmd-7, Tasks Shift-Cmd-9, Quote Opt-Cmd-Q, Code Block Opt-Cmd-C, Rule Opt-Cmd-- |
| Lists and quotes | Enter continues the item, numbers count up. Enter on an empty item ends the list or quote. Backspace on an empty item clears it. Tab and Shift-Tab indent and outdent list items |
| Word wrap | View > Word Wrap, Opt-Cmd-W |
| Text size | View > Bigger Text, Smaller Text, Actual Size (Cmd + - 0) |
| Files | .md and .markdown get styling and the toolbar, .txt and everything else stay plain |

Build: `./build.sh`, output is `build/Uphora.app`. Needs Xcode command line tools. Icon source is `icon/make_icon.swift`.
