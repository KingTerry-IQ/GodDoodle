# God Doodle - TempleOS Replica

A Godot 4 recreation of Terry A. Davis' "God Doodle" (Shift+F6) from TempleOS. Themed for the IQ Labs $IQ ecosystem (green CRT style, logo, "Powered by $IQ").

## How to use

1. Open the project in Godot 4.3+ (or run the exported binary).
2. The app starts with a blank white canvas.
3. **Press SPACE repeatedly** — a live ms timestamp at the top (bare universe wall-clock milliseconds, no commas/desc) shows real time. Each press feeds "divine" entropy from the exact timing of your keypresses into the God bit FIFO. Fits $IQ ecosystem.
4. Watch God draw: red geometric primitives (ellipses, circles, borders, lines) appear, followed by flood fills in black/gray/white, then a smoothing pass (3 layers total).
5. During drawing you can also:
   - Press 0-9 for manual smooth passes.
   - Press ENTER to clear the canvas (like original \n behavior).
6. When finished ("Doodle complete..." style message):
   - SHIFT+ESC = discard and start over (art cleared).
   - Ctrl+S = export/save the PNG.
   - Note: After "Doodle complete", SPACE does nothing (to prevent accidental clear while spamming to finish). You must explicitly SHIFT+ESC=discard (then SPACE for new), or Ctrl+S=save/export. Plain ESC does nothing (accept is redundant with save). (Matches "save or discard before new".)
7. **Export**: Ctrl+S to save the 640×480 image as PNG (no separate accept needed). A timestamped filename is suggested.
8. **The puppet**: A bare ms timestamp (universe time) is shown at the top. Press SPACE timed to it — cosmic timing is the puppetry. $IQ ecosystem themed.

## Fidelity to original

- Bit consumption, GOD_GOOD_BITS (24), coordinate math, switch cases (ellipse/circle/border/line), flood positions, and 3-layer + smooth(3) exactly ported from `Adam/God/GodDoodle.HC`.
- Uses a 16-color EGA-style palette (RED outlines, then BLACK/DKGRAY/LTGRAY/WHITE fills).
- Smoothing is a per-pixel dominant-neighbor filter over a (2*num+1) window using a copy buffer (identical behavior).
- Interactive puppet experience via SPACE mashing timed against the visible bare ms universe timestamp (your press timing provides the entropy). $IQ themed.

## Export

The exported PNG is full resolution 640×480 using the internal indexed colors mapped to RGB. You can post-process or upscale as desired.

## Credits / Tribute

Faithful tribute to Terry A. Davis and TempleOS. The original source lives in the TempleOS distribution under `Adam/God/GodDoodle.HC` (and supporting Gr* rasterizer + GodExt).

"$IQ Doodle - press SPACE to generate."

Enjoy making art with the Holy Spirit.
