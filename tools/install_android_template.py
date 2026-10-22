#!/usr/bin/env python3
"""Unpack the installed official export template matching the selected Godot binary."""
import os
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
version = subprocess.check_output([os.environ.get('GODOT_BIN', 'godot4'), '--version'], text=True).strip().split('.')
template_version = '.'.join(version[:3]) + '.stable'
data_root = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
source = data_root / 'godot/export_templates' / template_version / 'android_source.zip'
if not source.is_file():
    raise SystemExit(f'Install official {template_version} export templates first: {source}')
destination = root / 'android/build'
if destination.exists() and any(destination.iterdir()):
    raise SystemExit('android/build is not empty; refusing to overwrite an existing Gradle template')
with zipfile.ZipFile(source) as archive:
    archive.extractall(destination)
(destination / '.gdignore').touch()
(root / 'android/.build_version').write_text('.'.join(version[:3]) + '.stable\n')
for executable in ['gradlew']:
    path = destination / executable
    if path.exists():
        path.chmod(path.stat().st_mode | 0o111)
print(f'Installed official Android Gradle source: {template_version}')
