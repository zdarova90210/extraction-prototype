"""Rebuild Godot atlas resources from unchanged generated PNGs (Pillow read-only).

Run from the repository with Python + Pillow. No PNG is resized, recolored,
cropped or overwritten: AtlasTexture regions/margins only describe Godot views.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/art/forest_post'
OUT = ROOT / 'resources/art/forest_post'
OUT.mkdir(parents=True, exist_ok=True)


def save(name, text):
    (OUT / name).write_text(text.strip() + '\n', encoding='utf-8')


def rect(values):
    return 'Rect2(%s)' % ', '.join(str(v) for v in values)


def alpha_bounds(image, box):
    # Inspect alpha to describe the region; never save an edited image.
    alpha = image.getchannel('A').crop(box)
    bounds = alpha.point(lambda value: 255 if value > 150 else 0).getbbox()
    if bounds is None:
        raise ValueError(f'No opaque sprite in {box}')
    left, top, right, bottom = bounds
    return [box[0] + left - 2, box[1] + top - 2, right - left + 4, bottom - top + 4]


layout = {}
props = Image.open(ART / 'props.png')
for name, box in {
    'hut': (28, 32, 570, 612),
    'pine': (585, 32, 984, 615),
    'logs': (1008, 250, 1536, 616),
    'fence': (64, 670, 545, 977),
    'chest': (604, 704, 956, 978),
    'rocks': (1032, 648, 1528, 1000),
}.items():
    region = alpha_bounds(props, box)
    layout[name] = region
    save(name + '.tres', f'''[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/art/forest_post/props.png" id="1"]

[resource]
atlas = ExtResource("1")
region = {rect(region)}
filter_clip = true
''')

for actor in ('scout', 'guard'):
    image = Image.open(ART / (actor + '.png'))
    width, height = image.size
    regions = []
    text = f'''[gd_resource type="SpriteFrames" load_steps=14 format=3]

[ext_resource type="Texture2D" path="res://assets/art/forest_post/{actor}.png" id="1"]
'''
    for row in range(3):
        for column in range(4):
            box = (round(column * width / 4), round(row * height / 3),
                   round((column + 1) * width / 4), round((row + 1) * height / 3))
            region = alpha_bounds(image, box)
            regions.append(region)
            w, h = region[2:]
            if w > 192 or h > 260:
                raise ValueError('Sprite exceeds the shared animation canvas')
            text += f'''
[sub_resource type="AtlasTexture" id="Frame_{row}_{column}"]
atlas = ExtResource("1")
region = {rect(region)}
margin = {rect([(192 - w) / 2, 0, 192 - w, 260 - h])}
filter_clip = true
'''
    text += '\n[resource]\nanimations = [\n'
    for row, animation in enumerate(('down', 'side', 'up')):
        frames = ', '.join('{"duration": 1.0, "texture": SubResource("Frame_%d_%d")}' % (row, c) for c in range(4))
        text += '{"frames": [%s], "loop": true, "name": &"%s", "speed": 8.0},\n' % (frames, animation)
    text += ']\n'
    save(actor + '_frames.tres', text)
    layout[actor] = regions

(ART / 'SOURCES.json').write_text(json.dumps({
    'generator': 'Built-in image_gen; exact prompts stored alongside PNGs',
    'reference': 'User-selected concept 03_pixel_checkpoint.png, generated 2026-10-22',
    'processing': 'PNG byte-for-byte copies. Godot AtlasTexture region/margin only; alpha cutoff shader at runtime.',
    'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in ART.glob('*.png')},
    'atlas_regions': layout,
}, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print('Built 6 prop atlases and 2 animation resources; PNGs unchanged.')
