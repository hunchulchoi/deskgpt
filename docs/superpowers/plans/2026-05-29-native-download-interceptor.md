# Native WebKit Download Interceptor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Intercept WebKit's native "Download Image" (이미지 다운로드) context menu item and route it cleanly to our secure cookie-mapped Swift URLSession downloader.

**Architecture:** Update `decidePolicyFor navigationAction` and `decidePolicyFor navigationResponse` in `DeskGPTViewController.swift` to hijack `.download` policy triggers, route the URL, and call `.cancel`.

**Tech Stack:** Swift, AppKit, WebKit (WKWebView)

---

### Task 1: Hijack Native WebKit Download Actions and Responses

**Files:**
- Modify: [DeskGPTViewController.swift](file:///Users/hunchulchoi/projects/workspace/myside/gpt_exe/src/DeskGPTViewController.swift)

- [ ] **Step 1: Rewrite decidePolicyFor navigationAction with native download hijacking**

Locate `decidePolicyFor navigationAction` inside `DeskGPTViewController.swift` (around lines 115-155) and modify it:

```swift
    // MARK: - WKNavigationDelegate: Intercept Downloads and Outbound Web Routing (macOS 11.3+)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                // Hijack WebKit's default context menu download action ("이미지 다운로드")
                if let url = navigationAction.request.url {
                    var filename = url.lastPathComponent
                    if !filename.contains(".") {
                        filename = "image.png"
                    }
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    print("🚀 Intercepted native download request for: \(url.absoluteString)")
                    
                    // Route securely to our custom downloader to sync cookies
                    self.downloadImage(from: url, to: destinationUrl)
                }
                
                // Cancel the native buggy thread to prevent double downloads and 403 errors
                decisionHandler(.cancel)
                return
            }
        }
        
        // Intercept and route outbound external links safely to default macOS Safari
        if let url = navigationAction.request.url {
            let host = url.host?.lowercased() ?? ""
            
            // Whitelist of domains allowed to remain inside DeskGPT
            let allowedHosts = [
                "chatgpt.com", 
                "openai.com", 
                "oaiusercontent.com", 
                "auth0.com", 
                "appleid.apple.com", 
                "accounts.google.com", 
                "sentry.io"
            ]
            
            // Allow hosts that match exactly or are subdomains of whitelisted domains
            let isAllowed = host.isEmpty || allowedHosts.contains { allowed in
                host == allowed || host.hasSuffix("." + allowed)
            }
            
            if !isAllowed {
                print("🌐 Outbound link routed to Safari: \(url.absoluteString)")
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        
        decisionHandler(.allow)
    }
```

- [ ] **Step 2: Hijack decidePolicyFor navigationResponse for Content-Disposition attachments**

Locate `decidePolicyFor navigationResponse` inside `DeskGPTViewController.swift` and modify it:

```swift
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationResponse.canShowMIMEType == false {
                // If it is a download attachment, hijack it cleanly
                if let url = navigationResponse.response.url {
                    let filename = navigationResponse.response.suggestedFilename ?? "file.dat"
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    self.downloadImage(from: url, to: destinationUrl)
                }
                decisionHandler(.cancel)
                return
            }
        }
        
        // Inspect HTTP headers for "Content-Disposition: attachment" (Crucial for ChatGPT image downloads)
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let headers = httpResponse.allHeaderFields as? [String: String],
           let url = navigationResponse.response.url {
            for (key, value) in headers {
                if key.lowercased() == "content-disposition" && value.lowercased().contains("attachment") {
                    let filename = navigationResponse.response.suggestedFilename ?? "file.dat"
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    self.downloadImage(from: url, to: destinationUrl)
                    
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        decisionHandler(.allow)
    }
```

- [ ] **Step 3: Compile and Hotfix Deploy**

Run compile & applications folder deployment:
`./build.sh && rm -rf /Applications/DeskGPT.app && cp -R build/DeskGPT.app /Applications/DeskGPT.app`
Expected: Succeeds cleanly.

- [ ] **Step 4: Commit and Push**

```bash
git add src/DeskGPTViewController.swift docs/superpowers/plans/2026-05-29-native-download-interceptor.md
git commit -m "feat: hijack native WebKit download actions to use secure URLSession downloader"
git push origin main
```
