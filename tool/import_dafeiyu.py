"""Remux upstream WebP frames without re-encoding their pixels."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

REVISION = '084323845ab82b68d5388d5c638bec09d8544a8a'

def chunk(tag, data):
    return tag + struct.pack('<I', len(data)) + data + b'\0' * (len(data) % 2)

def u24(value):
    return value.to_bytes(3, 'little')

def frame_chunks(data):
    assert data[:4] == b'RIFF' and data[8:12] == b'WEBP'
    pos, result = 12, b''
    while pos < len(data):
        tag = data[pos:pos+4]
        length = struct.unpack('<I', data[pos+4:pos+8])[0]
        end = pos + 8 + length + length % 2
        if tag in (b'ALPH', b'VP8 ', b'VP8L'):
            result += data[pos:end]
        pos = end
    assert result
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('assets/pet/dafeiyu'))
    args = parser.parse_args()
    source, out = args.source, args.output
    manifest = json.loads((source/'assets/pet-manifest.json').read_text())
    out.mkdir(parents=True, exist_ok=True)
    records = {}
    w, h = manifest['maxFrameWidth'], manifest['maxFrameHeight']
    for name, clip in manifest['clips'].items():
        payload = chunk(b'VP8X', b'\x12\0\0\0' + u24(w-1) + u24(h-1))
        payload += chunk(b'ANIM', struct.pack('<IH', 0, 0 if clip['loop'] else 1))
        for file in clip['frames']:
            frame = frame_chunks((source/'assets/pet'/file).read_bytes())
            header = u24(0)*2 + u24(w-1) + u24(h-1) + u24(clip['frameMs']) + b'\x02'
            payload += chunk(b'ANMF', header + frame)
        result = b'RIFF' + struct.pack('<I', len(payload)+4) + b'WEBP' + payload
        (out/f'{name}.webp').write_bytes(result)
        records[name] = dict(source=clip['source'], frames=len(clip['frames']), frameMs=clip['frameMs'], loop=clip['loop'], sha256=hashlib.sha256(result).hexdigest())
    shutil.copyfile(source/'assets/pet'/manifest['clips']['idle']['frames'][0], out/'poster.webp')
    shutil.copyfile(source/'assets/dsh-pet-LICENSE.txt', out/'LICENSE.txt')
    (out/'provenance.json').write_text(json.dumps(dict(repository='https://github.com/QCYTSN/dsh-dafeiyu', revision=REVISION, assetSource=manifest['assetSource'], conversion='Original compressed WebP frame chunks; no pixel re-encoding', clips=records), indent=2, ensure_ascii=False)+'\n')
    print(f'Imported {len(records)} animations into {out}')

if __name__ == '__main__':
    main()
