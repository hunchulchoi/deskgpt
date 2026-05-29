# Synchronous Menu Caching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement synchronous context menu image pre-caching to bypass WebKit's asynchronous `evaluateJavaScript` rendering bug.

**Architecture:** Add `lastRightClickedImageUrl` property to `DeskGPTViewController.swift`. Set up `"rightClickImageDetected"` script message handler. Inject JavaScript `"contextmenu"` event capture to cache image URLs prior to menu rendering, allowing `willOpenMenu` to update items synchronously.

**Tech Stack:** Swift, AppKit, WebKit (WKWebView, WKUserScript, MutationObserver)

---

### Task 1: Setup Synchronous Image Caching & Menu Customization

**Files:**
- Modify: [DeskGPTViewController.swift](file:///Users/hunchulchoi/projects/workspace/myside/gpt_exe/src/DeskGPTViewController.swift)

- [ ] **Step 1: Define lastRightClickedImageUrl property and script message handler registration**

Add the property and update the user content controller configuration in `loadView` inside `DeskGPTViewController.swift`:

```swift
class DeskGPTViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var webView: WKWebView!
    var lastRightClickedImageUrl: URL? // Synchronous cache for context menu images
```

Inside `loadView()`:
```swift
        // Configure WKUserContentController for JS message posting and script injection
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "directSaveImage")
        userContentController.add(self, name: "rightClickImageDetected") // Register synchronous cache handler
```

- [ ] **Step 2: Update jsSource to listen to contextmenu capture and pre-cache URLs**

Modify the `jsSource` string inside `loadView` to capture `"contextmenu"` events:

```swift
        let jsSource = """
        (function() {
            // 1. Inject styles for the floating download button
            var style = document.createElement('style');
            style.innerHTML = `
                .deskgpt-download-container {
                    position: relative !important;
                }
                .deskgpt-download-btn {
                    position: absolute !important;
                    top: 12px !important;
                    right: 12px !important;
                    z-index: 999999 !important;
                    background: rgba(15, 23, 42, 0.75) !important;
                    backdrop-filter: blur(8px) -webkit-backdrop-filter: blur(8px) !important;
                    border: 1px solid rgba(255, 255, 255, 0.2) !important;
                    border-radius: 6px !important;
                    color: #ffffff !important;
                    padding: 5px 10px !important;
                    font-size: 12px !important;
                    font-weight: 600 !important;
                    cursor: pointer !important;
                    opacity: 0 !important;
                    transition: opacity 0.2s ease-in-out, background 0.15s ease !important;
                    display: flex !important;
                    align-items: center !important;
                    gap: 4px !important;
                    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2) !important;
                }
                .deskgpt-download-btn:hover {
                    background: rgba(15, 23, 42, 0.9) !important;
                    border-color: rgba(255, 255, 255, 0.4) !important;
                }
                .deskgpt-download-container:hover .deskgpt-download-btn {
                    opacity: 1 !important;
                }
            `;
            document.head.appendChild(style);

            // 2. Scan and attach download buttons to images
            function scanAndAttach() {
                var images = document.querySelectorAll('img[src*="oaiusercontent.com"], img[src*="blob:"]');
                images.forEach(function(img) {
                    var container = img.closest('.relative') || img.parentElement;
                    if (!container) return;
                    container.classList.add('deskgpt-download-container');
                    if (container.querySelector('.deskgpt-download-btn')) return;
                    
                    var btn = document.createElement('button');
                    btn.className = 'deskgpt-download-btn';
                    btn.innerHTML = '⬇️ 저장';
                    btn.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        var src = img.src;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.directSaveImage) {
                            window.webkit.messageHandlers.directSaveImage.postMessage(src);
                        }
                    });
                    container.appendChild(btn);
                });
            }

            scanAndAttach();
            setInterval(scanAndAttach, 1500);
            var observer = new MutationObserver(scanAndAttach);
            observer.observe(document.body, { childList: true, subtree: true });

            // 3. Listen to contextmenu event to pre-cache image URL synchronously
            window.addEventListener('contextmenu', function(event) {
                var elements = document.elementsFromPoint(event.clientX, event.clientY);
                var imgSrc = "";
                if (elements && elements.length > 0) {
                    for (var i = 0; i < elements.length; i++) {
                        var el = elements[i];
                        if (el.tagName === 'IMG') {
                            imgSrc = el.src;
                            break;
                        }
                        if (el.tagName === 'CANVAS') {
                            imgSrc = el.toDataURL();
                            break;
                        }
                        var img = el.querySelector('img');
                        if (img) {
                            imgSrc = img.src;
                            break;
                        }
                    }
                }
                // Post detected image URL (or empty string) to pre-cache in Swift
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rightClickImageDetected) {
                    window.webkit.messageHandlers.rightClickImageDetected.postMessage(imgSrc);
                }
            }, true);
        })();
        """
```

- [ ] **Step 3: Update WKScriptMessageHandler extension to handle cache updates**

Update `userContentController` inside `DeskGPTViewController.swift`'s extension to process the new message:

```swift
extension DeskGPTViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "directSaveImage" {
            guard let imageUrlString = message.body as? String, let url = URL(string: imageUrlString) else { return }
            var filename = url.lastPathComponent
            if !filename.contains(".") { filename = "image.png" }
            let destinationUrl = getUniqueDownloadsURL(suggestedName: filename)
            self.downloadImage(from: url, to: destinationUrl)
        } else if message.name == "rightClickImageDetected" {
            // Synchronously cache the image URL before the context menu displays
            if let imageUrlString = message.body as? String, !imageUrlString.isEmpty, let url = URL(string: imageUrlString) {
                self.lastRightClickedImageUrl = url
                print("🎯 Cached right-clicked image URL: \(url.absoluteString)")
            } else {
                self.lastRightClickedImageUrl = nil
            }
        }
    }
}
```

- [ ] **Step 4: Rewrite willOpenMenu to be 100% synchronous**

Replace `willOpenMenu` in `DeskGPTViewController.swift` with a synchronous, race-condition-free implementation:

```swift
    // MARK: - WKUIDelegate: Custom Context Menu for Images (Save Image As... Fix)
    func webView(_ webView: WKWebView, willOpenMenu menu: NSMenu, with event: NSEvent) {
        // Synchronously check the pre-cached right-clicked image URL
        guard let url = self.lastRightClickedImageUrl else {
            print("ℹ️ willOpenMenu: No cached image found at right-click coordinates.")
            return
        }
        
        // Clear any default buggy web view download items to prevent silent failures
        let titlesToRemove = ["save image to downloads", "save image as", "download image", "이미지 저장", "다운로드", "다운로드 폴더에 이미지 저장"]
        menu.items.removeAll { item in
            let title = item.title.lowercased()
            return titlesToRemove.contains { title.contains($0) }
        }
        
        // Determine system preferred language to display native-like Korean/English
        let isKorean = NSLocale.preferredLanguages.first?.hasPrefix("ko") ?? false
        let directTitle = isKorean ? "다운로드 폴더에 이미지 저장" : "Save Image to Downloads"
        let saveAsTitle = isKorean ? "이미지를 다른 이름으로 저장..." : "Save Image As..."
        
        // Add direct download menu item
        let directItem = NSMenuItem(title: directTitle, action: #selector(self.customSaveImageDirectAction(_:)), keyEquivalent: "")
        directItem.target = self
        directItem.representedObject = url
        menu.insertItem(directItem, at: 0)
        
        // Add custom save-as item
        let saveAsItem = NSMenuItem(title: saveAsTitle, action: #selector(self.customSaveImageAction(_:)), keyEquivalent: "")
        saveAsItem.target = self
        saveAsItem.representedObject = url
        menu.insertItem(saveAsItem, at: 1)
        
        print("🎯 willOpenMenu: Synchronously inserted custom menu items for: \(url.lastPathComponent)")
    }
```

- [ ] **Step 5: Compile and Hotfix Deploy**

Run compile & applications folder deployment:
`./build.sh && rm -rf /Applications/DeskGPT.app && cp -R build/DeskGPT.app /Applications/DeskGPT.app`
Expected: Succeeds cleanly.

- [ ] **Step 6: Commit and Push**

```bash
git add src/DeskGPTViewController.swift docs/superpowers/plans/2026-05-29-synchronous-menu-caching.md
git commit -m "fix: resolve willOpenMenu asynchronous timing bug via capturing contextmenu pre-caching"
git push origin main
```
