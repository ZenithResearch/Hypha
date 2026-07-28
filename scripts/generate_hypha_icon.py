#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generate Hypha's original macOS icon and a matching editable SVG companion."""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
BACKGROUND_TOP = (11, 17, 14)
BACKGROUND_BOTTOM = (22, 39, 30)
GREEN = (118, 236, 165)
GREEN_DIM = (53, 145, 94)
INK = (5, 10, 7)


def draw_master() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(SIZE):
        ratio = y / (SIZE - 1)
        color = tuple(round(a + (b - a) * ratio) for a, b in zip(BACKGROUND_TOP, BACKGROUND_BOTTOM))
        for x in range(SIZE):
            pixels[x, y] = (*color, 255)

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((36, 36, 988, 988), radius=218, fill=255)
    image.putalpha(mask)
    draw = ImageDraw.Draw(image)

    # A branching hypha: one root, two stems, and four growing tips.
    branches = [
        ((512, 802), (512, 525)),
        ((512, 608), (346, 432)),
        ((512, 608), (678, 432)),
        ((346, 432), (270, 292)),
        ((346, 432), (408, 256)),
        ((678, 432), (616, 256)),
        ((678, 432), (754, 292)),
    ]
    for start, end in branches:
        draw.line((*start, *end), fill=GREEN, width=54, joint="curve")
    for x, y in ((346, 432), (512, 608), (678, 432)):
        draw.ellipse((x - 27, y - 27, x + 27, y + 27), fill=GREEN)
    for x, y in ((270, 292), (408, 256), (616, 256), (754, 292)):
        draw.ellipse((x - 45, y - 45, x + 45, y + 45), fill=GREEN)
    draw.ellipse((456, 746, 568, 858), fill=GREEN_DIM)
    draw.ellipse((482, 772, 542, 832), fill=INK)
    return image


def write_svg(path: Path) -> None:
    path.write_text(
        """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#0b110e"/><stop offset="1" stop-color="#16271e"/></linearGradient></defs>
  <rect x="36" y="36" width="952" height="952" rx="218" fill="url(#bg)"/>
  <g fill="none" stroke="#76eca5" stroke-width="54" stroke-linecap="round" stroke-linejoin="round">
    <path d="M512 802V525M512 608L346 432 270 292M346 432L408 256M512 608L678 432 616 256M678 432L754 292"/>
  </g>
  <g fill="#76eca5"><circle cx="346" cy="432" r="27"/><circle cx="512" cy="608" r="27"/><circle cx="678" cy="432" r="27"/><circle cx="270" cy="292" r="45"/><circle cx="408" cy="256" r="45"/><circle cx="616" cy="256" r="45"/><circle cx="754" cy="292" r="45"/></g>
  <circle cx="512" cy="802" r="56" fill="#35915e"/><circle cx="512" cy="802" r="30" fill="#050a07"/>
</svg>
""",
        encoding="utf-8",
    )


def generate(output: Path, svg: Path) -> None:
    master = draw_master()
    write_svg(svg)
    with tempfile.TemporaryDirectory(prefix="hypha-icon-") as temp:
        iconset = Path(temp) / "Hypha.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
                master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(iconset / name, optimize=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(output)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("Resources/ZenithOSIcon.icns"))
    parser.add_argument("--svg", type=Path, default=Path("Resources/HyphaIconSource.svg"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.svg.parent.mkdir(parents=True, exist_ok=True)
    generate(args.output, args.svg)


if __name__ == "__main__":
    main()
