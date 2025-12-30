# CI/CD Plan for Catboard

## Overview

Set up GitHub Actions for continuous integration and automated builds across supported platforms (macOS Apple Silicon, Linux, Windows).

## CI Pipeline Goals

1. **Run tests on every push/PR**
2. **Build release binaries for all platforms**
3. **Create releases with downloadable binaries**
4. **Security auditing for dependencies**

---

## Build Matrix

| OS | Target | Notes |
|----|--------|-------|
| ubuntu-latest | x86_64-unknown-linux-gnu | Standard Linux |
| ubuntu-latest | x86_64-unknown-linux-musl | Static binary |
| macos-latest | aarch64-apple-darwin | Apple Silicon only |
| windows-latest | x86_64-pc-windows-msvc | Windows |

**Note:** Intel macOS (x86_64-apple-darwin) is not supported.

---

## Workflow Files

### `.github/workflows/ci.yml` - Test Pipeline

**Triggers:** Push to main, all PRs

**Jobs:**
1. **fmt** - Check formatting with `cargo fmt --check`
2. **clippy** - Lint with `cargo clippy -- -D warnings`
3. **test** - Run tests on Ubuntu, macOS, Windows
4. **security-audit** - Check for known vulnerabilities

### `.github/workflows/release.yml` - Release Pipeline

**Triggers:** Tags matching `v*`

**Steps:**
1. Build release binaries for all targets
2. Package with README, LICENSE, and Quick Action (macOS)
3. Generate SHA256 checksums
4. Create GitHub Release with assets

---

## Additional Configuration

- `.github/dependabot.yml` - Automated dependency updates
- `deny.toml` - Supply chain security (cargo-deny)
- `Cargo.toml` - MSRV (Minimum Supported Rust Version)

---

## Notes

- Clipboard tests (`#[ignore]`) require a display and cannot run in CI
- musl builds may need testing for arboard compatibility
- macOS releases include the Finder Quick Action workflow
