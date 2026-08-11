import os
import struct
import zlib

SIZE = 24


def write_png(path, pixels):
    raw = b""
    for row in pixels:
        raw += b"\x00" + b"".join(bytes(px) for px in row)

    def chunk(tag, data):
        value = struct.pack(">I", len(data)) + tag + data
        return value + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(png)
    print("  " + path)


def blank():
    return [[[0, 0, 0, 0] for _ in range(SIZE)] for _ in range(SIZE)]


def set_pixel(pixels, x, y, alpha=255):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        pixels[y][x] = [255, 255, 255, alpha]


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


base = r"D:\Libraries\Pixelorama\EasySparkle\assets\graphics\tools"
os.makedirs(os.path.join(base, "cursors"), exist_ok=True)
write_png(os.path.join(base, "easysparkle.png"), sparkle_icon())
write_png(os.path.join(base, "cursors", "easysparkle.png"), sparkle_cursor())
