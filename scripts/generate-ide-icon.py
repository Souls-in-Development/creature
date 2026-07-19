#!/usr/bin/env python3
"""Generate Creature.app's icon from the app's own theme colours.

Writes packaging/ide/icon-1024.png (the master), then the caller turns it into
packaging/ide/AppIcon.icns via sips + iconutil (see the commands at the bottom).

Kept as a script so the icon is reproducible, not an opaque committed binary.
Requires Pillow:  python3 -m pip install pillow
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

# Straight from Sources/CreatureIDE/Theme.swift.
INK = (10, 10, 15, 255)
TEAL = (94, 234, 212, 255)
PAPER = (237, 233, 216, 255)

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "packaging" / "ide"
MASTER = OUT_DIR / "icon-1024.png"
ICNS = OUT_DIR / "AppIcon.icns"

ICONSET_SIZES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def draw_master() -> None:
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # macOS-style rounded square with a small margin.
    margin = int(S * 0.09)
    radius = int(S * 0.225)
    d.rounded_rectangle([margin, margin, S - margin, S - margin], radius=radius, fill=INK)

    # Teal ring — the "living / earned-green pulse" motif.
    cx, cy = S // 2, int(S * 0.47)
    r = int(S * 0.235)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=TEAL, width=int(S * 0.028))

    # The terminal prompt chevron "›" — the CLI's prompt and the chat input.
    cw, ch, lw = int(S * 0.16), int(S * 0.15), int(S * 0.05)
    x0 = cx - cw // 2
    d.line([(x0, cy - ch), (x0 + cw, cy), (x0, cy + ch)], fill=TEAL, width=lw, joint="curve")

    # Paper underscore — the cursor of a living terminal.
    uw, uy = int(S * 0.20), int(S * 0.70)
    d.rounded_rectangle([cx - uw // 2, uy, cx + uw // 2, uy + int(S * 0.022)],
                        radius=int(S * 0.011), fill=PAPER)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img.save(MASTER)
    print(f"wrote {MASTER}")


def build_icns() -> None:
    """Build AppIcon.icns from the master via sips + iconutil (macOS only)."""
    if sys.platform != "darwin":
        print("skipping .icns (needs macOS iconutil); master PNG written")
        return
    iconset = OUT_DIR / "AppIcon.iconset"
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    iconset.mkdir()
    for name, size in ICONSET_SIZES:
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(MASTER), "--out", str(iconset / name)],
            check=True, stdout=subprocess.DEVNULL,
        )
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    print(f"wrote {ICNS}")


if __name__ == "__main__":
    draw_master()
    build_icns()
