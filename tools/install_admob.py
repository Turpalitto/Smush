#!/usr/bin/env python3
"""Install optional MIT Poing AdMob 5.1.0 and its Godot 4.6.3 Android binaries.
No Google SDK license acceptance, account configuration or payments are performed.
"""
import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import urllib.request
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--install', action='store_true', help='Download the pinned optional AdMob add-on')
args = parser.parse_args()
if not args.install:
    parser.print_help()
    raise SystemExit(0)
root = Path(__file__).resolve().parents[1]
destination = root / 'addons/admob'
if destination.exists():
    raise SystemExit('addons/admob exists; refusing to overwrite it')
base = 'https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/'
artifacts = [
    ('poing-godot-admob-v5.1.0.zip', '8c53ff52719edf6a81cc7d32a9cdaad2d9e11693c85faca25008a1c19355726f'),
    ('android-template-v4.6.3.zip', 'f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee'),
]
archives = []
for name, digest in artifacts:
    with urllib.request.urlopen(base + name, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f'Checksum mismatch: {name}')
    archive = zipfile.ZipFile(io.BytesIO(data))
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit('Unsafe archive path')
    archives.append(archive)
for entry in archives[0].infolist():
    prefix = 'poing-godot-admob/addons/admob/'
    if entry.filename.startswith(prefix) and not entry.is_dir():
        rel = entry.filename[len(prefix):]
        # Samples, C# and agent instructions are not needed by this GDScript game.
        if rel.startswith(('csharp/', 'skills/', 'gdscript/sample/')):
            continue
        path = destination / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archives[0].read(entry))
for entry in archives[1].infolist():
    if not entry.is_dir() and (entry.filename.startswith('ads/') or entry.filename == 'package.gd'):
        path = destination / 'android/bin' / entry.filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archives[1].read(entry))
(destination / 'gdscript/sample').mkdir(parents=True, exist_ok=True)
(destination / 'gdscript/sample/.gdignore').touch()
print('Installed official MIT AdMob 5.1.0 + Android 4.6.3 files with SHA256 verification.')
print('Enable the AdMob editor plugin; configure app ID, rewarded unit IDs and UMP before Android testing.')
print('Release is blocked until real test-device/Play account validation is completed.')
