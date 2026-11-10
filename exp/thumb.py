#!/usr/bin/env python3
"""Print small JPEG thumbnails as base64 log lines (artifacts aren't reachable from the agent)."""
import base64, io, sys
from PIL import Image
for f in sys.argv[1:]:
    im = Image.open(f).convert("RGB"); im.thumbnail((240, 520))
    b = io.BytesIO(); im.save(b, "JPEG", quality=60)
    print(f"THUMB {f} {base64.b64encode(b.getvalue()).decode()}")
