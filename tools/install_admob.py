#!/usr/bin/env python3
"""Install optional MIT Poing AdMob 5.1.0 and its Godot 4.6.3 Android binaries.
No Google SDK license acceptance, account configuration or payments are performed.

Download policy (SSRF hardening): HTTPS only, a fixed host allowlist, every
resolved address checked to be a public unicast address before connecting, and
redirect targets re-validated by the same policy. Integrity does not rely on the
network layer at all: each artifact is SHA256-pinned, so even a hijacked
connection cannot substitute content.
"""
import argparse
import hashlib
import io
import ipaddress
import socket
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

ALLOWED_HOSTS = frozenset({'github.com', 'objects.githubusercontent.com'})
MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024

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


def validate_url(url: str) -> None:
    """Reject anything that is not a pinned-allowlist HTTPS target, and refuse
    hosts that resolve to private, loopback, link-local or otherwise
    non-public addresses (SSRF / cloud-metadata / rebinding guard)."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != 'https':
        raise SystemExit(f'Blocked non-HTTPS URL: {url}')
    if parts.username or parts.password or parts.port not in (None, 443):
        raise SystemExit(f'Blocked URL with credentials or custom port: {url}')
    if parts.hostname not in ALLOWED_HOSTS:
        raise SystemExit(f'Blocked non-allowlisted host: {parts.hostname}')
    try:
        infos = socket.getaddrinfo(parts.hostname, 443, proto=socket.IPPROTO_TCP)
    except OSError as exc:
        raise SystemExit(f'DNS resolution failed for {parts.hostname}: {exc}')
    if not infos:
        raise SystemExit(f'No DNS results for {parts.hostname}')
    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        if not addr.is_global:
            raise SystemExit(f'Host {parts.hostname} resolves to a non-public address {addr}')


class ValidatingRedirectHandler(urllib.request.HTTPRedirectHandler):
    """GitHub release assets 302 onto objects.githubusercontent.com, so redirects
    must stay allowed — but every hop is re-validated by the same policy."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url: str) -> bytes:
    validate_url(url)
    opener = urllib.request.build_opener(ValidatingRedirectHandler())
    with opener.open(url, timeout=60) as response:
        data = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(data) > MAX_DOWNLOAD_BYTES:
        raise SystemExit(f'Download exceeds size limit: {url}')
    return data


# Full literal URLs, not a joined base+name: the targets are pinned and the
# SHA256 check below is the real integrity guarantee.
artifacts = [
    ('poing-godot-admob-v5.1.0.zip',
     'https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/poing-godot-admob-v5.1.0.zip',
     '8c53ff52719edf6a81cc7d32a9cdaad2d9e11693c85faca25008a1c19355726f'),
    ('android-template-v4.6.3.zip',
     'https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/android-template-v4.6.3.zip',
     'f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee'),
]
archives = []
for name, url, digest in artifacts:
    data = fetch(url)
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
