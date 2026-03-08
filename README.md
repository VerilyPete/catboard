# Catboard

A macOS CLI utility to copy file contents to the system clipboard, with Finder integration and OCR support.

Like `cat` but for your clipboard - hence **catboard**.

## Features

- Copy text file contents to clipboard from the command line
- Extract text from PDF documents (including multi-page PDFs)
- OCR images (PNG, JPG, TIFF, etc.) using macOS Vision framework
- OCR scanned PDFs automatically when no embedded text is found
- Multi-page PDF OCR with page separators
- **Directory tree snapshots** for LLM context (`catboard tree`) with `.gitignore` support
- macOS Finder right-click integration via Finder Sync Extension or Quick Action (files and directories)
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

### Directory Contents for LLM Context (`catboard tree`)

Generate a markdown snapshot of a directory's contents — ideal for pasting into ChatGPT, Claude, or other LLMs as context.

```bash
# Output to stdout
catboard tree src/

# Copy to clipboard instead
catboard tree --copy src/

# Multiple directories
catboard tree --copy src/ lib/ tests/

# Include hidden files
catboard tree --hidden .

# Larger size limits
catboard tree --max-file-size 1MB --max-total-size 10MB src/

# Ignore .gitignore rules
catboard tree --no-gitignore src/

# Verbose mode (show stats on stderr)
catboard tree -v src/
```

#### Tree Options

```
ARGS:
  <DIRS>...                    Directories to walk

OPTIONS:
      --copy                   Copy to clipboard instead of stdout
      --hidden                 Include hidden files
      --max-file-size <SIZE>   Maximum size per file [default: 256KB]
      --max-total-size <SIZE>  Maximum total output size [default: 1MB]
      --no-gitignore           Don't respect .gitignore rules
  -v, --verbose                Show stats (files included/skipped/total)
  -q, --quiet                  Suppress non-error output
```

Size values accept `B`, `KB`, `MB`, `GB` suffixes (case-insensitive). Plain numbers are treated as bytes.

#### Output Format

The output is structured markdown containing:

1. **Directory tree** — ASCII tree showing the file/folder structure
2. **File contents** — Each file in a fenced code block with language detection (50+ languages)
3. **Skip notes** — Entries for binary files, oversized files, symlinks, and permission errors

Files are skipped when they exceed `--max-file-size`, and output is truncated when it exceeds `--max-total-size`. `.gitignore` rules (including nested `.gitignore` files and negation patterns) are respected by default. Common noise directories (`node_modules`, `.git`, `__pycache__`, `target`, etc.) are always excluded.

#### Finder Integration

Right-click any directory in Finder to copy its tree output to the clipboard. The Finder extension uses the same defaults as the CLI (256KB per file, 1MB total, respects `.gitignore`).

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

- **catboard** - Rust CLI tool for copying file contents to clipboard, with `catboard tree` for directory-to-markdown output
- **catboard-ocr** - Swift OCR helper using macOS Vision framework (required by the CLI for image and scanned PDF support)
- **CatboardFinder** - Native Swift Finder Sync Extension with built-in file reading, PDF extraction, OCR, and directory tree generation. Right-click any file or directory. Includes container app, extension, and shared CatboardCore framework
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
│   ├── main.rs                   # CLI entry point (clap subcommands)
│   ├── lib.rs                    # Library exports
│   ├── clipboard.rs              # Clipboard operations (arboard)
│   ├── file.rs                   # File reading and PDF extraction
│   ├── tree.rs                   # Directory tree generation for LLM context
│   ├── ocr.rs                    # OCR integration (shells out to catboard-ocr)
│   └── error.rs                  # Error types (thiserror)
├── swift/
│   ├── catboard-ocr/             # Standalone OCR CLI (Vision framework)
│   └── CatboardFinder/           # Finder Sync Extension
│       ├── CatboardCore/         # Shared framework (FileReader, Clipboard, OCR, PDF, TreeGenerator)
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
