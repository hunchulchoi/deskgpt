# Chat Body Event-Driven Image Downloads Design

## Goal

Reduce scroll jank in long ChatGPT conversations by removing DeskGPT's injected image-download DOM controls.

## Problem

DeskGPT injected JavaScript into ChatGPT to add floating image download controls. Even when batched or lazy, that approach still adds CSS, buttons, observers, and DOM work to a page ChatGPT already manages with React. In long conversations, extra DOM work can add avoidable scroll pressure.

## Approach

Keep ChatGPT's own message DOM intact. DeskGPT will not remove, hide, virtualize, or decorate ChatGPT messages because that risks breaking React state, scroll restoration, and ongoing responses.

DeskGPT will use event-driven image downloads:

- Remove floating download button CSS and button injection.
- Remove `MutationObserver` and `IntersectionObserver` use for image controls.
- Keep right-click image handling because it reads the image under the cursor only at interaction time.
- Add `Option + click` direct image save by reading the image under the cursor and posting the URL to Swift's existing `directSaveImage` handler.

## Success Criteria

- No DeskGPT floating download button DOM or CSS is injected into ChatGPT.
- No image-download `MutationObserver` or `IntersectionObserver` remains.
- Right-click image menu still works.
- `Option + click` directly saves the image under the cursor.
- The app still compiles with the updated injected script.

## Testing

Add a lightweight source-level regression test that checks the injected script no longer adds download button DOM, no longer observes the chat DOM for image controls, and still includes `Option + click` direct-save support. Run that test before and after implementation, then compile the Swift app sources.
