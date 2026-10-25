#!/usr/bin/env python3
"""Read-only audit of prepared character PNGs; stdout JSON, no artwork changes.

Requires Pillow. Checks decoding, PNG format, optional exact size, nonempty
foreground and transparent background. Anatomy, pivot, packing and animation
quality require scene inspection; this audit cannot establish them.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path


def audit_file(path: Path, expected_size: tuple[int, int] | None, image_module,
               cell_size: tuple[int, int] | None = None, max_colors: int | None = None) -> dict:
    result = {"path": str(path.resolve()), "errors": []}
    errors = result["errors"]
    try:
        data = path.read_bytes()
        result["sha256"] = hashlib.sha256(data).hexdigest()
        with image_module.open(io.BytesIO(data)) as image:
            image.load()
            result["format"] = image.format
            result["mode"] = image.mode
            result["size"] = list(image.size)
            if image.format != "PNG":
                errors.append("Expected PNG image data.")
            if expected_size is not None and image.size != expected_size:
                errors.append(f"Expected size {expected_size}, got {image.size}.")
            rgba = image.convert("RGBA")
            alpha = rgba.getchannel("A")
            histogram = alpha.histogram()
            result["alpha_bbox"] = alpha.getbbox()
            result["transparent_pixels"] = histogram[0]
            result["opaque_pixels"] = histogram[255]
            result["partial_alpha_pixels"] = sum(histogram[1:255])
            if result["alpha_bbox"] is None:
                errors.append("Image contains no visible foreground.")
            if result["transparent_pixels"] == 0:
                errors.append("Image has no fully transparent background pixels.")
            if cell_size is not None:
                if image.width % cell_size[0] or image.height % cell_size[1]:
                    errors.append(f"Image size is not divisible by cell size {cell_size}.")
                else:
                    result["cell_grid"] = [image.width // cell_size[0], image.height // cell_size[1]]
            if max_colors is not None:
                # Count visible RGB colours, not each alpha variant of a colour.
                colors = {color[:3] for _, color in rgba.getcolors(rgba.width * rgba.height) if color[3] > 0}
                result["visible_rgb_colors"] = len(colors)
                if len(colors) > max_colors:
                    errors.append(f"Visible colour count {len(colors)} exceeds {max_colors}.")
    except (OSError, ValueError, image_module.DecompressionBombError) as exc:
        errors.append(f"Cannot read image: {exc}")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--cell-size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--max-colors", type=int, help="Optional visible RGB colour budget.")
    parser.add_argument("paths", type=Path, nargs="+", help="Explicit PNG file paths.")
    args = parser.parse_args(argv)
    if args.size is not None and any(value <= 0 for value in args.size):
        parser.error("--size requires positive dimensions")
    if args.cell_size is not None and any(value <= 0 for value in args.cell_size):
        parser.error("--cell-size requires positive dimensions")
    if args.max_colors is not None and args.max_colors <= 0:
        parser.error("--max-colors must be positive")
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required; use the configured workspace Python runtime.", file=sys.stderr)
        return 2
    size = tuple(args.size) if args.size is not None else None
    cell_size = tuple(args.cell_size) if args.cell_size is not None else None
    results = [audit_file(path, size, Image, cell_size, args.max_colors) for path in args.paths]
    failures = sum(bool(result["errors"]) for result in results)
    print(json.dumps({"files": results, "failures": failures}, indent=2, ensure_ascii=True))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
