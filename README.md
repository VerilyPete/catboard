# Catboard

A cross-platform CLI utility to copy file contents to the system clipboard, with macOS Finder integration.

Like `cat` but for your clipboard - hence **catboard**.

## Features

- Copy text file contents to clipboard from the command line
- macOS Finder right-click integration via Quick Action
- Cross-platform support (macOS, Linux, Windows)
- Binary file detection to prevent clipboard corruption
- Support for stdin input
- Multiple file concatenation

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/VerilyPete/catboard.git
cd catboard

# Build and install
cargo build --release
sudo cp target/release/catboard /usr/local/bin/
```

### macOS Finder Integration

To add a "Copy to Clipboard" option in Finder's right-click menu:

```bash
# Copy the Quick Action to your Services folder
cp -r "macos/Copy to Clipboard.workflow" ~/Library/Services/
```

After installation, right-click any file in Finder and look for "Copy to Clipboard" under Quick Actions or Services.

## Usage

### Basic Usage

```bash
# Copy a single file to clipboard
catboard file.txt

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

# Copy multiple config files
catboard ~/.bashrc ~/.zshrc
```

## Platform Support

| Platform | Status | Clipboard Backend |
|----------|--------|-------------------|
| macOS    | Full support | Native (arboard) |
| Linux (X11) | Supported | X11 clipboard |
| Linux (Wayland) | Supported | Wayland clipboard |
| Windows  | Supported | Win32 API |

### Linux Requirements

On Linux, you may need to install clipboard-related packages:

```bash
# Ubuntu/Debian (X11)
sudo apt install xclip

# Ubuntu/Debian (Wayland)
sudo apt install wl-clipboard

# Fedora
sudo dnf install xclip wl-clipboard
```

## Error Handling

Catboard provides clear error messages for common issues:

- **File not found**: The specified file doesn't exist
- **Permission denied**: Cannot read the file
- **Binary file**: File contains null bytes (likely binary data)
- **Clipboard error**: Cannot access the system clipboard

## Development

### Building

```bash
cargo build
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
│   ├── file.rs       # File reading
│   └── error.rs      # Error types
├── tests/
│   └── integration.rs
└── macos/
    └── Copy to Clipboard.workflow/
```

## Similar Tools

On macOS, you can achieve similar functionality with built-in tools:

```bash
# Using pbcopy (macOS only, no binary detection)
pbcopy < file.txt

# Using xclip (Linux X11)
xclip -selection clipboard < file.txt

# Using xsel (Linux X11)
xsel --clipboard < file.txt
```

Catboard provides a unified cross-platform interface with additional features like binary file detection and Finder integration.

## License

MIT License - see [LICENSE](LICENSE) for details.
