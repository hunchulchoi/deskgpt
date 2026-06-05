# DeskGPT Auto Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check GitHub Releases twice a day, download new versions automatically when enabled, and show a persistent `Restart to Update` prompt that can be deferred until the next launch.

**Architecture:** Add a small update subsystem that owns release discovery, version comparison, download caching, and install/relaunch orchestration. Keep UI concerns separate: `AppDelegate` wires menu actions and preferences, `DeskGPTViewController` presents the update banner, and a dedicated preferences window controls the auto-update toggle stored in `UserDefaults`.

**Tech Stack:** Swift, AppKit, URLSession, GitHub Releases REST API, `UserDefaults`, shell helper script launched from the app.

---

### Task 1: Add update state, release fetching, and background scheduling

**Files:**
- Create: `src/UpdateManager.swift`
- Modify: `src/AppDelegate.swift`
- Modify: `src/Info.plist`

- [ ] **Step 1: Write the failing compile target**

Add a new `UpdateManager` type with the methods and properties that the app will call:

```swift
final class UpdateManager {
    static let shared = UpdateManager()

    func start()
    func stop()
    func checkForUpdatesNow()
    func isAutoUpdateEnabled() -> Bool
    func setAutoUpdateEnabled(_ enabled: Bool)
    func pendingUpdateVersion() -> String?
}
```

- [ ] **Step 2: Run a compile check and confirm it fails**

Run:

```bash
swiftc src/UpdateManager.swift src/AppDelegate.swift src/main.swift -framework Cocoa -framework WebKit -framework PDFKit
```

Expected: fail because `UpdateManager` is not implemented yet and `AppDelegate` does not call it.

- [ ] **Step 3: Implement release discovery and scheduling**

Implement `UpdateManager` so it:

```swift
struct GitHubRelease: Decodable {
    let tagName: String
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
}
```

Fetches `https://api.github.com/repos/hunchulchoi/deskgpt/releases/latest`, compares `tagName` against `CFBundleShortVersionString`, and schedules a timer that checks every 12 hours when auto-update is enabled. Persist these keys in `UserDefaults`:

```swift
enum UpdateDefaultsKey {
    static let autoUpdateEnabled = "DeskGPTAutoUpdateEnabled"
    static let pendingUpdateVersion = "DeskGPTPendingUpdateVersion"
    static let pendingUpdateDownloadPath = "DeskGPTPendingUpdateDownloadPath"
    static let lastUpdateCheckDate = "DeskGPTLastUpdateCheckDate"
}
```

Use Application Support for cached downloads:

```swift
let updatesDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("DeskGPT/Updates", isDirectory: true)
```

Default `autoUpdateEnabled` to `true` if the key is missing.

- [ ] **Step 4: Run the compile check again**

Run the same `swiftc` command and verify the new type compiles cleanly.

- [ ] **Step 5: Commit**

```bash
git add src/UpdateManager.swift src/AppDelegate.swift src/Info.plist
git commit -m "feat: add auto update manager"
```

### Task 2: Add Preferences UI for auto update control

**Files:**
- Create: `src/PreferencesWindowController.swift`
- Modify: `src/AppDelegate.swift`

- [ ] **Step 1: Write the failing UI wiring**

Wire the existing `Preferences...` menu item to a new `showPreferencesWindow()` action and create a minimal preferences window controller with a checkbox:

```swift
let autoUpdateCheckbox = NSButton(checkboxWithTitle: "자동 업데이트 확인", target: self, action: #selector(toggleAutoUpdate(_:)))
autoUpdateCheckbox.state = UpdateManager.shared.isAutoUpdateEnabled() ? .on : .off
```

- [ ] **Step 2: Run a compile check and confirm it fails**

Run:

```bash
swiftc src/PreferencesWindowController.swift src/AppDelegate.swift src/main.swift -framework Cocoa -framework WebKit -framework PDFKit
```

Expected: fail until the new controller and action exist.

- [ ] **Step 3: Implement the preferences window**

Build a small AppKit window with:

```swift
let titleLabel = NSTextField(labelWithString: "업데이트")
let statusLabel = NSTextField(labelWithString: "새 버전이 있으면 자동으로 확인하고 다운로드합니다.")
let autoUpdateCheckbox = NSButton(checkboxWithTitle: "자동 업데이트 확인", target: self, action: #selector(toggleAutoUpdate(_:)))
```

The checkbox updates `UpdateManager.shared.setAutoUpdateEnabled(_:)` and immediately starts or stops the 12-hour timer.

- [ ] **Step 4: Verify the menu item opens the window**

Run the app locally and confirm `Preferences...` opens the new window and that the checkbox state matches `UserDefaults`.

- [ ] **Step 5: Commit**

```bash
git add src/PreferencesWindowController.swift src/AppDelegate.swift
git commit -m "feat: add preferences window for updates"
```

### Task 3: Show update banner and install on restart

**Files:**
- Modify: `src/DeskGPTViewController.swift`
- Modify: `src/AppDelegate.swift`
- Create: `src/UpdateInstaller.swift`

- [ ] **Step 1: Write the failing banner integration**

Add a method on `DeskGPTViewController` that can present update UI:

```swift
func showUpdateAvailable(version: String, downloadPath: URL)
func dismissUpdateBanner()
```

The banner should contain:

```swift
let titleLabel = NSTextField(labelWithString: "새 버전 \(version)을 다운로드했습니다.")
let restartButton = NSButton(title: "Restart to Update", target: self, action: #selector(restartToUpdate))
let laterButton = NSButton(title: "다음 실행에 적용", target: self, action: #selector(dismissUpdateBanner))
```

- [ ] **Step 2: Run a compile check and confirm it fails**

Run:

```bash
swiftc src/DeskGPTViewController.swift src/AppDelegate.swift src/main.swift -framework Cocoa -framework WebKit -framework PDFKit
```

Expected: fail until the new banner API exists.

- [ ] **Step 3: Implement the deferred installer**

Add `UpdateInstaller` to stage the downloaded DMG, mount it, copy `DeskGPT.app`, and relaunch after the running process exits.

```swift
final class UpdateInstaller {
    static func installAndRelaunch(from dmgURL: URL, bundleIdentifier: String)
}
```

The helper should:

```bash
#!/bin/bash
set -euo pipefail
APP_PATH="/Applications/DeskGPT.app"
MOUNT_POINT="$(mktemp -d /tmp/deskgpt-update-mount.XXXXXX)"
hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_POINT" -quiet
while pgrep -x DeskGPT >/dev/null; do sleep 0.5; done
rm -rf "$APP_PATH"
ditto "$MOUNT_POINT/DeskGPT.app" "$APP_PATH"
hdiutil detach "$MOUNT_POINT" -quiet || true
open "$APP_PATH"
```

Keep the downloaded DMG path in `UserDefaults` so if the user clicks `Later`, the next launch can show the same pending update again without re-downloading.

- [ ] **Step 4: Verify the restart flow locally**

Confirm that clicking `Restart to Update` launches the helper, quits the app, replaces the bundle, and relaunches the updated app.

- [ ] **Step 5: Commit**

```bash
git add src/DeskGPTViewController.swift src/AppDelegate.swift src/UpdateInstaller.swift
git commit -m "feat: add deferred update install flow"
```

### Task 4: Wire update checks into app startup and release verification

**Files:**
- Modify: `src/AppDelegate.swift`
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Write the startup wiring**

Start the update manager when the app finishes launching and trigger an immediate check on launch:

```swift
UpdateManager.shared.start()
UpdateManager.shared.checkForUpdatesNow()
```

When a newer release is discovered, tell `DeskGPTViewController` to show the banner and pass the cached DMG path.

- [ ] **Step 2: Verify the workflow asset naming still matches the updater**

Confirm the release workflow continues to publish a DMG named like:

```text
DeskGPT-1.0.6.dmg
```

The updater will resolve this from the GitHub API release asset list, so no additional feed file is needed as long as the release asset name stays stable.

- [ ] **Step 3: Run end-to-end verification**

Run:

```bash
bash -n build.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "YAML OK"'
swiftc src/main.swift src/AppDelegate.swift src/DeskGPTViewController.swift src/DeskGPTPDFViewController.swift src/UpdateManager.swift src/PreferencesWindowController.swift src/UpdateInstaller.swift -framework Cocoa -framework WebKit -framework PDFKit
```

Expected: all commands succeed.

- [ ] **Step 4: Manual test checklist**

1. Launch the app with `자동 업데이트 확인` enabled.
2. Confirm it checks GitHub Releases on launch.
3. Confirm an available release shows `Restart to Update`.
4. Confirm clicking `Later` leaves the app usable and the prompt returns on the next launch.
5. Confirm disabling the checkbox stops periodic checks while keeping the app functional.

- [ ] **Step 5: Commit**

```bash
git add src/AppDelegate.swift .github/workflows/release.yml
git commit -m "feat: wire update checks into startup"
```

