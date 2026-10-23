"""Prepare owner-selected forest WAVs. Requires numpy/soundfile; never edits masters.

Usage: python tools/prepare_forest_audio.py <external-source-folder>
Only this offline preparation command needs the originals; Godot uses res:// assets.
"""
from pathlib import Path
import sys
import json
import hashlib
import re
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio/forest'
FAMILIES = {
    'footstep_dirt': ('footsteps/dirt', .19),
    'footstep_grass': ('footsteps/grass', .14),
    'footstep_wet_dirt': ('footsteps/wet_dirt', .18),
    'footstep_puddle': ('footsteps/puddle', .18),
    'grass_brush': ('foliage', .07),
    'bush_brush': ('foliage', .09),
    'forest_crow': ('ambience', .09),
    'forest_woodpecker': ('ambience', .09),
    'forest_wind_gust': ('ambience', .06),
    'forest_tree_creak': ('ambience', .08),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def active_rms(data, rate):
    n = min(len(data), rate // 10)
    power = np.r_[0., np.cumsum(data * data)]
    return float(np.sqrt(np.max((power[n:] - power[:-n]) / n)))


def import_settings(path, loop=False):
    # Godot fills generated paths/UIDs on first import. Keep existing UIDs on rebuild.
    sidecar = Path(str(path) + '.import')
    if sidecar.exists():
        text = sidecar.read_text(encoding='utf-8')
        if loop:
            text = re.sub(r'(?m)^loop=.*$', 'loop=true', text)
        else:
            text = re.sub(r'(?m)^compress/mode=.*$', 'compress/mode=0', text)
    else:
        text = ('[remap]\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\nloop=true\nloop_offset=0.0\n' if loop else
                '[remap]\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\ncompress/mode=0\nedit/trim=false\nedit/normalize=false\n')
    sidecar.write_text(text, encoding='utf-8')


def main(source):
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for family, (folder, target) in FAMILIES.items():
        files = sorted(source.glob(family + '*.wav'), key=lambda p: (0 if p.stem == family else int(p.stem.rsplit('-', 1)[1])))
        if not files:
            raise ValueError('Missing family: ' + family)
        for index, path in enumerate(files):
            x, rate = sf.read(path, always_2d=True)
            if rate != 48000:
                raise ValueError('Expected 48 kHz: ' + path.name)
            y = x.mean(axis=1)
            ratio = float(np.sqrt(np.mean(y*y) / max(np.mean(x*x), 1e-20)))
            if ratio < .5:
                raise ValueError('Inspect stereo phase before downmix: ' + path.name)
            dc = float(y.mean())
            y -= dc
            window = rate // 200
            rms = np.sqrt(np.mean(y[:len(y)//window*window].reshape(-1,window)**2, axis=1))
            active = np.flatnonzero(rms > rms.max() * .01)
            start = max(0, int(active[0]*window) - int(.008*rate))
            end = min(len(y), int((active[-1]+1)*window) + int(.08*rate))
            y = y[start:end].copy()
            before = active_rms(y, rate)
            gain = min(target / max(before, 1e-12), .88 / max(abs(y).max(), 1e-12))
            y *= gain
            fade_in, fade_out = (.0002, .008) if family.startswith('footstep') else (.005, .015)
            for length, head in [(int(fade_in*rate), True), (int(fade_out*rate), False)]:
                length = min(length, len(y)//2)
                if head:
                    y[:length] *= np.linspace(0, 1, length)
                else:
                    y[-length:] *= np.linspace(1, 0, length)
            output = OUT / folder / (family + f'_{index+1:02d}.wav')
            output.parent.mkdir(parents=True, exist_ok=True)
            sf.write(output, y, rate, subtype='PCM_16')
            import_settings(output)
            records.append(dict(source=path.name, source_sha256=digest(path), rank=index,
                                output=str(output.relative_to(OUT)).replace('\\','/'), output_sha256=digest(output),
                                source_seconds=len(x)/rate, source_channels=x.shape[1], sample_rate=rate,
                                crop_start_seconds=start/rate, crop_end_seconds=end/rate, mono_rms_ratio=ratio,
                                dc_removed=dc, gain_linear=float(gain), edge_fades_seconds=[fade_in,fade_out],
                                output_seconds=len(y)/rate, peak=float(abs(y).max()), rms100=active_rms(y,rate)))
    path = source / 'forest_ambience.wav'
    x, rate = sf.read(path, always_2d=True)
    if rate != 48000 or x.shape[1] != 2:
        raise ValueError('Expected stereo 48 kHz forest bed')
    x -= x.mean(axis=0)
    n = int(.12*rate)
    t = np.linspace(0, np.pi/2, n)[:,None]
    y = np.concatenate([x[n:-n], x[-n:]*np.cos(t) + x[:n]*np.sin(t)])
    gain = min(.07 / np.sqrt(np.mean(y*y)), .75 / abs(y).max())
    y *= gain
    output = OUT / 'ambience/forest_bed_loop.ogg'
    # Bounded chunks avoid excessive native Vorbis encoder stack use on Windows.
    with sf.SoundFile(output, mode='w', samplerate=rate, channels=2, format='OGG', subtype='VORBIS') as encoder:
        for start in range(0, len(y), 4096):
            encoder.write(y[start:start+4096])
    import_settings(output, loop=True)
    records.append(dict(source=path.name, source_sha256=digest(path), rank=0,
                        output='ambience/forest_bed_loop.ogg', output_sha256=digest(output),
                        source_seconds=len(x)/rate, source_channels=2, sample_rate=rate,
                        gain_linear=float(gain), loop_crossfade_seconds=.12, output_seconds=len(y)/rate))
    metadata = dict(origin='ElevenLabs Sound Effects; generated and selected by project owner',
                    license='Owner-provided generated assets; not represented as CC0/CC BY',
                    format='48 kHz mono PCM16 one-shots; stereo Vorbis looping ambience',
                    processing='DC removal; phase-checked mono one-shots; relative -40 dB RMS boundaries with 8 ms pre-roll/80 ms tail padding; scalar RMS100 gain capped at 0.88 peak; edge fades. Stereo bed: 120 ms equal-power loop join and scalar gain.',
                    runtime_dependency='Only files inside this directory. Original folder is not required.',
                    unused_sources=[dict(source='forest_ambience-2.wav', reason='Lower-priority alternative bed; keep outside runtime bank')],
                    recordings=records)
    (OUT/'SOURCES.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    (OUT/'CREDITS.md').write_text('# Лесная озвучка\n\nСгенерирована и отобрана владельцем в ElevenLabs Sound Effects.\nЭто предоставленные владельцем генерации, не материалы CC0/CC BY.\nИсходные имена, SHA256 и обработка — SOURCES.json. Игра использует только\nподготовленные файлы внутри проекта; оригиналы для запуска не требуются.\n', encoding='utf-8')
    resources = ROOT / 'resources/audio/forest'
    resources.mkdir(parents=True, exist_ok=True)
    for family in FAMILIES:
        steps = family.startswith('footstep_')
        script = 'footstep_profile' if steps else 'sound_cue'
        rows = [r for r in records if r['source'] == family+'.wav' or r['source'].startswith(family+'-')]
        text = '[gd_resource type="Resource" format=3]\n\n'
        text += f'[ext_resource type="Script" path="res://scripts/{script}.gd" id="script"]\n'
        for index, row in enumerate(rows):
            text += f'[ext_resource type="AudioStream" path="res://assets/audio/forest/{row["output"]}" id="clip{index}"]\n'
        text += '\n[resource]\nscript = ExtResource("script")\n'
        text += f'{"surface_id" if steps else "id"} = &"{family.removeprefix("footstep_") if steps else family}"\n'
        text += 'clips = Array[AudioStream]([' + ', '.join(f'ExtResource("clip{i}")' for i in range(len(rows))) + '])\n'
        if not steps:
            volumes = {'grass_brush': -9, 'bush_brush': -9, 'forest_crow': -5,
                       'forest_woodpecker': -8, 'forest_wind_gust': -8, 'forest_tree_creak': -12}
            text += 'clip_weights = PackedFloat32Array(' + ', '.join(str(max(1, 3-i)) for i in range(len(rows))) + ')\n'
            text += f'volume_db = {volumes[family]}.0\npitch_variation = 0.015\n'
        name = 'footsteps_' + family.removeprefix('footstep_') if steps else family
        (resources/(name+'.tres')).write_text(text, encoding='utf-8')
    print(f'Prepared {len(records)} recordings; external masters unchanged.')


if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve())
