# Chat Body Event-Driven Image Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove DeskGPT's injected image-download controls from ChatGPT's DOM while preserving image downloads through interaction-driven handlers.

**Architecture:** Keep ChatGPT's message DOM untouched and change only DeskGPT's injected JavaScript inside `DeskGPTViewController.swift`. Remove floating button CSS, button creation, and DOM observers; keep image URL lookup only on right-click or `Option + click`.

**Tech Stack:** Swift, WebKit `WKUserScript`, JavaScript DOM APIs, Node.js source-level regression test.

---

### Task 1: Add Regression Test

**Files:**
- Create: `tests/lazy_image_controls.test.js`
- Modify: none

- [ ] **Step 1: Write the failing test**

Create a Node.js test that reads `src/DeskGPTViewController.swift` and asserts:

```javascript
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'src', 'DeskGPTViewController.swift'), 'utf8');

assert(
  !source.includes('deskgpt-download-btn') &&
    !source.includes('deskgpt-download-container') &&
    !source.includes('document.head.appendChild(style)') &&
    !source.includes('appendChild(btn)'),
  'DeskGPT should not inject floating download button DOM into the ChatGPT page'
);

assert(
  !source.includes('MutationObserver') && !source.includes('IntersectionObserver'),
  'DeskGPT image download support should be event-driven instead of observing the full chat DOM'
);

assert(
  source.includes('event.altKey') && source.includes('directSaveImage.postMessage'),
  'DeskGPT should keep direct image saving via Option-click without adding DOM controls'
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node tests/lazy_image_controls.test.js`

Expected: FAIL because the current script still injects floating download button DOM.

### Task 2: Implement Event-Driven Image Downloads

**Files:**
- Modify: `src/DeskGPTViewController.swift`
- Test: `tests/lazy_image_controls.test.js`

- [ ] **Step 1: Remove injected controls**

Inside the injected JavaScript, remove:

```javascript
document.head.appendChild(style);
container.classList.add('deskgpt-download-container');
container.appendChild(btn);
new MutationObserver(...);
new IntersectionObserver(...);
```

- [ ] **Step 2: Keep image URL lookup**

Keep `resolveImageAtPoint(event)` so DeskGPT can read the image URL at the user's interaction point.

- [ ] **Step 3: Add Option-click direct save**

Add:

```javascript
function postDirectSaveImage(event) {
    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.directSaveImage) {
        return false;
    }

    var imgSrc = resolveImageAtPoint(event);
    if (!imgSrc) {
        return false;
    }

    event.preventDefault();
    event.stopPropagation();
    window.webkit.messageHandlers.directSaveImage.postMessage(imgSrc);
    return true;
}
```

- [ ] **Step 4: Keep right-click handling unchanged**

Leave `postRightClickImage`, `mousedown`, and `contextmenu` behavior intact except for routing `Option + click` to `postDirectSaveImage(event)` first.

- [ ] **Step 5: Run regression test**

Run: `node tests/lazy_image_controls.test.js`

Expected: PASS.

### Task 3: Compile Verification

**Files:**
- Modify: none

- [ ] **Step 1: Compile without installing**

Run:

```bash
swiftc src/DeskGPTViewController.swift src/DeskGPTPDFViewController.swift src/UpdateInstaller.swift src/UpdateManager.swift src/PreferencesWindowController.swift src/AppDelegate.swift src/main.swift -module-cache-path /private/tmp/deskgpt-swift-module-cache-test -o /private/tmp/DeskGPT-test -framework Cocoa -framework WebKit -framework PDFKit
```

Expected: exit code 0.
