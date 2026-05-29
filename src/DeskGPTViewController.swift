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
    
    // MARK: - WKNavigationDelegate: Intercept Downloads (macOS 11.3+)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
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
}
