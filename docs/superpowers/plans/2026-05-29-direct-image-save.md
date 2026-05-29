# Direct Image Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement premium, localized native-like context menus and a lightning-fast Option(⌥) + Click direct download gesture for DeskGPT.

**Architecture:** Inject captures-phase global JavaScript to listen to `Option + Click` clicks on image/canvas tags and post message to Swift. Implement `WKScriptMessageHandler` to securely decode/download directly. Update AppKit `willOpenMenu` to dynamically offer localized native browser actions.

**Tech Stack:** Swift, AppKit, WebKit (WKWebView, WKUserContentController, WKScriptMessageHandler)

---

### Task 1: Add WKScriptMessageHandler & Setup JS Injection

**Files:**
- Modify: [DeskGPTViewController.swift](file:///Users/hunchulchoi/projects/workspace/myside/gpt_exe/src/DeskGPTViewController.swift)

- [ ] **Step 1: Implement WKScriptMessageHandler and inject custom event script**

Modify `loadView` inside `DeskGPTViewController.swift` to construct a `WKUserContentController`, add script message handler for `"directSaveImage"`, and inject the capturing click event listener.

```swift
    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        // default persistent datastore preserves cookies, sessions, and local storage across restarts
        webConfiguration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable Safari Web Inspector / DevTools for debugging
        webConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Configure WKUserContentController for JS message posting and script injection
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "directSaveImage")
        
        let jsSource = """
        window.addEventListener('click', function(event) {
            if (!event.altKey) return;
            
            var elements = document.elementsFromPoint(event.clientX, event.clientY);
            var imgSrc = null;
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
            if (!imgSrc) {
                // Fallback: Check if clicked inside a div container having background-image
                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    var bg = window.getComputedStyle(el).backgroundImage;
                    if (bg && bg !== 'none') {
                        var match = bg.match(/url\\\\(["']?([^"']+)["']?\\\\)/);
                        if (match && match[1]) {
                            imgSrc = match[1];
                            break;
                        }
                    }
                }
            }
            if (imgSrc) {
                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.directSaveImage.postMessage(imgSrc);
            }
        }, true);
        """
        let userScript = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)
        webConfiguration.userContentController = userContentController
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // Set standard macOS Safari User Agent to bypass bot/webview block gates
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        
        self.view = webView
    }
```

- [ ] **Step 2: Add WKScriptMessageHandler extension to process direct save calls**

At the bottom of `DeskGPTViewController.swift`, implement the protocol extension to handle JavaScript messages:

```swift
extension DeskGPTViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "directSaveImage",
              let imageUrlString = message.body as? String,
              let url = URL(string: imageUrlString) else { return }
        
        // Deduce filename
        var filename = url.lastPathComponent
        if !filename.contains(".") {
            filename = "image.png"
        }
        
        let destinationUrl = getUniqueDownloadsURL(suggestedName: filename)
        print("🚀 JavaScript Direct Save: Saving straight to \\(destinationUrl.path)")
        
        if url.scheme == "data" {
            self.saveDataURL(url, to: destinationUrl)
        } else {
            self.downloadImage(from: url, to: destinationUrl)
        }
    }
}
```

- [ ] **Step 3: Modify DeskGPTViewController class definition to comply with WKScriptMessageHandler**

Add `WKScriptMessageHandler` compliance directly to the class line:
`class DeskGPTViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler`

- [ ] **Step 4: Verify Compilation**

Run build script to check if the class definition and extensions compile cleanly:
`./build.sh`
Expected: Succeeds without errors.

---

### Task 2: Localize Context Menu Labels to Native Browser Titles

**Files:**
- Modify: [DeskGPTViewController.swift](file:///Users/hunchulchoi/projects/workspace/myside/gpt_exe/src/DeskGPTViewController.swift)

- [ ] **Step 1: Replace hardcoded menus with localized system-style browser labels**

Modify the `willOpenMenu` function inside `DeskGPTViewController.swift` to adapt to the language preferred by macOS.

```swift
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
```

- [ ] **Step 2: Compile and Build App**

Run the build script to compile everything:
`./build.sh`
Expected: Succeeds without errors.

- [ ] **Step 3: Commit Changes**

```bash
git add src/DeskGPTViewController.swift
git commit -m "feat: implement native direct image downloader via Option+Click & localized context menus"
```
