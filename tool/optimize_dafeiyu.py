#!/usr/bin/env python3
"""Shrink bundled BigFish WebP animations with a measured display-quality floor.

Requires Pillow and numpy only on the build machine. Runtime remains Flutter's
native WebP codec; no new app dependency or network download is introduced.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import time

import numpy as np
from PIL import Image, ImageSequence, __version__ as PILLOW_VERSION

BACKGROUNDS = [(16, 22, 18), (243, 246, 237), (200, 255, 95)]
DISPLAY_SIZE = (230, 192)


def box_mean(a, n=7):
    pad = n // 2
    a = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode='reflect')
    s = np.pad(a, ((1, 0), (1, 0), (0, 0))).cumsum(0).cumsum(1)
    return (s[n:, n:] - s[:-n, n:] - s[n:, :-n] + s[:-n, :-n]) / (n*n)


def composite(a, background):
    alpha = a[:, :, 3:4].astype(float) / 255
    return a[:, :, :3] * alpha + np.array(background) * (1-alpha)


def visible_ssim(a, b, mask):
    if not np.any(mask):
        return 1.0
    a, b = a.astype(float), b.astype(float)
    ma, mb = box_mean(a), box_mean(b)
    va = (box_mean(a*a) - ma*ma) * 49/48
    vb = (box_mean(b*b) - mb*mb) * 49/48
    covariance = (box_mean(a*b) - ma*mb) * 49/48
    score = ((2*ma*mb + 6.5025) * (2*covariance + 58.5225)) / (
        (ma*ma + mb*mb + 6.5025) * (va+vb+58.5225))
    return float(score[mask].mean())


def verify(original, candidate, frame_ms, frame_count, loop):
    """Compare every logical frame on dark, light and lime backgrounds.

    The mask excludes transparent background so blank canvas cannot inflate
    SSIM. Encoded duplicate frames may merge; logical timing must stay exact.
    """
    scores = []
    alpha_error = 0
    durations = []
    logical = 0
    with Image.open(original) as source, Image.open(candidate) as optimized:
        assert optimized.size == source.size == (412, 344)
        assert optimized.info.get('loop', 0) == (0 if loop else 1)
        encoded_frames = optimized.n_frames
        for frame in ImageSequence.Iterator(optimized):
            actual = frame.convert('RGBA')
            duration = optimized.info['duration']
            assert duration > 0 and duration % frame_ms == 0
            durations.append(duration)
            actual_array = np.array(actual)
            scaled_actual = np.array(actual.resize(DISPLAY_SIZE, Image.Resampling.LANCZOS))
            for _ in range(duration // frame_ms):
                assert logical < frame_count
                source.seek(logical)
                reference = source.convert('RGBA')
                reference_array = np.array(reference)
                alpha_error = max(alpha_error, int(np.abs(reference_array[:, :, 3].astype(int) - actual_array[:, :, 3].astype(int)).max()))
                scaled_reference = np.array(reference.resize(DISPLAY_SIZE, Image.Resampling.LANCZOS))
                mask = scaled_reference[:, :, 3] > 8
                for bg in BACKGROUNDS:
                    scores.append(visible_ssim(composite(scaled_reference, bg), composite(scaled_actual, bg), mask))
                logical += 1
        assert logical == frame_count
        assert sum(durations) == frame_count * frame_ms
    return dict(encodedFrames=encoded_frames, durationsMs=durations,
                logicalFrames=logical, durationMs=sum(durations),
                minDisplaySSIM=min(scores), meanDisplaySSIM=float(np.mean(scores)),
                maxAlphaError=alpha_error)


def encode(source, output, quality, loop, frame_ms):
    frames = []
    with Image.open(source) as image:
        for frame in ImageSequence.Iterator(image):
            rgba = np.array(frame.convert('RGBA'))
            # The upstream video contains a nearly invisible alpha=1 veil.
            # Removing only opacity <=1/255 makes its hidden RGB discardable.
            # All other alpha values are preserved exactly.
            rgba[rgba[:, :, 3] <= 1] = 0
            frames.append(Image.fromarray(rgba))
    frames[0].save(output, format='WEBP', save_all=True, append_images=frames[1:],
                   duration=frame_ms, loop=0 if loop else 1,
                   lossless=False, quality=quality, method=4,
                   minimize_size=True, alpha_quality=100)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=Path('assets/pet/dafeiyu'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--quality', type=int, default=50)
    parser.add_argument('--min-display-ssim', type=float, default=.985)
    args = parser.parse_args()
    assert args.input.resolve() != args.output.resolve(), 'Use a staging directory'
    if not 0 <= args.quality <= 100 or not 0 <= args.min_display_ssim <= 1 or args.workers < 1:
        parser.error('Quality must be 0..100, SSIM 0..1, and workers positive')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Output must be a new/empty staging directory')
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.input/'provenance.json').read_text())
    assert not manifest.get('optimization'), 'Always optimize from original assets'
    unique = {}
    aliases = {}
    for name in manifest['clips']:
        data = (args.input/f'{name}.webp').read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        canonical = unique.setdefault(digest, name)
        aliases[name] = canonical

    def process(name):
        started = time.monotonic()
        clip = manifest['clips'][name]
        source, output = args.input/f'{name}.webp', args.output/f'{name}.webp'
        original_size = source.stat().st_size
        selected = None
        for quality in [args.quality, *[q for q in (68, 85) if q > args.quality]]:
            encode(source, output, quality, clip['loop'], clip['frameMs'])
            if output.stat().st_size >= original_size:
                break
            metrics = verify(source, output, clip['frameMs'], clip['frames'], clip['loop'])
            if metrics['minDisplaySSIM'] >= args.min_display_ssim and metrics['maxAlphaError'] <= 1:
                selected = dict(metrics, quality=quality, mode='measured-lossy')
                break
        if selected is None:
            shutil.copyfile(source, output)
            selected = verify(source, output, clip['frameMs'], clip['frames'], clip['loop'])
            selected.update(quality=None, mode='original-fallback')
        selected.update(originalBytes=original_size, optimizedBytes=output.stat().st_size,
                        originalSha256=clip['sha256'], sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                        asset=f'{name}.webp')
        print(json.dumps(dict(clip=name, bytes=selected['optimizedBytes'], original=original_size,
                              quality=selected['quality'], minSSIM=round(selected['minDisplaySSIM'], 5),
                              seconds=round(time.monotonic()-started, 1))), flush=True)
        return name, selected

    names = list(dict.fromkeys(aliases.values()))
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = dict(pool.map(process, names))
    for name, clip in manifest['clips'].items():
        canonical = aliases[name]
        stats = results[canonical]
        clip.update(stats)
        if name != canonical:
            clip['aliasOf'] = canonical
            assert not (args.output/f'{name}.webp').exists()
    for file in ['poster.webp', 'LICENSE.txt']:
        shutil.copyfile(args.input/file, args.output/file)
    before = sum((args.input/f'{name}.webp').stat().st_size for name in aliases)
    after = sum((args.output/f'{name}.webp').stat().st_size for name in names)
    manifest['conversion'] = 'Measured high-quality WebP re-encoding; shared identical animations; complete logical timelines'
    manifest['optimization'] = dict(pillow=PILLOW_VERSION, codec='libwebp', displaySize=list(DISPLAY_SIZE),
        minDisplaySSIM=args.min_display_ssim, maxAlphaError=1, backgrounds=BACKGROUNDS,
        alphaCleanupMaxOpacity=1, runtime='unchanged Flutter native WebP codec',
        originalAnimationBytes=before, optimizedAnimationBytes=after, savedBytes=before-after,
        originalClips=len(aliases), bundledAnimations=len(names), logicalFrames=sum(c['frames'] for c in manifest['clips'].values()))
    (args.output/'provenance.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(manifest['optimization']), flush=True)


if __name__ == '__main__':
    main()
