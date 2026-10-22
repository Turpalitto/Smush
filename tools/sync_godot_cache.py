#!/usr/bin/env python3
"""Synchronizes .godot/global_script_class_cache.cfg from GDScript class_name declarations."""
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+extends\s+([A-Za-z_][A-Za-z0-9_]*))?", re.MULTILINE)
EXTENDS_RE = re.compile(r"^\s*extends\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)


def main() -> None:
    entries: list[dict[str, str]] = []
    for gd_path in sorted(ROOT.rglob("*.gd")):
        rel = gd_path.relative_to(ROOT).as_posix()
        if rel.startswith(".godot/"):
            continue
        text = gd_path.read_text(encoding="utf-8")
        m_class = CLASS_RE.search(text)
        if not m_class:
            continue
        cls_name = m_class.group(1)
        base_name = m_class.group(2)
        if not base_name:
            m_ext = EXTENDS_RE.search(text)
            base_name = m_ext.group(1) if m_ext else "RefCounted"
        entries.append(
            {
                "base": base_name,
                "class": cls_name,
                "path": f"res://{rel}",
            }
        )

    entries.sort(key=lambda e: e["class"])
    out_dir = ROOT / ".godot"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "global_script_class_cache.cfg"

    lines = ["list=["]
    for idx, item in enumerate(entries):
        comma = "," if idx + 1 < len(entries) else ""
        lines.append("{")
        lines.append(f'"base": &"{item["base"]}",')
        lines.append(f'"class": &"{item["class"]}",')
        lines.append('"icon": "",')
        lines.append('"is_abstract": false,')
        lines.append('"is_tool": false,')
        lines.append('"language": &"GDScript",')
        lines.append(f'"path": "{item["path"]}"')
        lines.append(f"}}{comma}")
    lines.append("]")
    out_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Synced {len(entries)} global GDScript classes -> {out_file.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
