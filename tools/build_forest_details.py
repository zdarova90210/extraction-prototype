"""Build atlases for the supplemental forest sheet; never rewrite PNGs or scenes."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/art/forest_dusk'
OUT = ROOT / 'resources/art/forest_dusk'
# Actual gaps in the generated sheet, not an assumed perfect grid.
CELLS = {
    'grass_low': (0, 0, 384, 350),
    'grass_tall': (384, 0, 768, 350),
    'fern': (768, 0, 1152, 350),
    'shrub': (1152, 0, 1536, 350),
    'stump': (0, 350, 420, 680),
    'firewood': (420, 350, 768, 680),
    'workbench': (768, 350, 1152, 680),
    'planks': (1152, 350, 1536, 680),
    'puddle': (0, 680, 410, 1024),
    'needles': (410, 680, 780, 1024),
    'small_rocks': (780, 680, 1152, 1024),
    'fern_grass': (1152, 680, 1536, 1024),
}


def main():
    image = Image.open(ART / 'details.png')
    layout = {}
    for name, box in CELLS.items():
        alpha = image.getchannel('A').crop(box)
        found = alpha.point(lambda value: 255 if value > 127 else 0).getbbox()
        if found is None:
            raise ValueError(f'Empty sprite: {name}')
        left, top, right, bottom = found
        if left < 2 or top < 2 or right > alpha.width - 2 or bottom > alpha.height - 2:
            raise ValueError(f'Sprite crosses its cell: {name}: {found}')
        region = (box[0] + left - 1, box[1] + top - 1, right - left + 2, bottom - top + 2)
        layout[name] = region
        text = f'''[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/art/forest_dusk/details.png" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2({', '.join(map(str, region))})
filter_clip = true
'''
        (OUT / f'{name}.tres').write_text(text, encoding='utf-8')
    manifest = {
        'generator': 'Built-in image_gen, transparent background',
        'prompt': 'details_prompt.txt',
        'reference': 'props.png, style/palette only; existing files unchanged',
        'processing': 'Byte-for-byte PNG copy; AtlasTexture regions and scene scale only; alpha retained',
        'sha256': hashlib.sha256((ART / 'details.png').read_bytes()).hexdigest(),
        'atlas_layout': layout,
    }
    (ART / 'DETAILS_SOURCES.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'Built {len(layout)} detail atlases; no PNG or scene modified.')


if __name__ == '__main__':
    main()
