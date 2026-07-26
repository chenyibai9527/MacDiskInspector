#!/usr/bin/env python3
from __future__ import annotations

import io
import struct
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE = PROJECT_ROOT / "Brand" / "Distribution" / "DMG-Icon-Transparent.png"
ASSET_DIR = PROJECT_ROOT / "Distribution" / "DMG"
ICONSET = ASSET_DIR / "VolumeIcon.iconset"
OUTPUT = ASSET_DIR / "VolumeIcon.icns"


def normalized_master() -> Image.Image:
    source = Image.open(SOURCE).convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("DMG icon source is fully transparent")

    subject = source.crop(bounds)
    subject.thumbnail((900, 900), Image.Resampling.LANCZOS)
    master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    origin = ((1024 - subject.width) // 2, (1024 - subject.height) // 2)
    master.alpha_composite(subject, origin)
    return master


def png_bytes(image: Image.Image, size: int) -> bytes:
    buffer = io.BytesIO()
    image.resize((size, size), Image.Resampling.LANCZOS).save(
        buffer,
        "PNG",
        optimize=True,
    )
    return buffer.getvalue()


def write_icns(master: Image.Image) -> None:
    # Modern ICNS files may store PNG payloads directly. Include both small
    # Finder representations and large Retina artwork without depending on
    # iconutil, which rejects otherwise valid iconsets on some macOS 26 builds.
    chunks = []
    for chunk_type, size in (
        (b"icp4", 16),
        (b"icp5", 32),
        (b"icp6", 64),
        (b"ic07", 128),
        (b"ic08", 256),
        (b"ic09", 512),
        (b"ic10", 1024),
        (b"ic11", 32),
        (b"ic12", 64),
        (b"ic13", 256),
        (b"ic14", 512),
    ):
        payload = png_bytes(master, size)
        chunks.append(chunk_type + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    OUTPUT.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = normalized_master()
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            ICONSET / filename,
            "PNG",
            optimize=True,
        )

    write_icns(master)
    print(OUTPUT)


if __name__ == "__main__":
    main()
