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
