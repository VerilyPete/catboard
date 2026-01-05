# Phase 5: Build & Distribution

**Goal:** Configure code signing, notarization, and integrate with distribution channels.

**Dependencies:** Phases 1-4 (complete, working app and extension)

**Reference:** [finder-extension-plan.md](../finder-extension-plan.md)

---

## Table of Contents

| Task | Purpose |
|------|---------|
| Code Signing Setup | Configure Developer ID certificates |
| ExportOptions.plist | Archive export configuration |
| Notarization Script | Automate notarization workflow |
| pkg Installer Integration | Add app to existing installer |
| Homebrew Cask Formula | Optional: standalone Homebrew distribution |

---

## 1. Code Signing Setup

### Prerequisites

- Apple Developer account (paid)
- Developer ID Application certificate installed in Keychain
- Team ID (find at https://developer.apple.com/account → Membership Details)

### Xcode Configuration

For each target, configure in Build Settings:

| Setting | Value |
|---------|-------|
| `CODE_SIGN_IDENTITY` | `Developer ID Application` |
| `DEVELOPMENT_TEAM` | Your Team ID (e.g., `ABC123XYZ`) |
| `CODE_SIGN_STYLE` | `Manual` (recommended for CI) |

### Verify Entitlements

**CatboardFinder.entitlements** (container app):
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

**FinderSync.entitlements** (extension):
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

---

## 2. ExportOptions.plist

Create `swift/CatboardFinder/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <!-- Replace YOUR_TEAM_ID with your actual Apple Developer Team ID -->
    <!-- Find it at: https://developer.apple.com/account -> Membership Details -->
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

---

## 3. Notarization Script

Create `scripts/notarize.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
PROJECT_DIR="swift/CatboardFinder"
SCHEME="CatboardFinder"
BUILD_DIR="build"
APP_NAME="CatboardFinder"

# These should be set as environment variables or passed as arguments
: "${APPLE_ID:?Set APPLE_ID environment variable}"
: "${TEAM_ID:?Set TEAM_ID environment variable}"
: "${APP_PASSWORD:?Set APP_PASSWORD environment variable (app-specific password)}"

echo "=== Step 1: Archive ==="
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive

echo "=== Step 2: Export ==="
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist"

echo "=== Step 3: Create ZIP for notarization ==="
ditto -c -k --keepParent "$BUILD_DIR/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.zip"

echo "=== Step 4: Submit for notarization ==="
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "=== Step 5: Staple the ticket ==="
xcrun stapler staple "$BUILD_DIR/$APP_NAME.app"

echo "=== Step 6: Verify ==="
spctl --assess --verbose "$BUILD_DIR/$APP_NAME.app"

echo "=== Done ==="
echo "Notarized app: $BUILD_DIR/$APP_NAME.app"
```

### Usage

```bash
export APPLE_ID="your@email.com"
export TEAM_ID="ABC123XYZ"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com

chmod +x scripts/notarize.sh
./scripts/notarize.sh
```

---

## 4. pkg Installer Integration

### Directory Structure

Update the installer to include:

```
CatboardInstaller.pkg
├── catboard (CLI binary) → /usr/local/bin/
├── catboard-ocr (Swift OCR helper) → /usr/local/bin/
└── CatboardFinder.app → /Applications/
```

### pkgbuild Command

Add to existing pkg build script:

```bash
# Build component for the Finder app
pkgbuild --root "$BUILD_DIR" \
    --install-location /Applications \
    --component "$BUILD_DIR/CatboardFinder.app" \
    --identifier com.verilypete.catboard.finder \
    --version "1.0" \
    CatboardFinder.pkg
```

### Conclusion HTML

Update installer conclusion page (`resources/conclusion.html`):

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h1 { font-size: 24px; }
        ol { line-height: 1.8; }
        .highlight { background: #f0f0f0; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>Installation Complete</h1>

    <h2>Command Line Tool</h2>
    <p>The <span class="highlight">catboard</span> command is now available in your terminal.</p>

    <h2>Finder Extension</h2>
    <p>To enable the Finder "Copy to Clipboard" feature:</p>
    <ol>
        <li>Open <strong>CatboardFinder</strong> from Applications</li>
        <li>Click "Open System Settings" when prompted</li>
        <li>Enable the <strong>CatboardFinder</strong> extension under Finder</li>
    </ol>
    <p>Then right-click any file in Finder to see "Copy to Clipboard"</p>
</body>
</html>
```

### Important: Do NOT Auto-Launch

The installer runs as root. Do NOT add a postinstall script that launches the app, as this would cause security issues. Let the user launch it manually.

---

## 5. Homebrew Cask Formula (Optional)

For standalone Homebrew distribution, create a cask formula:

**Location:** `Formula/catboard-finder.rb` (in homebrew-tap repo)

```ruby
cask "catboard-finder" do
  version "1.0.0"
  sha256 "COMPUTED_SHA256_HASH"

  url "https://github.com/VerilyPete/catboard/releases/download/v#{version}/CatboardFinder.app.zip"
  name "Catboard Finder Extension"
  desc "Finder extension to copy file contents to clipboard"
  homepage "https://github.com/VerilyPete/catboard"

  depends_on macos: ">= :big_sur"

  app "CatboardFinder.app"

  postflight do
    # Open the app to trigger the enable-extension dialog
    system_command "/usr/bin/open", args: ["/Applications/CatboardFinder.app"]
  end

  uninstall quit: "com.verilypete.CatboardFinder"

  zap trash: [
    "~/Library/Caches/com.verilypete.CatboardFinder",
    "~/Library/Preferences/com.verilypete.CatboardFinder.plist",
  ]
end
```

### Release Process

1. Build and notarize the app
2. Create ZIP: `ditto -c -k --keepParent CatboardFinder.app CatboardFinder.app.zip`
3. Compute SHA256: `shasum -a 256 CatboardFinder.app.zip`
4. Upload to GitHub release
5. Update cask formula with new version and SHA256
6. Submit PR to homebrew-tap

---

## Verification Checklist

| Step | Command | Expected Result |
|------|---------|-----------------|
| Check signing | `codesign -dvvv CatboardFinder.app` | Shows Developer ID, no errors |
| Check extension signing | `codesign -dvvv CatboardFinder.app/Contents/PlugIns/FinderExtension.appex` | Shows same Team ID |
| Check notarization | `spctl --assess --verbose CatboardFinder.app` | "accepted, source=Notarized Developer ID" |
| Check entitlements | `codesign -d --entitlements - CatboardFinder.app` | Shows sandbox entitlements |
| Test Gatekeeper | Download app via browser, open | No Gatekeeper warning |

---

## Troubleshooting

### "Developer cannot be verified" error

The app isn't notarized. Run the notarization script and staple the ticket.

### Extension doesn't appear in System Settings

1. Ensure the extension is properly signed
2. Kill Finder: `killall Finder`
3. Check Console.app for extension loading errors

### Notarization fails

Common issues:
- Hardened Runtime not enabled
- Missing entitlements
- Using development certificate instead of Developer ID
- App-specific password expired

Check submission status:
```bash
xcrun notarytool log <submission-id> \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"
```

---

## Success Criteria

1. App and extension are signed with Developer ID
2. Notarization succeeds without warnings
3. `spctl --assess` passes
4. App can be downloaded and opened without Gatekeeper warnings
5. Extension appears in System Settings after launching app
6. pkg installer includes app at `/Applications/CatboardFinder.app`

---

## Do NOT

- Use development/ad-hoc signing for distribution
- Skip notarization (app won't run for users)
- Auto-launch app from installer postinstall script
- Commit credentials or app-specific passwords to repo
