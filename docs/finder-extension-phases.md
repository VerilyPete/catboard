# Finder Extension Implementation Phases

This breaks the Finder extension plan into discrete phases, each sized for a single implementation session.

## Phase Overview

| Phase | Description | Dependencies | Estimated Scope |
|-------|-------------|--------------|-----------------|
| 1 | Xcode Project Setup | None | Create project structure |
| 2 | CatboardCore Framework | Phase 1 | 6 Swift files (~400 lines) |
| 3 | Finder Extension | Phases 1, 2 | 1 Swift file (~200 lines) |
| 4 | Container App | Phases 1, 2 | 1 Swift file (~60 lines) |
| 5 | Build & Distribution | Phases 1-4 | Signing, notarization, pkg |

---

## Phase 1: Xcode Project Setup

**Goal:** Create the Xcode project with all three targets configured.

**Deliverables:**
- `swift/CatboardFinder/CatboardFinder.xcodeproj`
- Three targets: CatboardFinder (app), FinderExtension, CatboardCore (framework)
- Basic Info.plist files for each target
- Entitlements files
- Empty Swift files as placeholders

**Structure to create:**
```
swift/CatboardFinder/
├── CatboardFinder.xcodeproj
├── CatboardFinder/
│   ├── AppDelegate.swift (placeholder)
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/Contents.json
│   ├── CatboardFinder.entitlements
│   └── Info.plist
├── FinderExtension/
│   ├── FinderSync.swift (placeholder)
│   ├── FinderSync.entitlements
│   └── Info.plist
└── CatboardCore/
    ├── CatboardCore.h
    ├── Info.plist
    └── (Swift files added in Phase 2)
```

**Build settings:**
- Deployment target: macOS 11.0
- Swift version: 5.0
- Hardened Runtime: YES
- App Sandbox: YES (for both app and extension)

**Framework linking:**
- FinderExtension links CatboardCore.framework
- CatboardFinder links CatboardCore.framework
- Both link: Cocoa, FinderSync, UserNotifications, Vision, Quartz

---

## Phase 2: CatboardCore Framework

**Goal:** Implement the shared framework with all file processing logic.

**Deliverables (6 files):**

### 2.1 Logging.swift
- OSLog extension with categories: fileReader, pdf, ocr, clipboard, ui
- ~15 lines

### 2.2 CatboardError.swift
- Error enum with 9 cases
- LocalizedError conformance
- ~45 lines

### 2.3 FileReader.swift
- `readContents(of:)` main entry point
- URL validation (isFileURL, exists, readable, size limit)
- UTType-based routing to PDF/Image/Text handlers
- Text file reading with encoding detection (UTF-8, UTF-16, Latin-1)
- Binary detection (null byte check)
- ~150 lines

### 2.4 PDFExtractor.swift
- `extractText(from:)` entry point
- PDFKit text extraction
- OCR fallback for scanned PDFs
- ~40 lines

### 2.5 OCREngine.swift
- `extractText(from:)` for images and PDFs
- Vision framework OCR with timeout (60s)
- PDF page rendering at 150 DPI
- Image dimension validation (50MP limit)
- autoreleasepool for memory management
- Page separators for multi-page PDFs
- ~200 lines

### 2.6 Clipboard.swift
- `copy(_:completion:)` async with size limit check
- `copySync(_:)` for main thread
- Thread-safe (main queue dispatch)
- ~50 lines

**Testing:**
- Can test framework independently with command-line tool
- All public APIs should work before Phase 3

---

## Phase 3: Finder Extension

**Goal:** Implement the FinderSync extension.

**Deliverables:**

### 3.1 FinderSync.swift
- FIFinderSync subclass
- Thread-safe notification permission caching
- Toolbar item (optional)
- Context menu with "Copy to Clipboard"
- File URL validation
- Background processing with async clipboard
- UserNotifications for feedback
- ~200 lines

**Key behaviors:**
- Only show menu for `.contextualMenuForItems`
- Reject multiple file selection
- Reject non-file URLs
- Process on background queue
- Copy on main queue (async)
- Show notification on completion

---

## Phase 4: Container App

**Goal:** Implement the minimal container app.

**Deliverables:**

### 4.1 AppDelegate.swift
- Request notification permission on launch
- Show dialog guiding user to enable extension
- Open System Settings/Preferences (version-aware URLs)
- ~60 lines

### 4.2 MainMenu.xib (optional)
- Minimal menu bar (can be code-only if preferred)

**Key behaviors:**
- Quit after last window closed
- Safe URL handling (no force unwraps)
- Correct app path for macOS 13+ vs earlier

---

## Phase 5: Build & Distribution

**Goal:** Configure signing, notarization, and distribution.

**Deliverables:**

### 5.1 Code Signing
- Developer ID Application certificate
- Team ID configuration
- Entitlements verification

### 5.2 Notarization
- ExportOptions.plist with Team ID
- notarytool submission script
- Stapling script

### 5.3 pkg Integration
- Add CatboardFinder.app to installer
- Update conclusion.html with enable instructions
- Do NOT auto-launch from post-install

### 5.4 Homebrew Cask (optional)
- catboard-finder cask formula
- depends_on macos: ">= :big_sur"
- postflight opens app

---

## Implementation Order

```
Phase 1 ──┬── Phase 2 ──┬── Phase 3 ──┐
          │             │             ├── Phase 5
          │             └── Phase 4 ──┘
          │
          └── (Can start signing setup in parallel)
```

**Critical path:** 1 → 2 → 3 → 5

Phase 4 can be done in parallel with Phase 3 since they're independent once Phase 2 is complete.

---

## Agent Instructions Template

For each phase, provide the agent with:

1. **Reference:** `docs/finder-extension-plan.md` (full implementation details)
2. **Scope:** Which files to create/modify
3. **Success criteria:** What should work when done
4. **Do NOT:** What to avoid (e.g., "don't implement Phase 3 code")

Example prompt for Phase 2:
```
Implement the CatboardCore framework for the Finder extension.

Reference: docs/finder-extension-plan.md contains full code for each file.

Create these files in swift/CatboardFinder/CatboardCore/:
- Logging.swift
- CatboardError.swift
- FileReader.swift
- PDFExtractor.swift
- OCREngine.swift
- Clipboard.swift

The Xcode project already exists (Phase 1 complete).
Do NOT implement FinderSync.swift or AppDelegate.swift.

Success: Framework builds without errors.
```
