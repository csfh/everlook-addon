#!/usr/bin/env python3
"""Generate Everlook's original, tintable Island surface textures."""

import math
from pathlib import Path
import struct


def tga(path, size, alpha):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            coverage = sum(alpha(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)
                           for sy in range(4) for sx in range(4)) / 16
            pixels.extend((255, 255, 255, round(coverage * 255)))
    path.write_bytes(header + pixels)


def arrow(x, y):
    # Tip at the top. The head widens downward, then a narrow shaft.
    if 2 <= y <= 16 and abs(x - 16) <= (y - 2) / 14 * 13:
        return 1.0
    if 15 <= y <= 29 and abs(x - 16) <= 2.5:
        return 1.0
    return 0.0


def ring(x, y):
    # A circle 62 wide with its middle cut out, 8 thick, for the progress rings.
    distance = math.hypot(x - 32, y - 32)
    return 1.0 if 23 <= distance <= 31 else 0.0


def main():
    assets = Path(__file__).resolve().parents[1] / "Everlook_Island" / "assets"
    tga(assets / "island_corner.tga", 32,
        lambda x, y: float(math.hypot(32 - x, 32 - y) <= 32))
    tga(assets / "island_white.tga", 2, lambda x, y: 1)
    tga(assets / "island_arrow.tga", 32, arrow)
    tga(assets / "island_ring.tga", 64, ring)


if __name__ == "__main__":
    main()
