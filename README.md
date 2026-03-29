# pbhtml

A lightweight macOS CLI tool for analyzing, extracting, and repackaging clipboard content—specifically designed to handle **HTML** and Apple's **WebArchive** format (used by Outlook, Safari, and Mail).

## 🚀 What it does
`pbhtml` solves the common problem of editing email signatures or complex web snippets that contain embedded images. 

- **Analyze**: See exactly what data types (HTML, WebArchive, Plain Text) and sizes are currently in your clipboard.
- **Extract (Paste)**: Decodes a WebArchive into a clean HTML file and separate asset files (PNG, JPG, etc.). It automatically replaces internal `cid:` or `file://` references with local file paths.
- **Repackage (Copy)**: Takes your edited HTML and associated assets (e.g., `sig-1.png`) and bundles them back into a valid binary WebArchive on your clipboard, ready to be pasted back into Outlook or Mail with all images intact.

## 🛠 Building the tool
The tool is written in Swift and has **zero external dependencies**. It uses native macOS frameworks (`AppKit`, `Foundation`).

**Minimum Requirements:**
- macOS 10.15+
- Swift Compiler (comes with Xcode or Command Line Tools)

**Compile command:**
```bash
swiftc pbhtml.swift -o pbhtml
```

## 📖 Usage Examples

### 1. Analyze the clipboard
Check if your clipboard contains a WebArchive or just plain HTML:
```bash
./pbhtml
```

### 2. Extract an Outlook Signature
Copy a signature from Outlook or a website, then extract it for editing:
```bash
./pbhtml paste my_signature
```
This creates:
- `my_signature.html` (The main HTML)
- `my_signature-1.png`, `my_signature-2.jpg`, etc. (The embedded assets)

### 3. Repackage and Copy back to Clipboard
After editing `my_signature.html`, bundle it back with its assets:
```bash
./pbhtml copy my_signature
```
Now you can simply press `Cmd+V` in Outlook’s signature settings, and your updated signature (including images) will be pasted correctly.

### 4. Simple Stream Mode
To just output the raw HTML or text from the clipboard to `stdout`:
```bash
./pbhtml paste -- > content.html
```

## 💡 Pro Tip: Editing Outlook Signatures
Outlook often adds massive amounts of redundant CSS to signatures. Using `pbhtml`, you can:
1. `paste` the signature to a file.
2. Manually clean up the HTML/CSS in your favorite editor.
3. `copy` it back to the clipboard to "re-inject" the clean version into Outlook.
