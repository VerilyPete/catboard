# Phase 1: Xcode Project Setup

**Goal:** Create the Xcode project with all three targets configured.

**Dependencies:** None

**Reference:** [finder-extension-plan.md](../finder-extension-plan.md)

---

## Getting Started

Create the Xcode project using Xcode's wizards:

1. **Create the main app:**
   - Xcode → File → New → Project
   - Choose macOS → App
   - Product Name: `CatboardFinder`
   - Organization Identifier: `com.verilypete`
   - Interface: SwiftUI or Storyboard (we'll remove the UI)
   - Language: Swift

2. **Add the Finder Sync Extension target:**
   - File → New → Target
   - Choose macOS → Finder Sync Extension
   - Product Name: `FinderExtension`
   - Embed in Application: CatboardFinder

3. **Add the Framework target:**
   - File → New → Target
   - Choose macOS → Framework
   - Product Name: `CatboardCore`

4. **Clean up generated files:**
   - Delete any generated ContentView.swift or Main.storyboard
   - Replace generated Swift files with the placeholders below

**Minimum Xcode Version:** Xcode 13.0 or later (for macOS 11.0 deployment target)

---

## Table of Contents

| File | Purpose |
|------|---------|
| `swift/CatboardFinder/CatboardFinder.xcodeproj` | Xcode project with three targets |
| `swift/CatboardFinder/CatboardFinder/Info.plist` | Container app metadata |
| `swift/CatboardFinder/CatboardFinder/CatboardFinder.entitlements` | App sandbox entitlements |
| `swift/CatboardFinder/CatboardFinder/AppDelegate.swift` | Placeholder (implemented in Phase 4) |
| `swift/CatboardFinder/CatboardFinder/Assets.xcassets/` | App icons |
| `swift/CatboardFinder/FinderExtension/Info.plist` | Extension metadata with NSExtension config |
| `swift/CatboardFinder/FinderExtension/FinderSync.entitlements` | Extension sandbox entitlements |
| `swift/CatboardFinder/FinderExtension/FinderSync.swift` | Placeholder (implemented in Phase 3) |
| `swift/CatboardFinder/CatboardCore/Info.plist` | Framework metadata |
| `swift/CatboardFinder/CatboardCore/CatboardCore.h` | Framework umbrella header |

---

## Project Structure to Create

```
swift/CatboardFinder/
├── CatboardFinder.xcodeproj
├── CatboardFinder/                    # Container app target
│   ├── AppDelegate.swift              # Placeholder: import Cocoa; @main class AppDelegate: NSObject, NSApplicationDelegate {}
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/Contents.json
│   ├── CatboardFinder.entitlements
│   └── Info.plist
├── FinderExtension/                   # Finder Sync Extension target
│   ├── FinderSync.swift               # Placeholder: import FinderSync; class FinderSync: FIFinderSync {}
│   ├── FinderSync.entitlements
│   └── Info.plist
└── CatboardCore/                      # Shared framework target
    ├── CatboardCore.h
    └── Info.plist
```

---

## Target Configuration

### Target 1: CatboardFinder (macOS Application)

**Bundle Identifier:** `com.verilypete.CatboardFinder`

**Info.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

**CatboardFinder.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

**Placeholder AppDelegate.swift:**
```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Implemented in Phase 4
    }
}
```

---

### Target 2: FinderExtension (Finder Sync Extension)

**Bundle Identifier:** `com.verilypete.CatboardFinder.FinderExtension`

**Info.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Catboard</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).FinderSync</string>
    </dict>
</dict>
</plist>
```

**FinderSync.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

**Placeholder FinderSync.swift:**
```swift
import FinderSync

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Implemented in Phase 3
    }
}
```

---

### Target 3: CatboardCore (Framework)

**Bundle Identifier:** `com.verilypete.CatboardCore`

**Info.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
</dict>
</plist>
```

**CatboardCore.h:**
```objc
#import <Foundation/Foundation.h>

//! Project version number for CatboardCore.
FOUNDATION_EXPORT double CatboardCoreVersionNumber;

//! Project version string for CatboardCore.
FOUNDATION_EXPORT const unsigned char CatboardCoreVersionString[];
```

---

## Build Settings

Apply these settings to all targets:

| Setting | Value |
|---------|-------|
| `MACOSX_DEPLOYMENT_TARGET` | `11.0` |
| `SWIFT_VERSION` | `5.0` |
| `ENABLE_HARDENED_RUNTIME` | `YES` |

### Framework Linking

**FinderExtension target:**
- Link `CatboardCore.framework` (embed and sign)
- Link system frameworks: `Cocoa`, `FinderSync`, `UserNotifications`, `Vision`, `Quartz`

**CatboardFinder target:**
- Link `CatboardCore.framework` (embed and sign)
- Link system frameworks: `Cocoa`, `UserNotifications`

**CatboardCore target:**
- Link system frameworks: `Foundation`, `AppKit`, `Vision`, `Quartz`, `UniformTypeIdentifiers`

---

## Assets

**AppIcon.appiconset/Contents.json:**
```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

---

## Success Criteria

1. Project opens in Xcode without errors
2. All three targets are visible in the project navigator
3. Building the CatboardFinder scheme builds all targets
4. Framework is embedded in both app and extension
5. Entitlements files are correctly associated with targets
6. Deployment target is macOS 11.0

---

## Do NOT

- Implement actual Swift code beyond placeholders
- Add Swift files to CatboardCore (Phase 2)
- Configure code signing identities (Phase 5)
- Create app icons (optional, can use placeholder)
