# Performance Bridge: app icon and menu-bar glyph

Design "1q‴", chosen on 2026-10-30: a single-tower, self-anchored suspension span (after the
outline of the San Francisco–Oakland Bay Bridge's east span, stylized), whose hangers are fader
slots, at night over water. The amber (#FFB13D) is also the app's accent color.

`make_icon.py` holds the geometry and writes every SVG here (standard library only):

| Folder | What | Used for |
|---|---|---|
| `master/` | Full-canvas 1024 × 1024 layers: `1-sky`, `2-reflection`, `3-waves`, `4-bridge`, `5-faders`, and `composite` | The layered icon format of macOS 26 and later (import into Icon Composer, which makes the light, dark, clear, and tinted styles) |
| `legacy/` | Shaped icons with a drop shadow: `large` (with the reflection and shaded caps), `medium` (plain, lighter and thicker deck), `px32` and `px16` (drawn on the pixel grid) | `AppIcon.iconset`, for an `.icns` |
| `AppIcon.iconset/` | PNGs rendered from `legacy/`: 16 from `px16`; 32 from `px32`; 64 from `medium`; 128 and up from `large` | `iconutil -c icns AppIcon.iconset` on a Mac |
| `menubar/` | `MenuBarIcon.svg`, an 18 × 18 point one-color template glyph (deck, tower, cables, three thin hangers), and its PNGs | The menu-bar item (copied into `App/PerformanceBridge/Resources/`) |

Rules the design keeps:

- An amber cable appears only where faders could plausibly sit under it, and it hangs as a real
  cable would: a parabola with a vertical axis, its low point at the deck anchor.
- The tower is drawn two to three times taller, relative to the spans, than the real one, so the
  bridge reads at small sizes.
- The reflection, waterline, and shaded caps appear at 128 px and up; 32 and 64 px are plain; 16 px
  has its own drawing.
- The About window shows the icon at 128 points (the 256 px art), large enough for the details.
- The dark appearance uses the same colors as the default (Adam, 2026-10-30): set it so in Icon
  Composer rather than letting it darken the sky.
- The Clear and Tinted styles leave out the wave lines (`3-waves`), which look odd there (Adam).
- No fader caps at 16 px or in the menu-bar glyph: at those sizes they read as dots (Adam).

Open points, to check on a Mac:

- The icon outline in `legacy/` is a superellipse that approximates Apple's shape; Apple's template
  (Apple Design Resources) is the reference.
- That the macOS 26 layers should fill the whole canvas, and how much margin the tower top needs,
  is an inference; Icon Composer's preview settles it.

To regenerate: `python3 make_icon.py`, then render each SVG with `node render.js <in.svg> <out.png>
<pixels>` (Playwright with Chromium) or any SVG renderer.
