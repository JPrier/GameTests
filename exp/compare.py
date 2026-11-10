#!/usr/bin/env python3
"""compare.py label a.png b.png -> prints ALIVE/FROZEN: did the middle of the screen change
between two screenshots taken a few seconds apart? The probe page redraws a growing bar and a
frame counter every frame, so a live canvas always differs; a frozen one doesn't."""
import sys
from PIL import Image, ImageChops
label, a, b = sys.argv[1:4]
A, B = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
w, h = A.size
box = (0, int(h * 0.15), w, int(h * 0.75))
diff = ImageChops.difference(A.crop(box), B.crop(box)).getbbox()
verdict = "ALIVE" if diff else "FROZEN"
line = f"| {label} | {verdict} |"
print(line)
with open(sys.argv[4] if len(sys.argv) > 4 else "/dev/null", "a") as f:
    f.write(line + "\n")
