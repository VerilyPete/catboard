# Catboard

A macOS CLI utility to copy file contents to the system clipboard, with Finder integration and OCR support.

Like `cat` but for your clipboard - hence **catboard**.

## Features

- Copy text file contents to clipboard from the command line
- Extract text from PDF documents (including multi-page PDFs)
- OCR images (PNG, JPG, TIFF, etc.) using macOS Vision framework
- OCR scanned PDFs automatically when no embedded text is found
- Multi-page PDF OCR with page separators
- macOS Finder right-click integration via Finder Sync Extension or Quick Action
- Binary file detection to prevent clipboard corruption
- Support for stdin input
- Multiple file concatenation

## Installation

### Homebrew (recommended)

```bash
# CLI tools
brew install VerilyPete/tap/catboard

# Finder extension (toolbar button + right-click menu)
brew install --cask VerilyPete/tap/catboard-finder
```

After installing the CLI, enable the Quick Action:

```bash
cp -r "$(brew --prefix)/share/catboard/Copy to Clipboard.workflow" ~/Library/Services/
```

### macOS Installer (.pkg)

Download `catboard-*-installer.pkg` from the [releases page](https://github.com/VerilyPete/catboard/releases) and double-click to install. The installer automatically sets up:
- CLI tools in `/usr/local/bin`
- CatboardFinder app in `/Applications` (Finder extension)
- Finder Quick Action for right-click integration

### Manual Installation

Download the tarball from the [releases page](https://github.com/VerilyPete/catboard/releases):

```bash
# Extract the archive
tar xzf catboard-*.tar.gz
cd catboard-*/

# Install binaries
sudo cp catboard catboard-ocr /usr/local/bin/

# Install Finder Quick Action
cp -r "Copy to Clipboard.workflow" ~/Library/Services/
```

### From Source

```bash
# Clone the repository
git clone https://github.com/VerilyPete/catboard.git
cd catboard

# Build the main binary
cargo build --release
sudo cp target/release/catboard /usr/local/bin/

# Build the OCR helper (required for image/scanned PDF support)
cd swift/catboard-ocr
swift build -c release
sudo cp .build/release/catboard-ocr /usr/local/bin/

# Install Finder Quick Action
cp -r "macos/Copy to Clipboard.workflow" ~/Library/Services/
```

### Finder Integration

There are two options for Finder integration:

**Finder Sync Extension (recommended):** Install via `brew install --cask VerilyPete/tap/catboard-finder` or from the [releases page](https://github.com/VerilyPete/catboard/releases). Open CatboardFinder from `/Applications`, then enable the extension in System Settings → Privacy & Security → Extensions → Finder. Right-click any file to see "Copy to Clipboard" in the context menu, or add the Catboard button to the Finder toolbar (right-click toolbar → Customize Toolbar). This option uses native Swift with built-in OCR and PDF extraction — no separate CLI tools needed.

**Quick Action (legacy):** After installing the Rust CLI, right-click any file in Finder and look for "Copy to Clipboard" under Quick Actions or Services. This shells out to the `catboard` CLI.

## Usage

### Basic Usage

```bash
# Copy a text file to clipboard
catboard file.txt

# Extract text from a PDF
catboard document.pdf

# OCR an image (requires catboard-ocr)
catboard screenshot.png

# Copy multiple files (contents concatenated with newlines)
catboard file1.txt file2.txt file3.txt

# Read from stdin
echo "Hello, clipboard!" | catboard -

# With a pipe
cat README.md | catboard -
```

### Options

```
-v, --verbose    Verbose output (shows file reading progress)
-q, --quiet      Quiet mode (suppress all output except errors)
-h, --help       Print help information
-V, --version    Print version
```

### Examples

```bash
# Copy with verbose output
catboard -v important.txt
# Output: Reading file: important.txt
# Output: Copied 1234 bytes from important.txt to clipboard

# Copy silently
catboard -q data.json

# Copy code to share
catboard src/main.rs

# Extract text from a scanned document
catboard scanned-receipt.pdf

# OCR a screenshot
catboard ~/Desktop/Screenshot.png
```

## Supported File Types

| File Type | Method |
|-----------|--------|
| Text files (.txt, .md, .rs, etc.) | Direct read with binary detection |
| PDF documents | Text extraction, OCR fallback for scanned PDFs |
| Multi-page PDFs | All pages extracted with `--- Page N ---` separators |
| Images (.png, .jpg, .tiff, etc.) | OCR via macOS Vision framework |

## Components

- **catboard** - Rust CLI tool for copying file contents to clipboard
- **catboard-ocr** - Swift OCR helper using macOS Vision framework (required by the CLI for image and scanned PDF support)
- **CatboardFinder** - Native Swift Finder Sync Extension with built-in file reading, PDF extraction, and OCR. Includes container app, extension, and shared CatboardCore framework
- **Copy to Clipboard.workflow** - Legacy Finder Quick Action (shells out to the `catboard` CLI)

## Error Handling

Catboard provides clear error messages for common issues:

- **File not found**: The specified file doesn't exist
- **Permission denied**: Cannot read the file
- **Binary file**: File contains null bytes (likely binary data)
- **Extraction error**: Failed to extract text from PDF or image
- **Clipboard error**: Cannot access the system clipboard

## Development

### Building

```bash
# Build main binary
cargo build

# Build OCR helper
cd swift/catboard-ocr
swift build
```

### Testing

```bash
# Run all tests
cargo test

# Run tests including clipboard tests (requires display server)
cargo test -- --ignored
```

### Project Structure

```
catboard/
├── src/                          # Rust CLI
│   ├── main.rs                   # CLI entry point (clap)
│   ├── lib.rs                    # Library exports
│   ├── clipboard.rs              # Clipboard operations (arboard)
│   ├── file.rs                   # File reading and PDF extraction
│   ├── ocr.rs                    # OCR integration (shells out to catboard-ocr)
│   └── error.rs                  # Error types (thiserror)
├── swift/
│   ├── catboard-ocr/             # Standalone OCR CLI (Vision framework)
│   └── CatboardFinder/           # Finder Sync Extension
│       ├── CatboardCore/         # Shared framework (FileReader, Clipboard, OCR, PDF)
│       ├── CatboardFinder/       # Container app (AppDelegate, icon assets)
│       ├── FinderExtension/      # Finder Sync Extension (context menu, clipboard)
│       ├── CatboardCoreTests/    # Unit tests
│       └── project.yml           # XcodeGen project definition
├── tests/
│   └── integration.rs            # Rust integration tests
└── macos/
    └── Copy to Clipboard.workflow/  # Legacy Finder Quick Action
```

## Requirements

- macOS (tested on macOS 13+)
- For OCR: catboard-ocr must be installed in the same directory as catboard or in PATH

## Similar Tools

For simple text file copying, you can use built-in macOS tools:

```bash
# Using pbcopy (no PDF/image support, no binary detection)
pbcopy < file.txt
```

Catboard adds PDF text extraction, OCR for images and scanned documents, and Finder integration.

## License

MIT License - see [LICENSE](LICENSE) for details.
