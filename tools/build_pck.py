#!/usr/bin/env python3
"""
Builds a standard Godot 4 .pck archive (GDPC format v2) from the repository files.
Allows testing packed distribution via `godot4 --main-pack` and WebAssembly preview.
"""
from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# .ogg is not optional: the three music loops are the only audio in the pack that
# is not a .wav, and leaving the extension out of this set built packs that
# shipped with no music at all - silently, because nothing crashed. The packaged
# QA step caught it as "Music file exists: res://audio/music/theme_menu.ogg".
INCLUDE_EXTS = {".gd", ".tscn", ".tres", ".gdshader", ".json", ".png", ".wav", ".ogg", ".cfg", ".ttf"}
EXCLUDE_DIRS = {".git", "builds", "deliverables", "reports", "node_modules", "__pycache__", "tools", "src", "web", "android"}
EXCLUDE_FILES = {"project.godot", "export_presets.cfg", "package.json", "package-lock.json", "tsconfig.json", "drizzle.config.json"}


def collect_files(exclude_tests: bool = False) -> list[tuple[str, bytes]]:
    items: list[tuple[str, bytes]] = []
    # Include project.godot and .godot/global_script_class_cache.cfg
    proj = ROOT / "project.godot"
    items.append(("res://project.godot", proj.read_bytes()))
    cache_cfg = ROOT / ".godot/global_script_class_cache.cfg"
    if cache_cfg.exists():
        items.append(("res://.godot/global_script_class_cache.cfg", cache_cfg.read_bytes()))

    excl_dirs = set(EXCLUDE_DIRS)
    if exclude_tests:
        excl_dirs.add("tests")

    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in excl_dirs or rel.parts[0].startswith("."):
            continue
        if p.name in EXCLUDE_FILES:
            continue
        if p.suffix.lower() in INCLUDE_EXTS or rel.parts[0] == "licenses" or p.name.startswith("LICENSE") or p.name == "LICENSE-DejaVu.txt":
            items.append((f"res://{rel.as_posix()}", p.read_bytes()))
    return items


def build_pck(out_path: Path, ver_major: int = 4, ver_minor: int = 5, ver_patch: int = 0, exclude_tests: bool = False) -> None:
    files = collect_files(exclude_tests=exclude_tests)

    # Pack format v2 (supported by Godot 4.0 - 4.7+):
    # Header: magic(4s="GDPC"), pack_version(u32=2), ver_major(u32), ver_minor(u32), ver_patch(u32),
    #         flags(u32=0), file_base(u64), reserved(16*u32)
    header_size = 4 + 4 * 5 + 8 + 16 * 4  # 96 bytes

    dir_entries_meta: list[tuple[bytes, int, bytes]] = []
    dir_size = 4  # file_count (u32)
    for res_path, data in files:
        raw_p = res_path.encode("utf-8") + b"\x00"
        pad_len = (4 - (len(raw_p) % 4)) % 4
        raw_p += b"\x00" * pad_len
        md5 = hashlib.md5(data).digest()
        dir_entries_meta.append((raw_p, len(data), md5))
        # path_len(u32) + path_bytes + ofs(u64) + size(u64) + md5(16) + flags(u32)
        dir_size += 4 + len(raw_p) + 8 + 8 + 16 + 4

    file_base = header_size + dir_size
    if file_base % 16 != 0:
        file_base += 16 - (file_base % 16)

    # Compute absolute offsets inside pack (in format v2 with flags=0, offsets are from start of pack or file_base?
    # Note: In Godot PackFormat v2, file_base is added to entry offset! So entry offset is relative to file_base!)
    offsets: list[int] = []
    cur_rel = 0
    for _idx, (_, sz, _) in enumerate(dir_entries_meta):
        offsets.append(cur_rel)
        cur_rel += sz
        if cur_rel % 16 != 0:
            cur_rel += 16 - (cur_rel % 16)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("wb") as f:
        f.write(b"GDPC")
        f.write(struct.pack("<IIIIIQ", 2, ver_major, ver_minor, ver_patch, 0, file_base))
        f.write(b"\x00" * 64)
        f.write(struct.pack("<I", len(files)))
        for (raw_p, sz, md5), rel_ofs in zip(dir_entries_meta, offsets):
            f.write(struct.pack("<I", len(raw_p)))
            f.write(raw_p)
            f.write(struct.pack("<QQ", rel_ofs, sz))
            f.write(md5)
            f.write(struct.pack("<I", 0))

        cur_pos = f.tell()
        if cur_pos < file_base:
            f.write(b"\x00" * (file_base - cur_pos))

        for (_, data), rel_ofs in zip(files, offsets):
            target = file_base + rel_ofs
            cur = f.tell()
            if cur < target:
                f.write(b"\x00" * (target - cur))
            f.write(data)

    print(f"Built {out_path} ({out_path.stat().st_size / 1024:.1f} KB, {len(files)} files)")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--exclude-tests"]
    excl_t = "--exclude-tests" in sys.argv[1:]
    dest = Path(args[0]) if args else Path("/tmp/slime_rush.pck")
    build_pck(dest, exclude_tests=excl_t)
