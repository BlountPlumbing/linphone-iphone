#!/usr/bin/env python3
"""make-icon.py — generate the Blount Phone app icon (1024x1024).

Brand palette from wave8 marketing-site: navy #0f2a43 field, amber #f5a623
accent. Glyph = U+2706 TELEPHONE LOCATION SIGN (DejaVu Sans) — the classic
handset-receiver silhouette — rotated -35 deg. Supersampled 4x, LANCZOS
downscale. Output: phone-app/AppIcon-1024.png

Replaces Linphone/Assets.xcassets/AppIcon.appiconset/1024x1024.png at
fork-build time (rebrand.sh step 6b). Output MUST be opaque RGB — TestFlight
rejects any alpha channel in the app icon.
"""
import os
from PIL import Image, ImageDraw, ImageFont

S = 4
SIZE = 1024 * S
NAVY = (15, 42, 67)        # #0f2a43
NAVY_HI = (18, 38, 58)     # #12263a
AMBER = (245, 166, 35)     # #f5a623
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
GLYPH = "✆"

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

r = int(0.222 * SIZE)
d.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=r, fill=NAVY + (255,))
d.rounded_rectangle([0, 0, SIZE - 1, int(SIZE * 0.52)], radius=r,
                    fill=NAVY_HI + (255,))
d.rectangle([0, int(SIZE * 0.40), SIZE - 1, int(SIZE * 0.52)], fill=NAVY_HI + (255,))

# glyph fitted to ~74% of canvas width on its own layer, then rotated
probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
fsize = SIZE
while fsize > 64:
    font = ImageFont.truetype(FONT, fsize)
    bb = probe.textbbox((0, 0), GLYPH, font=font)
    if bb[2] - bb[0] <= SIZE * 0.74 and bb[3] - bb[1] <= SIZE * 0.62:
        break
    fsize -= 64
gl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
g = ImageDraw.Draw(gl)
bb = g.textbbox((0, 0), GLYPH, font=font)
g.text(((SIZE - (bb[2] - bb[0])) // 2 - bb[0],
        (SIZE - (bb[3] - bb[1])) // 2 - bb[1] - int(SIZE * 0.02)),
       GLYPH, font=font, fill=AMBER + (255,))
gl = gl.rotate(-35, resample=Image.BICUBIC, center=(SIZE // 2, SIZE // 2))
img = Image.alpha_composite(img, gl)

img = img.resize((1024, 1024), Image.LANCZOS)
# Flatten to opaque RGB — transparent rounded corners would reintroduce the
# alpha channel TestFlight rejected (build-1 upload failure).
img = Image.alpha_composite(Image.new("RGBA", img.size, NAVY + (255,)), img)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon-1024.png")
img.convert("RGB").save(out)
prev = Image.new("RGBA", (256, 256), NAVY + (255,))
prev.alpha_composite(img.resize((256, 256), Image.LANCZOS))
prev.convert("RGB").save("/tmp/appicon-preview.png")
print("wrote phone-app/AppIcon-1024.png + /tmp/appicon-preview.png")
