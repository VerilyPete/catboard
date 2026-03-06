# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Catboard is a macOS CLI utility that copies file contents to the system clipboard. It supports text files, PDF text extraction, and OCR for images/scanned PDFs via a Swift helper. It includes Finder integration through both a Quick Action workflow and a Finder Sync Extension.

## Architecture

Two codebases work together:

- **Rust CLI (`src/`)** — Main `catboard` binary. Modules: `main.rs` (CLI via clap), `lib.rs` (public API), `file.rs` (file reading + PDF extraction), `clipboard.rs` (clipboard ops via arboard), `ocr.rs` (OCR integration by shelling out to `catboard-ocr`), `error.rs` (error types via thiserror).
- **Swift (`swift/`)** — Two sub-projects:
  - `catboard-ocr/` — Standalone CLI using macOS Vision framework for OCR. Built with Swift Package Manager.
  - `CatboardFinder/` — Finder Sync Extension app with three targets: `CatboardFinder` (container app), `FinderExtension` (Finder Sync Extension), `CatboardCore` (shared framework). Uses XcodeGen (`project.yml`) to generate the Xcode project.

The Rust binary invokes `catboard-ocr` as a subprocess when it encounters image files or scanned PDFs.

## Build Commands

```bash
# Rust CLI
cargo build                    # Debug build
cargo build --release          # Release build

# Swift OCR helper
cd swift/catboard-ocr && swift build
cd swift/catboard-ocr && swift build -c release

# Swift Finder Extension (requires xcodegen)
cd swift/CatboardFinder && xcodegen generate
xcodebuild build -scheme CatboardFinder -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Test Commands

```bash
# Run all Rust tests
cargo test

# Run a single test
cargo test test_name

# Run tests including clipboard tests (requires display server, skipped in CI)
cargo test -- --ignored

# Run doc tests
cargo test --doc

# Run Swift Finder Extension tests
cd swift/CatboardFinder && xcodebuild test -scheme CatboardFinder -configuration Debug \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Lint & Format

```bash
cargo fmt --all -- --check     # Check formatting
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on push to main and PRs:
- `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, security audit via `rustsec/audit-check`, and Swift Finder Extension build+test.
- Clippy and tests run on `macos-latest`. Formatting and security audit run on `ubuntu-latest`.
- Clipboard tests are `#[ignore]`d because they require a display server unavailable in CI.

## Key Dependencies

- **arboard** — Cross-platform clipboard access
- **clap** (derive) — CLI argument parsing
- **pdf_oxide** — PDF text extraction
- **thiserror** — Error type derivation
- **assert_cmd + predicates** — Integration test helpers

## Notable Details

- MSRV: Rust 1.70.0, macOS deployment target: 15.0
- `deny.toml` configures `cargo-deny` for license and security auditing
- The Finder Extension uses `codeSign: false` in `project.yml` to preserve entitlements during embedding
- Integration tests live in `tests/integration.rs`
- `PLAN.md` contains the multi-page PDF OCR implementation plan
