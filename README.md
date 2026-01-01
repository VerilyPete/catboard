# Catboard

A macOS CLI utility to copy file contents to the system clipboard, with Finder integration and OCR support.

Like `cat` but for your clipboard - hence **catboard**.

## Features

- Copy text file contents to clipboard from the command line
- Extract text from PDF documents
- OCR images (PNG, JPG, TIFF, etc.) using macOS Vision framework
- OCR scanned PDFs automatically when no embedded text is found
- macOS Finder right-click integration via Quick Action
- Binary file detection to prevent clipboard corruption
- Support for stdin input
- Multiple file concatenation

## Installation

### Homebrew (recommended)

```bash
brew install VerilyPete/tap/catboard
```

After installation, enable Finder integration:

```bash
cp -r "$(brew --prefix)/share/catboard/Copy to Clipboard.workflow" ~/Library/Services/
```

### macOS Installer (.pkg)

Download `catboard-*-installer.pkg` from the [releases page](https://github.com/VerilyPete/catboard/releases) and double-click to install. The installer automatically sets up:
- CLI tools in `/usr/local/bin`
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

After installation, right-click any file in Finder and look for "Copy to Clipboard" under Quick Actions or Services.

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
| Images (.png, .jpg, .tiff, etc.) | OCR via macOS Vision framework |

## Components

- **catboard** - Main CLI tool for copying file contents to clipboard
- **catboard-ocr** - OCR helper using macOS Vision framework (required for image and scanned PDF support)
- **Copy to Clipboard.workflow** - Finder Quick Action for right-click integration

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
├── src/
│   ├── main.rs       # CLI entry point
│   ├── lib.rs        # Library exports
│   ├── clipboard.rs  # Clipboard operations
│   ├── file.rs       # File reading and PDF extraction
│   ├── ocr.rs        # OCR integration
│   └── error.rs      # Error types
├── swift/
│   └── catboard-ocr/ # macOS Vision OCR helper
├── tests/
│   └── integration.rs
└── macos/
    └── Copy to Clipboard.workflow/
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
