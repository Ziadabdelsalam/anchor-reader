# Anchor

A macOS reader for people who find long documents hard to stay with: text blurs together, attention slides off after a few minutes, small type feels like work.

Anchor shows one small bite of text at a time with everything else faded, keeps the type big and roomy, runs short focus sprints with real breaks, and asks a one-sentence recall question at the end of each section. Every feature is based on published research; see [RESEARCH.md](RESEARCH.md).

Opens Markdown, plain text, PDF, Word (.docx/.doc), RTF, HTML and ODT.

Tables (Markdown, HTML, and Word/RTF/HTML documents) are drawn as real tables that always fit the window: cells wrap, columns keep their alignment and formatting, long tables arrive a few rows at a time with the header repeated, and tables too wide to read side by side become one card per row. If any bite is taller than the window, Space scrolls through the rest of it before moving on.

## Install

You need macOS 15 or newer and Apple's developer tools (Swift 6.2+, from Xcode 26 or its Command Line Tools). In Terminal:

```bash
git clone https://github.com/Ziadabdelsalam/anchor-reader.git
cd anchor-reader
./build.sh --install
open ~/Applications/Anchor.app
```

**New to Terminal or developer tools?** Follow the step-by-step [installation guide](INSTALL.md). It also covers updating, uninstalling, making Anchor your default Markdown app, and troubleshooting.

## Using it

Drag a file onto the drop zone on the start screen (or anywhere in the window, even while reading), click the drop zone to choose a file, or press ⌘O. You can also drop files on the Dock icon or use Finder's "Open With".

| Key | Does |
|---|---|
| Space / → / ↓ / J | Next bite |
| ⇧ Space / ← / ↑ / K | Previous bite |
| D | "I zoned out": step back one bite |
| R | Read aloud with word highlighting |
| O | Map of the document (outline) |
| N | Recall notes |
| Z | Hide all controls (Esc to bring them back) |
| F | Full screen |
| T | Pause/resume the sprint timer |
| B | Take a break now |
| ⌘= / ⌘− / ⌘0 | Bigger / smaller / default text (or pinch) |

On first launch, the **Reading comfort setup** helps you pick a text size that feels effortless (minimum 18 pt, default 24 pt) and runs a short timed test to find the font you read fastest in.

Your place in every document, your recall notes and your reading pace are saved in `~/Library/Application Support/Anchor/library.json`.

## Project layout

```
Sources/Anchor/
  App/        app entry, menus, app state, debug tools
  Model/      reader session logic, sprint timer, text-to-speech, settings, saved progress
  Parsing/    Markdown / PDF / rich-text importers and the chunker
  Views/      SwiftUI screens
  Content/    guided tour text, font-test passages, research citations
Support/      Info.plist and app icon
Tools/        icon generator
```

## Developer tools

- `Anchor --dump <file> [sentence|small|medium|paragraph]` prints how a document is parsed and chunked.
- `ANCHOR_SCRIPT=<file>` runs a UI script (open, start, next, key, snap…, see `App/DebugScript.swift`) and can save window snapshots without screen-recording permission. `ANCHOR_MUTE=1` silences read-aloud during tests.
