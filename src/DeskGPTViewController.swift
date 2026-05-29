import Cocoa
import WebKit

class DeskGPTViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var webView: WKWebView!
    
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
                /* Reveal button on hover over the container */
                .deskgpt-download-container:hover .deskgpt-download-btn {
                    opacity: 1 !important;
                }
            `;
            document.head.appendChild(style);

            // 2. Scan and attach download buttons to images
            function scanAndAttach() {
                var images = document.querySelectorAll('img[src*="oaiusercontent.com"], img[src*="blob:"]');
                images.forEach(function(img) {
                    // Find parent container with position: relative or fallback to direct parent
                    var container = img.closest('.relative') || img.parentElement;
                    if (!container) return;
                    
                    // Mark the container
                    container.classList.add('deskgpt-download-container');
                    
                    // Check if button is already added
                    if (container.querySelector('.deskgpt-download-btn')) return;
                    
                    // Create sleek download button
                    var btn = document.createElement('button');
                    btn.className = 'deskgpt-download-btn';
                    btn.innerHTML = '⬇️ 저장';
                    btn.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        
                        var src = img.src;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.directSaveImage) {
                            window.webkit.messageHandlers.directSaveImage.postMessage(src);
                        } else {
                            alert("Direct save handler is not available. Please restart the app.");
                        }
                    });
                    
                    container.appendChild(btn);
                });
            }

            // Run scans periodically and via MutationObserver to support dynamic React DOM updates
            scanAndAttach();
            setInterval(scanAndAttach, 1500);
            
            var observer = new MutationObserver(scanAndAttach);
            observer.observe(document.body, { childList: true, subtree: true });
        })();
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = URL(string: "https://chatgpt.com") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    // MARK: - WKUIDelegate: File Upload and New Window Handling
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK {
                completionHandler(openPanel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    // Handle target="_blank" links (essential for image downloads and external links)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                // Open internal and OpenAI hosting CDN links inside the app, and external links in the default browser
                if host.contains("chatgpt.com") || host.contains("openai.com") || host.contains("oaiusercontent.com") {
                    webView.load(navigationAction.request)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        return nil
    }
    
    // MARK: - WKNavigationDelegate: Intercept Downloads and Outbound Web Routing (macOS 11.3+)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
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
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationResponse.canShowMIMEType == false {
                decisionHandler(.download)
                return
            }
        }
        
        // Inspect HTTP headers for "Content-Disposition: attachment" (Crucial for ChatGPT image downloads)
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let headers = httpResponse.allHeaderFields as? [String: String] {
            for (key, value) in headers {
                if key.lowercased() == "content-disposition" && value.lowercased().contains("attachment") {
                    decisionHandler(.download)
                    return
                }
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                completionHandler(url)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        NSSound.beep()
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let alert = NSAlert()
        alert.messageText = "다운로드 실패"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
    
    // MARK: - Navigation, Zoom, and Utility Controls
    func zoomIn() {
        webView.pageZoom += 0.1
    }
    
    func zoomOut() {
        if webView.pageZoom > 0.5 {
            webView.pageZoom -= 0.1
        }
    }
    
    func resetZoom() {
        webView.pageZoom = 1.0
    }
    
    func reloadPage() {
        webView.reload()
    }
    
    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    // MARK: - Smart Prompt Injection (Inject text into ChatGPT Input)
    func injectTextIntoChat(_ text: String) {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        let jsScript = """
        (function() {
            var textarea = document.querySelector('#prompt-textarea') || document.querySelector('textarea');
            if (textarea) {
                textarea.focus();
                textarea.value = "\(escapedText)";
                textarea.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
            }
            return false;
        })();
        """
        
        webView.evaluateJavaScript(jsScript) { result, error in
            if let error = error {
                print("Text injection failed: \(error.localizedDescription)")
            } else if let success = result as? Bool, !success {
                // Safe Fallback: Copy to clipboard if textarea not found
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "클립보드 복사 완료"
                    alert.informativeText = "ChatGPT의 입력칸을 자동으로 찾지 못했습니다. 텍스트가 클립보드에 안전하게 복사되었으니 원하시는 곳에 붙여넣기(Cmd+V) 해주세요."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "확인")
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Cache & Session Cleaning
    func resetSession() {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            DispatchQueue.main.async {
                self.reloadPage()
                let alert = NSAlert()
                alert.messageText = "세션 초기화 완료"
                alert.informativeText = "쿠키 및 로컬 캐시가 완전히 삭제되었으며, 앱을 새로고침합니다."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "확인")
                alert.runModal()
            }
        }
    }
    
    // MARK: - WKUIDelegate: Custom Context Menu for Images (Save Image As... Fix)
    func webView(_ webView: WKWebView, willOpenMenu menu: NSMenu, with event: NSEvent) {
        // Convert screen-based event location to web view bounds
        let point = webView.convert(event.locationInWindow, from: nil)
        let webX = point.x
        let webY = webView.bounds.height - point.y
        
        // Advanced JavaScript using elementsFromPoint (plural) to drill down through overlapping z-index overlay DOM elements 
        // to find the underlying image/canvas, with a fallback to search the active preview image in the page.
        let jsScript = """
        (function() {
            var elements = document.elementsFromPoint(\(webX), \(webY));
            if (elements && elements.length > 0) {
                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    if (el.tagName === 'IMG') return el.src;
                    if (el.tagName === 'CANVAS') return el.toDataURL();
                    var img = el.querySelector('img');
                    if (img) return img.src;
                }
            }
            // Robust Fallback: Try to find the large active image preview generated by ChatGPT in the DOM
            var activePreviews = document.querySelectorAll('img[src*="oaiusercontent.com"], img[src*="blob:"], div[style*="background-image"] img');
            if (activePreviews && activePreviews.length > 0) {
                // Return the last displayed preview image (which is typically the most recent one under focus)
                return activePreviews[activePreviews.length - 1].src;
            }
            return null;
        })();
        """
        
        webView.evaluateJavaScript(jsScript) { [weak self] result, error in
            if let error = error {
                print("🚀 willOpenMenu JS Error: \(error.localizedDescription)")
                return
            }
            guard let self = self else { return }
            guard let imageUrlString = result as? String, let url = URL(string: imageUrlString) else {
                print("🚀 willOpenMenu: No image found at right-click coordinates or DOM fallback.")
                return
            }
            
            DispatchQueue.main.async {
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
                
                print("🚀 willOpenMenu: Successfully inserted Save Image items (Direct & Save-As).")
            }
        }
    }
    
    @objc func customSaveImageDirectAction(_ sender: NSMenuItem) {
        guard let imageUrl = sender.representedObject as? URL else { return }
        
        // Deduce filename
        var filename = imageUrl.lastPathComponent
        if !filename.contains(".") {
            filename = "image.png"
        }
        
        // Compute the safe unique destination URL inside the Downloads folder
        let destinationUrl = getUniqueDownloadsURL(suggestedName: filename)
        print("🚀 Save Direct: Saving straight to \(destinationUrl.path)")
        
        if imageUrl.scheme == "data" {
            self.saveDataURL(imageUrl, to: destinationUrl)
        } else {
            self.downloadImage(from: imageUrl, to: destinationUrl)
        }
    }
    
    @objc func customSaveImageAction(_ sender: NSMenuItem) {
        guard let imageUrl = sender.representedObject as? URL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Save Image"
        
        // Deduce filename
        let filename = imageUrl.lastPathComponent
        savePanel.nameFieldStringValue = filename.contains(".") ? filename : "image.png"
        
        savePanel.begin { [weak self] response in
            guard let self = self, response == .OK, let destinationUrl = savePanel.url else { return }
            
            if imageUrl.scheme == "data" {
                self.saveDataURL(imageUrl, to: destinationUrl)
            } else {
                self.downloadImage(from: imageUrl, to: destinationUrl)
            }
        }
    }
    
    // Resolves duplicate filenames inside ~/Downloads by appending a standard counter e.g., image (1).png
    private func getUniqueDownloadsURL(suggestedName: String) -> URL {
        let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let name = suggestedName.isEmpty ? "image.png" : suggestedName
        
        let fileManager = FileManager.default
        var destinationUrl = downloadsUrl.appendingPathComponent(name)
        
        if fileManager.fileExists(atPath: destinationUrl.path) {
            let fileExtension = destinationUrl.pathExtension
            let baseName = destinationUrl.deletingPathExtension().lastPathComponent
            var counter = 1
            while true {
                let newName = "\(baseName) (\(counter)).\(fileExtension)"
                let newUrl = downloadsUrl.appendingPathComponent(newName)
                if !fileManager.fileExists(atPath: newUrl.path) {
                    destinationUrl = newUrl
                    break
                }
                counter += 1
            }
        }
        return destinationUrl
    }
    
    private func downloadImage(from url: URL, to destination: URL) {
        // Fetch webview cookies to prevent 403 Forbidden errors when downloading protected CDN assets
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            // Map Swift cookies to the request HTTP headers manually
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                if let error = error {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: error.localizedDescription)
                    return
                }
                
                // Handle HTTP response errors (e.g., 403, 404)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: "서버가 \(httpResponse.statusCode) 에러를 반환했습니다. 세션 만료 혹은 보안 차단일 수 있습니다.")
                    return
                }
                
                guard let data = data else {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: "데이터가 비어 있습니다.")
                    return
                }
                do {
                    try data.write(to: destination)
                    DispatchQueue.main.async {
                        NSSound.beep()
                        
                        // Notify the user exactly where the image was saved
                        let alert = NSAlert()
                        alert.messageText = "이미지 저장 완료"
                        alert.informativeText = "이미지가 다운로드 폴더에 안전하게 저장되었습니다:\n\(destination.lastPathComponent)"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "확인")
                        alert.runModal()
                    }
                } catch {
                    self.showErrorAlert(message: "이미지 저장 실패", info: error.localizedDescription)
                }
            }
            task.resume()
        }
    }
    
    private func saveDataURL(_ url: URL, to destination: URL) {
        let urlString = url.absoluteString
        guard let commaIndex = urlString.firstIndex(of: ",") else {
            self.showErrorAlert(message: "이미지 저장 실패", info: "잘못된 Data URL 형식입니다.")
            return
        }
        let base64String = String(urlString[urlString.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            self.showErrorAlert(message: "이미지 저장 실패", info: "Base64 디코딩에 실패했습니다.")
            return
        }
        do {
            try data.write(to: destination)
            DispatchQueue.main.async {
                NSSound.beep()
                
                // Notify the user exactly where the base64 image was saved
                let alert = NSAlert()
                alert.messageText = "이미지 저장 완료"
                alert.informativeText = "이미지가 다운로드 폴더에 안전하게 저장되었습니다:\n\(destination.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "확인")
                alert.runModal()
            }
        } catch {
            self.showErrorAlert(message: "이미지 저장 실패", info: error.localizedDescription)
        }
    }
    
    private func showErrorAlert(message: String, info: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = info
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }
}

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
        print("🚀 JavaScript Direct Save: Saving straight to \(destinationUrl.path)")
        
        if url.scheme == "data" {
            self.saveDataURL(url, to: destinationUrl)
        } else {
            self.downloadImage(from: url, to: destinationUrl)
        }
    }
}
