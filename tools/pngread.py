"""Minimal PNG reader for the asset tools.

The project deliberately has no third-party Python dependencies, and the texture
pack importer has to read PNGs that people get from elsewhere. This module
decodes the subset that block/item textures use: 8- and 16-bit greyscale, RGB,
palette (with an optional alpha table) and RGBA, non-interlaced. Anything exotic
(interlaced, 1/2/4-bit) raises `PngError` with a readable message instead of
producing garbage.

    width, height, pixels = read_png("stone.png")   # RGBA bytes, row major
"""

from __future__ import annotations

import struct
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Channels per pixel for each PNG colour type.
_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PngError(Exception):
    """Raised when a file is not a PNG this reader can decode."""


def _paeth(left: int, up: int, up_left: int) -> int:
    estimate: int = left + up - up_left
    distance_left: int = abs(estimate - left)
    distance_up: int = abs(estimate - up)
    distance_up_left: int = abs(estimate - up_left)
    if distance_left <= distance_up and distance_left <= distance_up_left:
        return left
    if distance_up <= distance_up_left:
        return up
    return up_left


def _unfilter(raw: bytes, width: int, height: int, channels: int, bit_depth: int) -> bytes:
    """Reverses the per-row PNG filters, returning raw sample bytes."""
    stride: int = (width * channels * bit_depth + 7) // 8
    bpp: int = max(1, (channels * bit_depth + 7) // 8)
    out = bytearray()
    previous = bytearray(stride)
    offset: int = 0
    for _row in range(height):
        if offset >= len(raw):
            raise PngError("truncated image data")
        filter_type: int = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        if len(line) != stride:
            raise PngError("truncated image row")
        offset += stride
        if filter_type == 1:
            for index in range(bpp, stride):
                line[index] = (line[index] + line[index - bpp]) & 0xFF
        elif filter_type == 2:
            for index in range(stride):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif filter_type == 3:
            for index in range(stride):
                left: int = line[index - bpp] if index >= bpp else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif filter_type == 4:
            for index in range(stride):
                left: int = line[index - bpp] if index >= bpp else 0
                up: int = previous[index]
                up_left: int = previous[index - bpp] if index >= bpp else 0
                line[index] = (line[index] + _paeth(left, up, up_left)) & 0xFF
        elif filter_type != 0:
            raise PngError(f"unknown row filter {filter_type}")
        out += line
        previous = line
    return bytes(out)


def _samples_to_rgba(samples: bytes, width: int, height: int, color_type: int,
                     bit_depth: int, palette: bytes, transparency: bytes) -> bytes:
    """Expands decoded samples into RGBA bytes."""
    pixels = bytearray(width * height * 4)
    channels: int = _CHANNELS[color_type]
    step: int = 2 if bit_depth == 16 else 1          # 16-bit: keep the high byte
    row_stride: int = width * channels * step

    for row in range(height):
        base: int = row * row_stride
        for column in range(width):
            source: int = base + column * channels * step
            if color_type == 0:                      # greyscale
                value: int = samples[source]
                alpha: int = 255
                if transparency and len(transparency) >= 2:
                    if value == struct.unpack(">H", transparency[:2])[0]:
                        alpha = 0
                red = green = blue = value
            elif color_type == 4:                    # greyscale + alpha
                red = green = blue = samples[source]
                alpha = samples[source + step]
            elif color_type == 2:                    # RGB
                red, green, blue = samples[source], samples[source + step], samples[source + 2 * step]
                alpha = 255
            elif color_type == 6:                    # RGBA
                red = samples[source]
                green = samples[source + step]
                blue = samples[source + 2 * step]
                alpha = samples[source + 3 * step]
            else:                                    # palette
                palette_index: int = samples[source] * 3
                if palette_index + 2 >= len(palette):
                    red = green = blue = 0
                else:
                    red, green, blue = palette[palette_index:palette_index + 3]
                alpha = 255
                if transparency and samples[source] < len(transparency):
                    alpha = transparency[samples[source]]
            target: int = (row * width + column) * 4
            pixels[target] = red
            pixels[target + 1] = green
            pixels[target + 2] = blue
            pixels[target + 3] = alpha
    return bytes(pixels)


def read_png(path: str) -> tuple[int, int, bytes]:
    """Reads a PNG file into `(width, height, rgba_bytes)`."""
    with open(path, "rb") as handle:
        data = handle.read()
    if not data.startswith(PNG_SIGNATURE):
        raise PngError(f"{path}: not a PNG file")

    offset: int = len(PNG_SIGNATURE)
    header: bytes | None = None
    palette: bytes = b""
    transparency: bytes = b""
    compressed = bytearray()

    while offset + 8 <= len(data):
        length, chunk_type = struct.unpack(">I4s", data[offset:offset + 8])
        offset += 8
        chunk: bytes = data[offset:offset + length]
        offset += length + 4                          # skip the CRC
        if chunk_type == b"IHDR":
            header = chunk
        elif chunk_type == b"PLTE":
            palette = chunk
        elif chunk_type == b"tRNS":
            transparency = chunk
        elif chunk_type == b"IDAT":
            compressed += chunk
        elif chunk_type == b"IEND":
            break

    if header is None:
        raise PngError(f"{path}: missing IHDR")
    width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
        ">IIBBBBB", header)
    if compression != 0 or filter_method != 0:
        raise PngError(f"{path}: unsupported compression or filter method")
    if interlace != 0:
        raise PngError(f"{path}: interlaced PNGs are not supported")
    if color_type not in _CHANNELS:
        raise PngError(f"{path}: unsupported colour type {color_type}")
    if bit_depth not in (8, 16):
        # Sub-byte images need sample unpacking before unfiltering; texture packs
        # are 8-bit, so refuse clearly instead of decoding them wrongly.
        raise PngError(f"{path}: unsupported bit depth {bit_depth} (use an 8-bit pack)")
    if width <= 0 or height <= 0:
        raise PngError(f"{path}: empty image")

    raw: bytes = zlib.decompress(bytes(compressed))
    channels: int = _CHANNELS[color_type]
    samples: bytes = _unfilter(raw, width, height, channels, bit_depth)
    return width, height, _samples_to_rgba(samples, width, height, color_type, bit_depth,
                                          palette, transparency)


def is_png(path: str) -> bool:
    try:
        with open(path, "rb") as handle:
            return handle.read(8) == PNG_SIGNATURE
    except OSError:
        return False


def resize_rgba(width: int, height: int, pixels: bytes, target: int) -> bytes:
    """Nearest-neighbour resize to `target` x `target` (used to normalise packs)."""
    if width == target and height == target:
        return pixels
    out = bytearray(target * target * 4)
    for y in range(target):
        source_y: int = min(height - 1, y * height // target)
        for x in range(target):
            source_x: int = min(width - 1, x * width // target)
            source: int = (source_y * width + source_x) * 4
            target_index: int = (y * target + x) * 4
            out[target_index:target_index + 4] = pixels[source:source + 4]
    return bytes(out)


def dominant_alpha(pixels: bytes) -> bool:
    """True when any pixel is not fully opaque, i.e. the tile needs cutout art."""
    return any(pixels[index] < 250 for index in range(3, len(pixels), 4))
