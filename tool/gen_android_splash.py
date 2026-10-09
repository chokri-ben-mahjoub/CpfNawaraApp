"""Images de l'écran de démarrage natif Android (derrick sur fond bleu nuit),
à partir de assets/icon/icon_foreground.png.

    python tool/gen_android_splash.py

- splash_logo.png : Android 5 à 11 (layer-list launch_background.xml), 120 dp.
- splash_icon.png : Android 12+ (windowSplashScreenAnimatedIcon), 240 dp,
  dessin réduit pour tenir dans le cercle visible (160 dp).
"""
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent.parent
res = root / 'android' / 'app' / 'src' / 'main' / 'res'
src = Image.open(root / 'assets' / 'icon' / 'icon_foreground.png').convert('RGBA')
content = src.crop(src.getbbox())
densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}


def render(canvas_dp: float, content_ratio: float, scale: float) -> Image.Image:
    size = round(canvas_dp * scale)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    box = size * content_ratio
    factor = box / max(content.size)
    resized = content.resize((round(content.width * factor), round(content.height * factor)), Image.LANCZOS)
    canvas.paste(resized, ((size - resized.width) // 2, (size - resized.height) // 2), resized)
    return canvas


for name, scale in densities.items():
    folder = res / f'drawable-{name}'
    folder.mkdir(exist_ok=True)
    render(120, 1.0, scale).save(folder / 'splash_logo.png', optimize=True)
    render(240, 0.44, scale).save(folder / 'splash_icon.png', optimize=True)
print('ok')
