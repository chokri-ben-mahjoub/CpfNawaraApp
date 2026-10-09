"""Generates the PuitsTrack app icon (derrick silhouette) with Pillow.

Run once with: python tool/generate_icon.py
Produces:
  assets/icon/icon.png            (1024x1024, opaque navy bg) -> app_icon
  assets/icon/icon_foreground.png (1024x1024, transparent bg) -> Android adaptive icon foreground
"""

from PIL import Image, ImageDraw

SIZE = 1024
NAVY = (11, 30, 45, 255)       # #0B1E2D
ACCENT = (255, 122, 51, 255)   # #FF7A33
WHITE = (247, 243, 237, 255)


def draw_derrick(draw: ImageDraw.ImageDraw, cx: int, base_y: int, height: int, half_width: int, color):
    """A simple oil-derrick (lattice tower) silhouette: tapered tower on a base beam."""
    top = base_y - height
    top_half = max(6, half_width // 7)

    # Outer tower outline (tapered trapezoid).
    draw.polygon(
        [
            (cx - half_width, base_y),
            (cx + half_width, base_y),
            (cx + top_half, top),
            (cx - top_half, top),
        ],
        fill=color,
    )

    # Carve the inside out to leave a lattice-like frame + cross braces, by
    # punching navy-colored triangles/rects back in.
    def punch(poly):
        draw.polygon(poly, fill=NAVY)

    wall = max(10, half_width // 6)
    inner_half_base = half_width - wall
    inner_top_half = max(2, top_half - wall // 2)
    punch([
        (cx - inner_half_base, base_y - wall),
        (cx + inner_half_base, base_y - wall),
        (cx + inner_top_half, top + wall),
        (cx - inner_top_half, top + wall),
    ])

    # Cross braces (X pattern) across 3 bands.
    bands = 3
    for i in range(bands):
        y0 = base_y - wall - i * (height - 2 * wall) // bands
        y1 = base_y - wall - (i + 1) * (height - 2 * wall) // bands
        t = i / bands
        t1 = (i + 1) / bands
        lx0 = cx - (half_width - wall + (top_half - (half_width - wall)) * t)
        rx0 = cx + (half_width - wall + (top_half - (half_width - wall)) * t)
        lx1 = cx - (half_width - wall + (top_half - (half_width - wall)) * t1)
        rx1 = cx + (half_width - wall + (top_half - (half_width - wall)) * t1)
        bw = max(6, wall // 2)
        draw.line([(lx0, y0), (rx1, y1)], fill=color, width=bw)
        draw.line([(rx0, y0), (lx1, y1)], fill=color, width=bw)

    # Base beam.
    beam_h = max(10, half_width // 5)
    draw.rectangle(
        [cx - half_width - wall, base_y, cx + half_width + wall, base_y + beam_h],
        fill=color,
    )


def build(bg_color):
    img = Image.new("RGBA", (SIZE, SIZE), bg_color)
    draw = ImageDraw.Draw(img)

    if bg_color is not None:
        # Full rounded-square badge look for the flat (non-adaptive) icon.
        radius = int(SIZE * 0.22)
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=255)
        bg = Image.new("RGBA", (SIZE, SIZE), NAVY)
        out = Image.composite(bg, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), mask)
        draw = ImageDraw.Draw(out)
    else:
        out = img

    cx = SIZE // 2
    base_y = int(SIZE * 0.72)
    height = int(SIZE * 0.40)
    half_width = int(SIZE * 0.17)

    draw_derrick(draw, cx, base_y, height, half_width, ACCENT)

    # Small ground line / platform under the derrick.
    draw.rounded_rectangle(
        [cx - half_width - int(SIZE * 0.07), base_y + int(SIZE * 0.045),
         cx + half_width + int(SIZE * 0.07), base_y + int(SIZE * 0.075)],
        radius=int(SIZE * 0.015),
        fill=WHITE,
    )

    return out


if __name__ == "__main__":
    flat = build(NAVY)
    flat.save("assets/icon/icon.png")

    foreground = build(None)
    foreground.save("assets/icon/icon_foreground.png")

    print("Wrote assets/icon/icon.png and assets/icon/icon_foreground.png")
