# DeskGPT Smart Direct Image Downloader Spec

이 설계 문서는 사용자가 ChatGPT 내에서 생성된 이미지를 번거로운 모달 뷰어(레이어) 팝업이나 인위적인 커스텀 메뉴 단계를 거치지 않고, 마치 브라우저의 기본 기능처럼 또는 파워 유저용 초고속 단축 기능으로 **직접 다운로드 폴더에 안전하게 저장**할 수 있도록 구현하는 사양서입니다.

---

## 1. 해결하고자 하는 문제 (Problem Statement)
1. **이질적인 메뉴명 피드백**: 기존의 `"Save Image to Downloads (DeskGPT)"`와 같은 메뉴명은 순정 macOS Safari나 Chrome 브라우저의 세련된 느낌을 해칩니다.
2. **레이어(뷰어) 팝업의 번거로움**: 채팅창에 떠 있는 이미지 썸네일을 곧바로 다운로드하고 싶으나, ChatGPT의 복잡한 투명 오버레이 z-index 구조 때문에 썸네일 우클릭이 정확히 감지되지 않고 모달 레이어를 띄운 뒤에만 저장이 수월한 한계가 존재합니다.
3. **WebKit 다운로드의 403 한계**: WKWebView 내부의 기본 "이미지 저장" 메뉴를 그대로 사용하면 WebKit 엔진의 보안 샌드박스로 인해 세션 쿠키가 전송되지 않아 다운로드가 실패(403 Forbidden)합니다.

---

## 2. 해결 방안 (Proposed Approaches)

우리는 사용자에게 가장 자연스럽고 강력한 이미지 저장 기능을 선사하기 위해 **두 가지 결합된 프리미엄 기능**을 구현합니다.

### 2.1. 방안 A: 순정 브라우저 스타일로 컨텍스트 메뉴 일치화 (Native-Style Context Menu)
커스텀 메뉴의 이질적인 텍스트(`(DeskGPT)`)를 완전히 제거하고, 사용자의 시스템 언어(한국어/영어)에 매칭되는 완전한 네이티브 브라우저 텍스트로 치환합니다.
- **한국어 macOS 환경**:
  - `Save Image to Downloads (DeskGPT)` ➔ **"다운로드 폴더에 이미지 저장"**
  - `Save Image As... (DeskGPT)` ➔ **"이미지를 다른 이름으로 저장..."**
- **영어 macOS 환경**:
  - `Save Image to Downloads (DeskGPT)` ➔ **"Save Image to Downloads"**
  - `Save Image As... (DeskGPT)` ➔ **"Save Image As..."**

### 2.2. 방안 B: Option(⌥) + 마우스 클릭 (Opt + Click) 즉시 직접 저장 기능 추가 (Ultra-Fast Direct Save)
우클릭 후 메뉴를 선택하는 단계마저 생략하고 싶어 하는 사용자를 위해, **Option(⌥) 키를 누른 상태에서 이미지를 왼쪽 클릭(L-Click)하면 즉시 아무런 팝업 창도 없이 디바이스의 다운로드 폴더(`~/Downloads`)에 초고속으로 이미지를 저장**해 주는 단축 기능을 제공합니다.
- **동작 방식**: 
  1. 사용자가 `Option` 키를 누른 상태에서 채팅창의 썸네일이나 메인 뷰어 상의 임의의 이미지를 클릭합니다.
  2. JavaScript 이벤트 리스너가 해당 클릭 좌표에 있는 이미지(`img` 또는 `canvas`)의 `src` 및 `dataURL`을 추출합니다.
  3. 추출된 데이터를 `WKScriptMessageHandler`를 통해 Cocoa(Swift) 네이티브 영역으로 전송합니다.
  4. Swift 단에서 ChatGPT 로그인 세션(쿠키)을 실어 다운로드 폴더에 직접 안전하게 저장하고 성공 효과음(`NSSound.beep()`)을 재생합니다.
- **장점**: ChatGPT의 검은색 이미지 뷰어 레이어를 켤 필요가 없으며, 팝업 창의 방해 없이 백그라운드에서 완전히 다이렉트로 저장할 수 있습니다.

---

## 3. 상세 설계 및 구현 아키텍처

### 3.1. JavaScript 단 (이벤트 주입 및 좌표 제약 극복)
웹뷰 로드 시 주입되는 전역 스크립트(`WKUserScript`)를 통해 `click` 이벤트를 가로채고 분석합니다.

```javascript
window.addEventListener('click', function(event) {
    // 1. Option 키가 눌려 있는지 감지
    if (!event.altKey) return;
    
    // 2. 클릭된 엘리먼트 또는 그 조상 중 이미지 관련 탐색
    let target = event.target;
    let imgSrc = null;
    
    // z-index로 덮어씌워진 투명 div 등까지 관통하기 위해 elementsFromPoint 활용
    let elements = document.elementsFromPoint(event.clientX, event.clientY);
    for (let el of elements) {
        if (el.tagName === 'IMG') {
            imgSrc = el.src;
            break;
        }
        if (el.tagName === 'CANVAS') {
            imgSrc = el.toDataURL();
            break;
        }
        let nestedImg = el.querySelector('img');
        if (nestedImg) {
            imgSrc = nestedImg.src;
            break;
        }
    }
    
    // 이미지를 찾았다면 브라우저의 기본 클릭 이벤트(이미지 모달 띄우기 등)를 막고 Swift 네이티브로 전송
    if (imgSrc) {
        event.preventDefault();
        event.stopPropagation();
        window.webkit.messageHandlers.directSaveImage.postMessage(imgSrc);
    }
}, true); // Use capture phase to intercept before ChatGPT reacts
```

### 3.2. Swift 네이티브 단 (`DeskGPTViewController`)
- **이벤트 핸들러 등록**: `directSaveImage` 스크립트 메시지 핸들러 등록.
- **다운로드 로직 재사용**: 기개발된 `downloadImage(from:to:)` 및 `saveDataURL(_:to:)` 함수를 연계하여 `~/Downloads`에 Chromium 규격 고유명 생성기(`getUniqueDownloadsURL`)를 통해 즉시 무음 저장.

---

## 4. 검증 계획 (Verification Plan)
1. **컨텍스트 메뉴 텍스트 정합성 테스트**: 이미지 우클릭 시 나타나는 메뉴명이 macOS Safari 순정 느낌과 일치하는지 눈으로 검증.
2. **Option+클릭 즉시 저장 작동 테스트**: 
   - 채팅 스트림에 나타난 이미지 썸네일 위에서 `Option + 클릭`을 실행했을 때, 화면의 번쩍임이나 팝업 창 없이 `NSSound` 효과음과 함께 `~/Downloads` 폴더에 즉시 저장되는지 검증.
   - ChatGPT 상단 모달 뷰어로 띄운 큰 이미지 위에서도 동일하게 `Option + 클릭`으로 깔끔히 저장되는지 검증.
3. **파일명 고유성 보존 테스트**: 중복된 이름의 이미지가 연달아 저장될 때, `image.png`, `image (1).png`, `image (2).png` 형태로 고유화되는지 검증.
