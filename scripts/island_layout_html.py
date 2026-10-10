#!/usr/bin/env python3
"""Draw a layout dump from the Island tests as an HTML page.

    ISLAND_LAYOUT_DIR=out lua5.1 tests/run.lua
    python3 scripts/island_layout_html.py out/open.json out/open.html

The dump is every shown frame and region with its resolved rectangle, so the
page shows where things land, not how the game would rasterise them: text is
set in a stand-in font, and icons are drawn as plain squares.
"""

import base64
import html
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "Everlook_Island" / "assets"
FONT_SIZES = {"Large": 16, "Medium": 14, "Small": 10}


def tga_to_png_data_uri(path):
    data = path.read_bytes()
    width, height, depth = struct.unpack_from("<HHB", data, 12)
    assert depth == 32, path
    rows = []
    for row in range(height):
        pixels = bytearray()
        for column in range(width):
            blue, green, red, alpha = data[18 + (row * width + column) * 4:22 + (row * width + column) * 4]
            pixels += bytes((red, green, blue, alpha))
        rows.append(b"\x00" + bytes(pixels))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    return "data:image/png;base64," + base64.b64encode(png).decode()


def rgba(color, fallback="255,255,255,1"):
    if not color or len(color) < 3:
        return f"rgba({fallback})"
    alpha = color[3] if len(color) > 3 else 1
    return f"rgba({round(color[0] * 255)},{round(color[1] * 255)},{round(color[2] * 255)},{alpha})"


def rich_text(text):
    """Colour codes (|cAARRGGBB ... |r) become spans; icon escapes become a box."""
    text = re.sub(r"\|T.*?\|t", "□", text)
    text = re.sub(r"\|A.*?\|a", "□", text)
    out, open_spans = [], 0
    position = 0
    for match in re.finditer(r"\|c([0-9a-fA-F]{8})|\|r", text):
        out.append(html.escape(text[position:match.start()]))
        if match.group(1):
            value = match.group(1)
            out.append(f'<span style="color:#{value[2:]}">')
            open_spans += 1
        elif open_spans:
            out.append("</span>")
            open_spans -= 1
        position = match.end()
    out.append(html.escape(text[position:]))
    out.append("</span>" * open_spans)
    return "".join(out)


def font_size(font):
    for key, size in FONT_SIZES.items():
        if key in font:
            return size
    return 12


def box(item, extra=""):
    return f"left:{item['x']}px;top:{item['y']}px;width:{item['w']}px;height:{item['h']}px;{extra}"


def render(items, scale):
    ring = tga_to_png_data_uri(ASSETS / "island_ring.tga")
    arrow = tga_to_png_data_uri(ASSETS / "island_arrow.tga")
    parts = []
    surface_open = False
    root = items[0]
    margin = 24
    for item in items:
        kind = item["kind"]
        if kind == "frame":
            surface_open = item["name"] == "EverlookIslandResting"
            if surface_open:
                parts.append(f'<div class="surface" style="{box(item)}"></div>')
            elif item.get("cooldown") is not None:
                fraction = max(0, min(1, item["cooldown"]))
                color = rgba(item.get("swipe") or [1, 1, 1, 1])
                parts.append(
                    f'<div class="ring" style="{box(item)};-webkit-mask-image:url({ring});mask-image:url({ring});'
                    f'background:conic-gradient({color} {fraction * 360}deg,transparent 0)"></div>'
                )
            bar = item.get("bar")
            if bar:
                span = (bar["max"] - bar["min"]) or 1
                share = max(0, min(1, (bar["value"] - bar["min"]) / span))
                parts.append(f'<div class="fill" style="{box(item)};width:{item["w"] * share}px;background:{rgba(bar["color"])}"></div>')
            if item["name"]:
                parts.append(f'<div class="frame" title="{html.escape(item["name"])}" style="{box(item)}"></div>')
            continue
        if surface_open and kind == "texture":
            continue
        if kind == "text":
            if not item["text"]:
                continue
            align = {"RIGHT": "right", "CENTER": "center"}.get(item.get("justify"), "left")
            style = box(item, f"font-size:{font_size(item['font'])}px;line-height:{item['h']}px;color:{rgba(item['color'], '245,247,250,1')};text-align:{align};opacity:{item.get('alpha', 1)}")
            parts.append(f'<div class="text" style="{style}">{rich_text(item["text"])}</div>')
        else:
            path = item["path"]
            if "island_ring" in path:
                parts.append(f'<div class="ring" style="{box(item)};-webkit-mask-image:url({ring});mask-image:url({ring});background:rgba(255,255,255,.14);opacity:{item.get('alpha', 1)}"></div>')
            elif "island_arrow" in path:
                rotation = item["rotation"]
                parts.append(
                    f'<div class="ring" style="{box(item)};-webkit-mask-image:url({arrow});mask-image:url({arrow});'
                    f'background:{rgba(item["color"])};transform:rotate({-rotation}rad)"></div>'
                )
            elif "island_corner" in path:
                continue
            elif item["atlas"] or path:
                label = html.escape(item["atlas"] or path.split("\\")[-1])
                parts.append(f'<div class="icon" title="{label}" style="{box(item)}"></div>')
            else:
                parts.append(f'<div class="fill" style="{box(item)};background:{rgba(item["color"], "255,255,255,.1")}"></div>')
    width = max(item["x"] + item["w"] for item in items if item["kind"] != "text") + margin
    height = max(item["y"] + item["h"] for item in items if item["kind"] != "text") + margin
    return f"""<!doctype html><meta charset="utf-8"><title>Island layout</title>
<style>
html{{background:#2d3a33}} body{{margin:0}}
.stage{{position:relative;margin:{margin}px;width:{width}px;height:{height}px;transform:scale({scale});transform-origin:0 0;
 font-family:'DejaVu Sans',sans-serif}}
.stage div{{position:absolute;box-sizing:border-box}}
.surface{{background:rgba(13,15,20,.96);border:1px solid rgba(255,255,255,.12);border-radius:14px;margin:0}}
.frame{{outline:1px dashed rgba(120,200,255,.18)}}
.text{{white-space:nowrap}} .icon{{background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.3);border-radius:3px}}
.ring{{-webkit-mask-size:100% 100%;mask-size:100% 100%;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat}}
</style>
<body><div class="stage" style="width:{width}px;height:{height}px">{''.join(parts)}</div>"""


def main():
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 2
    target.write_text(render(json.loads(source.read_text()), scale))


if __name__ == "__main__":
    main()
