#!/usr/bin/env python3
"""Set only Android path options in local Godot EditorSettings without printing credentials."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
jdk = os.environ.get('JAVA_HOME')
if not sdk or not jdk:
    raise SystemExit('ANDROID_HOME (or ANDROID_SDK_ROOT) and JAVA_HOME are required')
version = subprocess.check_output([os.environ.get('GODOT_BIN', 'godot4'), '--version'], text=True).split('.')
config_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'godot'
config_dir.mkdir(parents=True, exist_ok=True)
config = config_dir / f'editor_settings-{version[0]}.{version[1]}.tres'
text = config.read_text() if config.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
values = {'export/android/android_sdk_path': str(Path(sdk).resolve()),
          'export/android/java_sdk_path': str(Path(jdk).resolve())}
if os.environ.get('GODOT_ANDROID_KEYSTORE_DEBUG_PATH'):
    values.update({'export/android/debug_keystore': os.environ['GODOT_ANDROID_KEYSTORE_DEBUG_PATH'],
                   'export/android/debug_keystore_user': 'androiddebugkey',
                   'export/android/debug_keystore_pass': 'android'})
for key, value in values.items():
    line = f'{key} = {json.dumps(value)}'
    pattern = rf'^{re.escape(key)} = .*?$'
    if re.search(pattern, text, flags=re.MULTILINE):
        text = re.sub(pattern, lambda _: line, text, flags=re.MULTILINE)
    else:
        text = text.replace('[resource]\n', '[resource]\n' + line + '\n', 1)
with tempfile.NamedTemporaryFile(mode='w', dir=config_dir, delete=False) as handle:
    handle.write(text)
    temporary = Path(handle.name)
temporary.replace(config)
print('Android editor paths configured in local user settings')
