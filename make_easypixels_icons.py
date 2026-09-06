"""Generate the tool + cursor icons for EasyPixels (gradient line and sparkle)."""

import os
import struct
import zlib

SIZE = 24


def write_png(path, pixels):
    """pixels: list of rows, each row a list of (r, g, b, a) tuples."""
    raw = b""
    for row in pixels:
        raw += b"\x00" + b"".join(bytes(px) for px in row)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("  " + path)


def blank():
    return [[[0, 0, 0, 0] for _ in range(SIZE)] for _ in range(SIZE)]


def set_pixel(pixels, x, y, alpha=255):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        pixels[y][x] = [255, 255, 255, alpha]


def bresenham(x0, y0, x1, y1):
    points = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        points.append((x0, y0))
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
    return points


def gradient_line(thickness=3):
    """White line whose alpha ramps from faint to solid, so it reads as a
    gradient under any theme tint Pixelorama applies to tool icons."""
    px = blank()
    line = bresenham(4, 19, 19, 4)
    last = len(line) - 1
    for i, (x, y) in enumerate(line):
        t = i / last
        alpha = int(40 + 215 * t)
        for oy in range(thickness):
            for ox in range(thickness):
                nx, ny = x + ox - thickness // 2, y + oy - thickness // 2
                if 0 <= nx < SIZE and 0 <= ny < SIZE:
                    px[ny][nx] = [255, 255, 255, alpha]
    # Solid endpoint markers so the two picked pixels read as the point of it.
    for cx, cy in ((4, 19), (19, 4)):
        for oy in range(-2, 3):
            for ox in range(-2, 3):
                if abs(ox) == 2 or abs(oy) == 2:
                    nx, ny = cx + ox, cy + oy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE:
                        px[ny][nx] = [255, 255, 255, 255]
    return px


def gradient_cursor():
    """Cursor icon: a small crosshair marking the pixel being picked."""
    px = blank()
    c = SIZE // 2
    for i in range(SIZE):
        if abs(i - c) > 2:
            px[c][i] = [255, 255, 255, 255]
            px[i][c] = [255, 255, 255, 255]
    return px


def sparkle_icon():
    pixels = blank()
    center = 11
    for offset in range(-9, 10):
        reach = abs(offset)
        thickness = 2 if reach < 3 else 1
        alpha = 255 if reach < 6 else 175
        for cross in range(-thickness + 1, thickness):
            set_pixel(pixels, center + cross, center + offset, alpha)
            set_pixel(pixels, center + offset, center + cross, alpha)
    for offset in range(-4, 5):
        set_pixel(pixels, center + offset, center + offset, 210)
        set_pixel(pixels, center + offset, center - offset, 210)
    for x, y in ((4, 5), (18, 17), (18, 4)):
        set_pixel(pixels, x, y)
        set_pixel(pixels, x - 1, y, 180)
        set_pixel(pixels, x + 1, y, 180)
        set_pixel(pixels, x, y - 1, 180)
        set_pixel(pixels, x, y + 1, 180)
    return pixels


def sparkle_cursor():
    pixels = blank()
    center = 11
    for offset in range(-7, 8):
        alpha = 255 if abs(offset) < 5 else 150
        set_pixel(pixels, center, center + offset, alpha)
        set_pixel(pixels, center + offset, center, alpha)
    for offset in range(-3, 4):
        set_pixel(pixels, center + offset, center + offset, 210)
        set_pixel(pixels, center + offset, center - offset, 210)
    return pixels


base = r"D:\Libraries\Pixelorama\EasyPixels\assets\graphics\tools"
os.makedirs(os.path.join(base, "cursors"), exist_ok=True)
write_png(os.path.join(base, "gradientline.png"), gradient_line())
write_png(os.path.join(base, "cursors", "gradientline.png"), gradient_cursor())
write_png(os.path.join(base, "easysparkle.png"), sparkle_icon())
write_png(os.path.join(base, "cursors", "easysparkle.png"), sparkle_cursor())
