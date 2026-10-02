# Installing Anchor

Anchor is built from source on your own Mac. It takes about five minutes, most of it waiting for Apple's developer tools to download the first time.

## What you need

- A Mac running **macOS 15 Sequoia or newer** (Apple silicon or Intel)
- **Swift 6.2 or newer**, which comes with **Xcode 26** or the matching **Command Line Tools**. You don't need to open Xcode; the build runs from Terminal.

## Step 1: Install Apple's developer tools

If you already have Xcode 26 or newer, skip to step 2.

Open **Terminal** (press ⌘ Space, type "Terminal", press Return) and run:

```bash
xcode-select --install
```

A window pops up; click **Install** and wait for it to finish. Then check the Swift version:

```bash
swift --version
```

It should say **Swift version 6.2** or higher. If it shows an older version, update Xcode or the Command Line Tools from **System Settings → General → Software Update**.

## Step 2: Download the code

```bash
git clone https://github.com/Ziadabdelsalam/anchor-reader.git
cd anchor-reader
```

No git? Click the green **Code** button on the GitHub page, choose **Download ZIP**, unzip it, and `cd` into the unzipped folder in Terminal.

## Step 3: Build and install

```bash
./build.sh --install
```

This compiles Anchor and copies **Anchor.app** into the **Applications** folder in your home folder (`~/Applications`). The first build takes a minute or two; later builds are faster.

To only build it without installing, run `./build.sh` and you'll find the app at `build/Anchor.app`.

## Step 4: Open it

```bash
open ~/Applications/Anchor.app
```

Or press ⌘ Space, type **Anchor** and press Return. To keep it handy, right-click its icon in the Dock and choose **Options → Keep in Dock**.

On first launch Anchor walks you through a two-minute **reading comfort setup**: pick a text size that feels effortless, then a short timed test finds the font you read fastest in. After that, drag a Markdown, PDF, Word, RTF, HTML or text file onto the window to start reading, or take the built-in 3-minute tour.

## Optional extras

**Open Markdown files in Anchor by default.** In Finder, select any `.md` file, press ⌘ I (Get Info), choose **Anchor** under **Open with**, and click **Change All…**.

**Nicer read-aloud voices.** Open **System Settings → Accessibility → Spoken Content → System Voice → Manage Voices…** and download an **Enhanced** or **Premium** voice. Pick it in Anchor under **Settings → Voice**.

**An extra-clear font.** The free [Atkinson Hyperlegible](https://www.brailleinstitute.org/freefont/) font from the Braille Institute was designed for low-vision readers. Install it (double-click the font files, then click Install), and Anchor will offer it in the font menu and include it in the font test.

## Updating

From the `anchor-reader` folder:

```bash
git pull
./build.sh --install
```

Your settings, reading positions and recall notes are kept.

## Uninstalling

```bash
rm -rf ~/Applications/Anchor.app
rm -rf ~/Library/Application\ Support/Anchor
defaults delete local.anchor.reader
```

The second line deletes your saved reading positions and recall notes; the third resets your settings.

## Troubleshooting

**`swift: command not found` or `xcrun: error: invalid active developer path`**
The developer tools aren't installed yet. Run `xcode-select --install` (step 1).

**`package '…' is using Swift tools version 6.2.0 but the installed version is …`**
Your Swift is too old. Update Xcode or the Command Line Tools to version 26 or newer.

**`permission denied: ./build.sh`**
Run `chmod +x build.sh` once, then try again.

**"Anchor can't be opened because Apple cannot check it for malicious software"**
This only happens if you copy a built Anchor.app to a different Mac (apps you build yourself aren't quarantined). On that Mac, right-click the app, choose **Open**, then click **Open** again. You only need to do this once.

**A PDF shows no text**
It's probably a scanned PDF (pictures of pages). Run it through text recognition first; Preview and Adobe Acrobat can both do this. Then open the recognized copy in Anchor.
