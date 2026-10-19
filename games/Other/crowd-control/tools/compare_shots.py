#!/usr/bin/env python3
"""Visual regression for Crowd Control screenshot checkpoints (scripts/capture.gd).

  compare_shots.py approve SHOTS_DIR BASELINE_DIR   write half-size baselines from new captures
  compare_shots.py check   SHOTS_DIR BASELINE_DIR [--out FAILED_DIR]

Images are compared at half size so small renderer differences (anti-aliasing, font hinting,
software vs GPU rasterisers) do not count. A checkpoint fails when the mean absolute difference or
the share of strongly different pixels exceeds the tolerance. Pure Python (no Pillow) so it runs on
a bare CI image.
"""
import pathlib
import shutil
import struct
import sys
import zlib

MEAN_TOL = 6.0        # mean absolute channel difference (0..255)
STRONG = 48           # a pixel channel differing by more than this is "strongly different"
STRONG_TOL = 0.05     # max share of strongly different pixels


def read_png(path):
    data = pathlib.Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        ln, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and ctype in (2, 6) and interlace == 0, f"{path}: unsupported PNG format"
            bpp = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    # to RGB
    out = []
    for r in rows:
        out.append(bytes(r[k] for k in range(len(r)) if k % bpp < 3))
    return w, h, out


def half(w, h, rows):
    w2, h2 = w // 2, h // 2
    out = []
    for y in range(h2):
        a, b = rows[2 * y], rows[2 * y + 1]
        line = bytearray(w2 * 3)
        for x in range(w2):
            for ch in range(3):
                k1 = (2 * x) * 3 + ch
                k2 = (2 * x + 1) * 3 + ch
                line[x * 3 + ch] = (a[k1] + a[k2] + b[k1] + b[k2]) // 4
        out.append(bytes(line))
    return w2, h2, out


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    pathlib.Path(path).write_bytes(png)


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("approve", "check"):
        print(__doc__)
        return 2
    mode, shots, base = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    out = pathlib.Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else None
    if mode == "approve":
        base.mkdir(parents=True, exist_ok=True)
        for p in sorted(shots.glob("*.png")):
            write_png(base / p.name, *half(*read_png(p)))
            print("approved", p.name)
        return 0
    baselines = sorted(base.glob("*.png"))
    if not baselines:
        print(f"no baselines in {base}: nothing was compared (run 'approve' first)")
        return 1
    failed = 0
    for b in baselines:
        s = shots / b.name
        if not s.exists():
            print(f"MISSING {b.name}")
            failed += 1
            continue
        w, h, new = half(*read_png(s))
        bw, bh, old = read_png(b)
        if (w, h) != (bw, bh):
            print(f"SIZE    {b.name}: {w}x{h} vs baseline {bw}x{bh}")
            failed += 1
            continue
        total = strong = 0
        for r1, r2 in zip(new, old):
            for x, y in zip(r1, r2):
                d = abs(x - y)
                total += d
                strong += d > STRONG
        n = w * h * 3
        mean, share = total / n, strong / n
        ok = mean <= MEAN_TOL and share <= STRONG_TOL
        print(f"{'ok    ' if ok else 'DIFF  '} {b.name}: mean {mean:.2f}, strong {share:.3%}")
        if not ok:
            failed += 1
            if out:
                out.mkdir(parents=True, exist_ok=True)
                shutil.copy(s, out / b.name)
                shutil.copy(b, out / ("baseline_" + b.name))
    print(f"{failed} checkpoint(s) differ" if failed else "all checkpoints match")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
