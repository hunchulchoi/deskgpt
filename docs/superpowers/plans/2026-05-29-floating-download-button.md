# Floating Download Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a bulletproof floating download button on ChatGPT's generated images with custom alert confirmations.

**Architecture:** Inject highly-resilient JavaScript in `DeskGPTViewController.swift` that runs via a `MutationObserver` and periodic polling. It binds a styled glassmorphic button to all images, bypassing OS-level gesture/alt-key interceptor issues entirely.

**Tech Stack:** Swift, AppKit, WebKit (WKWebView), JavaScript

---

### Task 1: Rewrite loadView Script with Dynamic Floating Button Injections

**Files:**
- Modify: [DeskGPTViewController.swift](file:///Users/hunchulchoi/projects/workspace/myside/gpt_exe/src/DeskGPTViewController.swift)

- [ ] **Step 1: Replace JS Injection Source Code**

Locate `loadView` inside `DeskGPTViewController.swift` and replace the `jsSource` block with the highly resilient glassmorphic floating button script.

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
                    background: rgba(15, 23, 42, 0.7) !important;
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
```

- [ ] **Step 2: Compile & Deploy App**

Run the build and deploy script:
`./build.sh && rm -rf /Applications/DeskGPT.app && cp -R build/DeskGPT.app /Applications/DeskGPT.app`
Expected: Succeeds cleanly.

- [ ] **Step 3: Commit and Push**

```bash
git add src/DeskGPTViewController.swift docs/superpowers/specs/2026-05-29-floating-download-button.md docs/superpowers/plans/2026-05-29-floating-download-button.md
git commit -m "feat: inject sleek glassmorphic floating direct save button into chat images"
git push origin main
```
