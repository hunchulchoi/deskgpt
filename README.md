# 📄 DeskGPT: Standalone macOS ChatGPT Application

<p align="center">
  <img src="https://raw.githubusercontent.com/hunchulchoi/deskgpt/main/.github/assets/icon.png" width="160" height="160" alt="DeskGPT Flat App Icon" onerror="this.src='https://github.com/hunchulchoi/deskgpt/raw/main/build/DeskGPT.app/Contents/Resources/AppIcon.icns'; this.onerror=null;" />
</p>

**DeskGPT** is an ultra-lightweight, premium standalone macOS application that wraps `https://chatgpt.com` in a native Cocoa frame.

Unlike bulky Electron-based or Chromium-based wrappers that consume hundreds of megabytes of RAM, DeskGPT is built directly on the native **Cocoa (AppKit)** framework and **WebKit (WKWebView)** engine. The compiled binary is **less than 1MB in size**, consumes minimal system resources, and launches instantly.

---

## ✨ Key Features

* **Permanent Session Persistence**: Integrates the default persistent website data store (`WKWebsiteDataStore.default()`) so that cookies, local storage, and your ChatGPT login sessions remain securely saved across restarts.
* **Bot Gate Bypass**: Injects standard modern macOS Safari User Agents to prevent ChatGPT / Cloudflare security gates from blocking the embedded webview.
* **Always on Top (Floating Window) ⭐️**: Toggles floating window levels via shortcut (`Cmd + Shift + T`) or the View menu, allowing you to keep ChatGPT visible in a corner of your screen while writing code or documents.
* **PDF Chunker & Smart Injector 📁**: Solves the context-limit and long-document prompt issues. Opens a native floating assistant window (`Cmd + Shift + P`) powered by macOS native **`PDFKit`**. It extracts text from any PDF with blazing-fast speed, splits it into logic chunks (default: 4,000 characters), and automatically injects them into the ChatGPT prompt field with custom instructions—fully triggering React input detection.
* **Native File Uploads & Downloads**: Seamlessly integrates macOS native save panels (`NSSavePanel`) and open panels (`NSOpenPanel`) for file uploads (document analysis) and generated file downloads (code files, CSVs, images).
* **Native Navigation & Zooming**: Built-in standard browser keyboard mappings: Reload (`Cmd+R`), Go Back (`Cmd+[`), Go Forward (`Cmd+]`), and page zooming (`Cmd+=` / `Cmd+-` / `Cmd+0`).
* **Cache & Session Purging**: Provides an emergency "Reset Session & Restart" option under the Help menu to wipe cookies, caches, and service workers cleanly in case of connectivity or auth errors.

---

## 📂 File Structure

```text
├── src/
│   ├── main.swift             # App bootstrap, activation policy configuration, and event run loop
│   ├── AppDelegate.swift      # Application lifecycle, system menu bindings, and direct NSWindow management
│   ├── DeskGPTViewController.swift # Core WKWebView setup, session preservation, native file panels, and JS injector
│   ├── DeskGPTPDFViewController.swift # PDFKit high-speed text extraction, chunking, and clipboard/chat injectors
│   └── Info.plist             # App metadata bundle configuration (AppIcon mapping, system version targets)
├── build.sh                   # One-touch compilation & App packaging script (automates sips and iconutil)
├── README.md                  # Project documentation (English)
└── .gitignore                 # Exclusion configuration for build artifacts and OS caches
```

---

## 🛠️ Build & Installation (One-Touch Package)

If you have Xcode Command Line Tools installed (which includes the standard `swiftc` compiler), you can compile and package the application natively in seconds:

1. **Navigate to the Repository**:
   ```bash
   cd gpt_exe
   ```

2. **Run the Build Script**:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```
   *This script automatically resizes the high-resolution flat PNG icon into standard macOS icon sizes using `sips`, packages it into `AppIcon.icns` using `iconutil`, compiles all Swift source files, and produces a ready-to-run `build/DeskGPT.app` bundle.*

3. **Launch the App**:
   ```bash
   open build/DeskGPT.app
   ```

> [!TIP]
> Drag and drop the compiled `DeskGPT.app` into your macOS `/Applications` (Applications) folder. Once moved, it integrates fully with your macOS system, making it searchable via Spotlight Search (`Cmd + Space -> DeskGPT`) and launchable directly from Launchpad!

---

## 🔮 Future Roadmap (On-Device RAG Vision)

DeskGPT's native lightweight architecture is highly extensible for advanced offline feature additions:
* **Fully Private On-Device Embeddings**: Bundling an offline, CoreML-optimized multilingual embedding model (like `Multilingual-MiniLM`) using Apple Silicon's Neural Engine (ANE) for 100% free offline semantic indexing.
* **Category-based Multi-VectorDB**: Integrating a lightweight local SQLite database framework (`sqlite-vss`) in `Library/Application Support` to allow secure, air-gapped category-based document partitioning.
