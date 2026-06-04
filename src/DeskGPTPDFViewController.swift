import Cocoa
import PDFKit
import UniformTypeIdentifiers

class DeskGPTPDFViewController: NSViewController, NSTextFieldDelegate {
    var chunks: [String] = []
    var chunkSize: Int = 4000
    
    let fileLabel = NSTextField(labelWithString: "선택된 PDF 파일이 없습니다.")
    let sizeField = NSTextField()
    let stackView = NSStackView()
    let scrollView = NSScrollView()
    
    weak var mainViewController: DeskGPTViewController?
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 600))
        self.view = view
        
        let titleLabel = NSTextField(labelWithString: "📄 DeskGPT PDF 분할 주입기")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        let selectButton = NSButton(title: "PDF 파일 열기 (Select PDF)", target: self, action: #selector(selectPDFFile))
        selectButton.bezelStyle = .rounded
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectButton)
        
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        fileLabel.cell?.lineBreakMode = .byTruncatingMiddle
        view.addSubview(fileLabel)
        
        let configLabel = NSTextField(labelWithString: "분할 글자수 단위:")
        configLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(configLabel)
        
        sizeField.stringValue = "4000"
        sizeField.delegate = self
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeField)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            selectButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            selectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            fileLabel.centerYAnchor.constraint(equalTo: selectButton.centerYAnchor),
            fileLabel.leadingAnchor.constraint(equalTo: selectButton.trailingAnchor, constant: 12),
            fileLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            configLabel.topAnchor.constraint(equalTo: selectButton.bottomAnchor, constant: 12),
            configLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            sizeField.centerYAnchor.constraint(equalTo: configLabel.centerYAnchor),
            sizeField.leadingAnchor.constraint(equalTo: configLabel.trailingAnchor, constant: 8),
            sizeField.widthAnchor.constraint(equalToConstant: 80),
            
            scrollView.topAnchor.constraint(equalTo: sizeField.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
    
    @objc func selectPDFFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.pdf]
        
        openPanel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = openPanel.url else { return }
            self.fileLabel.stringValue = url.lastPathComponent
            self.processPDF(at: url)
        }
    }
    
    func processPDF(at url: URL) {
        guard let document = PDFDocument(url: url) else {
            fileLabel.stringValue = "PDF 읽기 실패"
            return
        }
        
        var fullText = ""
        let pageCount = document.pageCount
        for i in 0..<pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                fullText += pageText + "\n"
            }
        }
        
        if let size = Int(sizeField.stringValue), size > 100 {
            chunkSize = size
        } else {
            chunkSize = 4000
            sizeField.stringValue = "4000"
        }
        
        chunks = chunkText(fullText, size: chunkSize)
        updateChunksUI()
    }
    
    func chunkText(_ text: String, size: Int) -> [String] {
        var result: [String] = []
        var current = text
        
        while !current.isEmpty {
            let chunkIndex = current.index(current.startIndex, offsetBy: size, limitedBy: current.endIndex) ?? current.endIndex
            let chunk = String(current[current.startIndex..<chunkIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                result.append(chunk)
            }
            current = String(current[chunkIndex...])
        }
        return result
    }
    
    func updateChunksUI() {
        // Clear old list view items
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        if chunks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "추출된 텍스트 조각이 없습니다.")
            stackView.addArrangedSubview(emptyLabel)
            return
        }
        
        for (index, chunk) in chunks.enumerated() {
            let container = NSView()
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            container.layer?.cornerRadius = 8
            container.translatesAutoresizingMaskIntoConstraints = false
            
            let label = NSTextField(labelWithString: "🧩 조각 [\(index + 1) / \(chunks.count)]  (\(chunk.count) 자)")
            label.font = NSFont.boldSystemFont(ofSize: 12)
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            
            let previewText = String(chunk.prefix(80)).replacingOccurrences(of: "\n", with: " ") + "..."
            let preview = NSTextField(labelWithString: previewText)
            preview.font = NSFont.systemFont(ofSize: 11)
            preview.textColor = .secondaryLabelColor
            preview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(preview)
            
            let injectBtn = NSButton(title: "ChatGPT 주입", target: self, action: #selector(injectChunk(_:)))
            injectBtn.tag = index
            injectBtn.bezelStyle = .rounded
            injectBtn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(injectBtn)
            
            let copyBtn = NSButton(title: "복사", target: self, action: #selector(copyChunk(_:)))
            copyBtn.tag = index
            copyBtn.bezelStyle = .rounded
            copyBtn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(copyBtn)
            
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: 400),
                container.heightAnchor.constraint(equalToConstant: 75),
                
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                
                preview.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                
                injectBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                injectBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                
                copyBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                copyBtn.trailingAnchor.constraint(equalTo: injectBtn.leadingAnchor, constant: -8)
            ])
            
            stackView.addArrangedSubview(container)
        }
        
        // Force document size recalculation
        stackView.layout()
    }
    
    @objc func injectChunk(_ sender: NSButton) {
        let index = sender.tag
        guard index < chunks.count else { return }
        let chunkText = chunks[index]
        
        if let mainVC = mainViewController {
            mainVC.view.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            let prompt = """
            [문서 분할 분석 - 조각 \(index + 1)/\(chunks.count)]
            아래 전달하는 문서 조각을 읽고 기억해 주세요. (질문은 마지막에 이뤄집니다):
            
            ---
            \(chunkText)
            """
            mainVC.injectTextIntoChat(prompt)
        }
    }
    
    @objc func copyChunk(_ sender: NSButton) {
        let index = sender.tag
        guard index < chunks.count else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(chunks[index], forType: .string)
        NSSound.beep()
    }
}
