#!/usr/bin/env python3
"""Check installed Android tools; never accepts SDK licenses or generates release keys."""
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
offline = '--offline' in sys.argv
sdk_var = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
jdk_var = os.environ.get('JAVA_HOME')
missing = []
if not sdk_var:
    missing.append('ANDROID_HOME or ANDROID_SDK_ROOT')
if not jdk_var:
    missing.append('JAVA_HOME (JDK 17+ required for Gradle)')
if jdk_var:
    for name in (['java', 'keytool'] if offline else ['java', 'keytool', 'javac']):
        if not (Path(jdk_var) / 'bin' / name).is_file():
            missing.append(f'JDK executable: {name}')
if sdk_var:
    sdk = Path(sdk_var)
    if not (sdk / 'platform-tools/adb').is_file():
        missing.append('Android platform-tools/adb')
    signers = list((sdk / 'build-tools').glob('*/apksigner'))
    if not signers:
        missing.append('Android build-tools/apksigner')
    if not offline and not (sdk / 'platforms/android-36/android.jar').is_file():
        missing.append('Android platform 36')
if not offline:
    for flavor in ('debug', 'release'):
        if not (root / f'addons/GodotGooglePlayBilling/bin/{flavor}/GodotGooglePlayBilling-{flavor}.aar').is_file():
            missing.append(f'Official Billing 3.3.0 {flavor} AAR')
if missing:
    print('Android export blocked by missing toolchain components:', file=sys.stderr)
    for item in missing:
        print(f'  - {item}', file=sys.stderr)
    print('See RELEASE_CHECKLIST.md. SDK license acceptance requires the owner.', file=sys.stderr)
    sys.exit(2)
print('Android toolchain preflight passed')
