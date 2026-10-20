#!/usr/bin/env python3
"""Draw the app icon and README placeholder frames. No third-party packages."""
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixel) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def rounded(x, y, w, h, radius, left, top, width, height):
    if not (left <= x < left + width and top <= y < top + height):
        return False
    cx = min(max(x, left + radius), left + width - radius - 1)
    cy = min(max(y, top + radius), top + height - radius - 1)
    dx = x - cx
    dy = y - cy
    return dx * dx + dy * dy <= radius * radius


def blend(base, color, alpha):
    return tuple(int(base[i] * (1 - alpha) + color[i] * alpha) for i in range(3)) + (255,)


def icon(size: int):
    def pixel(x, y):
        # Map into a 0..1 square.
        nx = (x + 0.5) / size
        ny = (y + 0.5) / size
        background = (17, 17, 17, 255)
        # Rounded-rect mask.
        margin = 0.08
        radius = 0.22
        if not inside_round(nx, ny, margin, margin, 1 - 2 * margin, 1 - 2 * margin, radius):
            return (0, 0, 0, 0)
        # Speaker: a disc and a short base.
        cx, cy, r = 0.50, 0.44, 0.16
        if (nx - cx) ** 2 + (ny - cy) ** 2 <= r * r:
            inner = (nx - cx) ** 2 + (ny - cy) ** 2 <= (r * 0.38) ** 2
            return (17, 17, 17, 255) if inner else (244, 244, 244, 255)
        if abs(nx - 0.50) <= 0.11 and abs(ny - 0.70) <= 0.025:
            return (244, 244, 244, 255)
        return background

    return pixel


def inside_round(nx, ny, left, top, width, height, radius):
    if not (left <= nx <= left + width and top <= ny <= top + height):
        return False
    cx = min(max(nx, left + radius), left + width - radius)
    cy = min(max(ny, top + radius), top + height - radius)
    return (nx - cx) ** 2 + (ny - cy) ** 2 <= radius * radius


def frame(kind: str):
    w, h = 1200, 760

    def pixel(x, y):
        bg = (255, 255, 255, 255)
        card = (244, 244, 244, 255)
        ink = (20, 20, 20, 255)
        mute = (210, 210, 210, 255)
        if kind == "menu":
            # Centered popover on a light gray field.
            if not inside_round(x, y, 390, 40, 420, 680, 28):
                return (232, 232, 232, 255)
            if inside_round(x, y, 418, 68, 364, 280, 16):
                return ink if ((x - 600) ** 2 + (y - 200) ** 2) < 70 ** 2 else card
            return bg
        # Main window.
        if x < 360:
            if inside_round(x, y, 28, 150, 304, 86, 18):
                return (236, 236, 236, 255) if kind == "rooms" else card
            if inside_round(x, y, 28, 248, 304, 86, 18):
                return card
            if inside_round(x, y, 28, 346, 304, 86, 18):
                return card
            return bg
        if kind == "now-playing":
            if inside_round(x, y, 470, 90, 420, 420, 18):
                return ink if ((x - 680) ** 2 + (y - 300) ** 2) < 90 ** 2 else card
            if 470 <= x <= 760 and 540 <= y <= 556:
                return ink if x < 620 else mute
        return bg

    return w, h, pixel


def main():
    write_png(ROOT / "Sources/SonosApp/Resources/AppIcon.png", 512, 512, icon(512))
    for name in ("rooms", "now-playing", "menu-bar"):
        width, height, pixel = frame("menu" if name == "menu-bar" else name)
        write_png(ROOT / "docs/screenshots" / f"{name}.png", width, height, pixel)
    print("wrote icon and placeholders")


if __name__ == "__main__":
    main()
