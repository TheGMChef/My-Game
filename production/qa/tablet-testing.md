# Tablet testing

## What is covered
- **Touch input** (board only): one finger taps to select/target, drags a selected unit, or pans the board when
  not on a unit. Two fingers pinch to zoom and slide to pan; a second finger landing mid-drag cancels the move
  preview. Mouse and trackpad are a separate desktop path; fingers never act as a fake mouse on the board.
- **Layouts**: landscape (board left, explanation panel right) and portrait (board on top, panel docked below).
- **Sizes**: the interface is sized in CSS points, so buttons stay about 48 points across on 1x and 2x/2.25x screens.
- Emulated devices (Chromium touch emulation): iPad gen 7 landscape and portrait, iPad Pro 11 landscape,
  Galaxy Tab S4 landscape. Screenshots: `production/qa/evidence/tablet/`.

## Not covered (needs a real tablet)
- Real finger size and accuracy, palm rejection, browser gestures (Safari edge swipes), frame rate on older tablets,
  fullscreen / add-to-home-screen behaviour.

## Try it on a real tablet
1. On your computer, in the unzipped `web` folder: `python3 -m http.server 8000`
2. Find your computer's local IP (Windows: `ipconfig`, Mac: `ipconfig getifaddr en0`), e.g. 192.168.1.20.
3. Put the tablet on the same Wi-Fi and open `http://192.168.1.20:8000` in Chrome or Safari.
