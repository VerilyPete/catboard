# CI/CD Plan for Catboard

## Overview

Set up GitHub Actions for continuous integration and automated builds across all supported platforms (macOS, Linux, Windows).

## CI Pipeline Goals

1. **Run tests on every push/PR**
2. **Build release binaries for all platforms**
3. **Create releases with downloadable binaries**

---

## Phase 1: Basic CI (Tests)

### File: `.github/workflows/ci.yml`

**Triggers:**
- Push to `main` branch
- All pull requests

**Jobs:**

#### 1. Test Job (Matrix Strategy)
Run on: `ubuntu-latest`, `macos-latest`, `windows-latest`

Steps:
1. Checkout code
2. Install Rust toolchain (stable)
3. Cache cargo dependencies
4. Run `cargo fmt --check` (formatting)
5. Run `cargo clippy` (linting)
6. Run `cargo test` (unit + integration tests)
7. Run `cargo test -- --ignored` on macOS only (clipboard tests)

**Linux-specific:**
- Install `xvfb` for headless clipboard tests (optional)

---

## Phase 2: Build Artifacts

### File: `.github/workflows/build.yml`

**Triggers:**
- Push to `main`
- Tags matching `v*` (releases)

**Build Matrix:**

| OS | Target | Binary Name |
|----|--------|-------------|
| ubuntu-latest | x86_64-unknown-linux-gnu | catboard |
| ubuntu-latest | x86_64-unknown-linux-musl | catboard (static) |
| macos-latest | x86_64-apple-darwin | catboard |
| macos-latest | aarch64-apple-darwin | catboard (Apple Silicon) |
| windows-latest | x86_64-pc-windows-msvc | catboard.exe |

Steps:
1. Checkout code
2. Install Rust with target
3. Build release: `cargo build --release --target <target>`
4. Upload artifact

---

## Phase 3: Release Automation

### File: `.github/workflows/release.yml`

**Triggers:**
- Tags matching `v*.*.*`

**Steps:**
1. Build all platform binaries (reuse build workflow)
2. Create GitHub Release
3. Upload binaries as release assets
4. Generate changelog from commits

**Asset naming convention:**
- `catboard-v{version}-linux-x86_64.tar.gz`
- `catboard-v{version}-linux-x86_64-musl.tar.gz`
- `catboard-v{version}-macos-x86_64.tar.gz`
- `catboard-v{version}-macos-aarch64.tar.gz`
- `catboard-v{version}-windows-x86_64.zip`

---

## Implementation Checklist

### Files to Create:
- [ ] `.github/workflows/ci.yml` - Test pipeline
- [ ] `.github/workflows/release.yml` - Build and release pipeline

### CI Features:
- [ ] Rust formatting check (`cargo fmt`)
- [ ] Clippy linting (`cargo clippy`)
- [ ] Unit tests on all platforms
- [ ] Integration tests on all platforms
- [ ] Clipboard tests on macOS (with display)
- [ ] Dependency caching for faster builds

### Release Features:
- [ ] Cross-platform release builds
- [ ] Automatic GitHub release on tag push
- [ ] Compressed archives with binaries
- [ ] macOS Quick Action workflow included in release

---

## Example Workflow Structure

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo fmt --check
      - run: cargo clippy -- -D warnings
      - run: cargo test
```

---

## Optional Enhancements

1. **Code coverage** with `cargo-tarpaulin` or `cargo-llvm-cov`
2. **Security audit** with `cargo-audit`
3. **Dependency updates** with Dependabot
4. **Benchmarks** for performance regression testing
5. **MSRV testing** (Minimum Supported Rust Version)
