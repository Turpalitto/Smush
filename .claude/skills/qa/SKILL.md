---
name: qa
description: Run the SLIME RUSH native QA (scripts/run_qa.sh) and, for gameplay changes, the packed check through Godot's own exporter from outside the source tree. Reports only checks executed in this run.
disable-model-invocation: true
---

# QA: SLIME RUSH

Run only when the owner asks for it (`/qa`). Do not commit, push or merge.

## 0. Godot binary

This Mac has `godot` at `~/.local/bin/godot` (4.5.stable). `run_qa.sh` defaults to `godot4`,
so set `GODOT` once and pass it on:

```bash
GODOT="${GODOT:-/Users/turpal/.local/bin/godot}"
```

## 1. Native QA

```bash
cd /Users/turpal/Documents/smush
GODOT_BIN="$GODOT" ./scripts/run_qa.sh
```

Record the exact `TOTAL ASSERTIONS: ... PASSED, ... FAILED` line and the exit code from this run.
`run_qa.sh` ignores Godot's shutdown messages (`resources still in use at exit`, `leaked at exit`)
by owner decision and prints how many it ignored. Any non-zero exit is a real failure: quote the
lines that caused it, and stop before step 2.

## 2. Packed check (gameplay changes only)

Run this when the change touches `.gd`, `.tscn`, `.tres`, `.gdshader` or game data.
Skip it for docs-only changes and say so.

This uses Godot's own `--export-pack` on a copy of the project, with the export filter that
excludes `tests/` removed in the copy only. The repository's `export_presets.cfg` is not changed.
`tools/build_pck.py` is not used here: it packs raw PNG files without the import remaps, so
every imported texture fails to load from its pack.

```bash
SRC=/Users/turpal/Documents/smush
SCRATCH="$(mktemp -d)"           # outside the source tree
rsync -a --exclude '/builds' --exclude '/deliverables' --exclude '/.git' "$SRC/" "$SCRATCH/proj/"
cd "$SCRATCH/proj"
python3 - <<'EOF'
import re
p = "export_presets.cfg"
s = open(p).read()
open(p, "w").write(re.sub(r'exclude_filter="[^"]*"', 'exclude_filter=""', s))
EOF
"$GODOT" --headless --path . --export-pack "Android Offline Debug APK" "$SCRATCH/slime_rush.pck"
cd "$SCRATCH"
"$GODOT" --headless --main-pack "$SCRATCH/slime_rush.pck" --quit-after 600 res://tests/TestRunner.tscn > "$SCRATCH/pck.log" 2>&1
echo "exit=$?  log=$SCRATCH/pck.log"
grep -E "TOTAL ASSERTIONS|\[FAIL\]" "$SCRATCH/pck.log"
```

Keep the `SCRATCH` path in the report, not just the file name.

## 3. Interpreting the results

- **Exit-time messages** (`ERROR: N resources still in use at exit`, `leaked at exit`,
  `Leaked instance`) come from Godot shutdown. They are not test failures and `run_qa.sh`
  ignores them. Still list the count in the report, since they are not fixed.
- **Test failures** are `[FAIL]` lines and `TOTAL ... FAILED` above zero.
- **Known in the packed run:** tests that read `.wav` files with `FileAccess` (AudioChimes,
  GrowthLadder bell checks, FullGameIntegration chime files) fail in the export, because Godot
  stores those as imported samples. These failures are in the test code, not proven to be a
  game bug. Report them as-is, do not hide them and do not call them passes.
- If the packed run cannot load textures, report it as unverified. Do not change the packing
  method to hide it.

## 4. Report

Write a short report in Russian with exactly these sections:

- **Выполнено сейчас:** each command actually run in this session, with its result line and exit code.
- **Не выполнено / пропущено:** each skipped step and the reason.
- **Не проверено людьми:** always list the human checks that automated QA cannot cover
  (feel of controls, visual review, real Android FPS). Automated QA does not prove them.

Do not copy results from `PROGRESS.md`, `TEST_REPORT.md` or any earlier run into this report.
