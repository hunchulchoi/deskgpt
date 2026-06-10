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
