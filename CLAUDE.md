# Notes for agents working in this repo

## Before calling a PR done: check its preview on a real iPhone

CI can't catch iOS rendering bugs. In November 2026 every game froze on iOS 18 Safari: the first
frame drew, taps reached the game, the screen never updated (fixed by
`.github/scripts/render-options.js`). Nothing that runs in CI reproduced it: Chromium, Linux WebKit,
Playwright's WebKit 18 on a real Mac, and the iOS Simulator on GitHub's macOS runners (which has
no working WebGL at all) all rendered fine or not at all. Only real iPhones showed it.

So every PR that changes a game, `ui/`, the export settings, the Godot version or
`.github/scripts/` gets checked on real devices before it is called done:

1. CI deploys the PR to `https://joshprier.dev/GameTests/pr-preview/pr-<number>/` and comments the
   link on the PR. Wait for that.
2. With the BrowserStack tools, open each changed game's preview (all games, for shared changes)
   on a real iPhone on **iOS 18** and one on the **latest iOS**, with `?debug=input` on the URL.
3. Tap something that should visibly change the screen and compare screenshots before and after.
   BrowserStack can't run page scripts; to tap from the URL instead, add
   `&tap=x,y;x,y` (CSS pixels, after `tapwait` ms, default 8000; `tapgap` between taps,
   default 1500). The overlay shows the taps arriving and `GAME state changed: ...` lines.
4. The check passes only if the screen visibly changed after the tap. Taps logged in the overlay
   without the screen changing is the failure this check exists for. For a control, `?gl=nortfix`
   turns the iOS 18 fix off; on iOS 18 that page should freeze.
5. Say on the PR which devices and iOS versions were checked, and end the BrowserStack sessions.
