# Catboard - Cross-Platform Clipboard Utility

## Overview

**Catboard** is a Rust-based CLI utility that copies file contents to the system clipboard. It supports both command-line usage and macOS Finder integration via a Quick Action.

## Goals

1. **CLI Tool**: Copy file contents to clipboard from terminal
2. **Finder Integration**: Right-click context menu option in macOS Finder
3. **Multi-Platform**: Support macOS, Linux, and Windows
4. **TDD Approach**: Test-driven development throughout

## Architecture

```
catboard/
├── Cargo.toml
├── src/
│   ├── main.rs           # CLI entry point
│   ├── lib.rs            # Library exports
│   ├── clipboard.rs      # Platform-specific clipboard operations
│   ├── file.rs           # File reading operations
│   └── error.rs          # Custom error types
├── tests/
│   └── integration.rs    # Integration tests
└── macos/
    └── Copy to Clipboard.workflow/  # Finder Quick Action
```

## Platform Support

| Platform | Clipboard Backend | Status |
|----------|------------------|--------|
| macOS    | `pbcopy`/`pbpaste` or `arboard` crate | Primary |
| Linux    | X11/Wayland via `arboard` | Secondary |
| Windows  | Win32 API via `arboard` | Secondary |

## Dependencies

- **clap**: Command-line argument parsing
- **arboard**: Cross-platform clipboard access
- **thiserror**: Error handling

## Implementation Plan

### Phase 1: Project Setup
- Initialize Cargo project
- Add dependencies
- Set up test infrastructure

### Phase 2: Core Library (TDD)
1. **Error Module** (`src/error.rs`)
   - Define custom error types for file and clipboard operations
   - Tests: Error creation and display

2. **File Module** (`src/file.rs`)
   - Read file contents as String
   - Handle binary file detection
   - Tests: Read valid file, handle missing file, handle permission errors

3. **Clipboard Module** (`src/clipboard.rs`)
   - Abstract clipboard operations behind a trait
   - Platform-specific implementations
   - Tests: Set/get clipboard content (with mock for CI)

### Phase 3: CLI Interface (TDD)
- Parse command-line arguments
- Support multiple files
- Verbose/quiet modes
- Tests: Argument parsing, help output

### Phase 4: Finder Integration
- Create Automator Quick Action workflow
- Shell script that invokes catboard binary
- Installation instructions

## CLI Usage

```bash
# Copy single file contents to clipboard
catboard file.txt

# Copy multiple files (concatenated)
catboard file1.txt file2.txt

# Read from stdin
echo "hello" | catboard -

# Verbose mode
catboard -v file.txt

# Show version
catboard --version
```

## TDD Test Strategy

### Unit Tests
- Error type creation and formatting
- File reading (valid, missing, binary detection)
- Argument parsing

### Integration Tests
- Full CLI invocation with test files
- Clipboard operations (platform-specific, may skip in CI)

### Test Doubles
- Mock clipboard trait for unit testing
- Temporary files for file operations

## Finder Quick Action

The Quick Action will be an Automator workflow that:
1. Receives selected files as input
2. Runs the catboard CLI on each file
3. Shows a notification on success/failure

```bash
# Automator shell script content
/usr/local/bin/catboard "$@"
```

## Success Criteria

- [ ] `catboard file.txt` copies contents to clipboard
- [ ] Works on macOS, Linux, Windows
- [ ] Right-click in Finder shows "Copy to Clipboard" option
- [ ] All tests pass
- [ ] Error messages are helpful

## Implementation Order

1. `src/error.rs` - Error types
2. `src/file.rs` - File reading (write tests first!)
3. `src/clipboard.rs` - Clipboard operations (write tests first!)
4. `src/lib.rs` - Library exports
5. `src/main.rs` - CLI
6. Integration tests
7. Quick Action workflow
8. README with installation instructions
