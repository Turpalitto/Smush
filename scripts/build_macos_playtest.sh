#!/usr/bin/env bash
set -euo pipefail
# Builds a self-contained macOS Playtest .app (Universal x86_64 + arm64) for
# SLIME RUSH: EVOLUTION, ad-hoc signed for local playtesting (NOT Developer ID, NOT notarized).
#
# Usage:
#   ./scripts/build_macos_playtest.sh [output_dir]
#
# Requires: Godot 4.5 with macOS export templates installed in
#   ~/Library/Application Support/Godot/export_templates/4.5.stable/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-$HOME/godot45/Godot.app/Contents/MacOS/Godot}"
OUT_DIR="${1:-$ROOT_DIR/deliverables}"
PRESET_NAME="macOS Universal (Ad-hoc)"
APP_NAME="SlimeRushEvolution.app"
VERSION="1.0.0"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Error: Godot binary not found at $GODOT_BIN (set GODOT_BIN)" >&2
  exit 1
fi

GODOT_VER="$("$GODOT_BIN" --version | head -n 1)"
COMMIT_SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

python3 tools/sync_godot_cache.py

BUILD_ROOT="$ROOT_DIR/builds/macos"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
APP_PATH="$BUILD_ROOT/$APP_NAME"

echo "Exporting $PRESET_NAME with $GODOT_VER ..."
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "$PRESET_NAME" "$APP_PATH" 2>&1 \
  | grep -vE "^\[ *[0-9]+% \]" || true

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: export did not produce $APP_PATH" >&2
  exit 1
fi

# Re-apply ad-hoc signature: export rewrites the binary and invalidates the template signature.
codesign --force --deep --sign - --options runtime "$APP_PATH" 2>/dev/null || \
  codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

BIN_PATH="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
ARCH_INFO="$(file -b "$APP_PATH/Contents/MacOS/$BIN_PATH")"

mkdir -p "$OUT_DIR"
STAGE_DIR="$(mktemp -d /tmp/smush_macos_playtest.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

PKG_DIR="$STAGE_DIR/SlimeRushEvolution_macOS_Universal"
mkdir -p "$PKG_DIR"
ditto "$APP_PATH" "$PKG_DIR/$APP_NAME"

cat > "$PKG_DIR/launch_clean_profile.command" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Starts SLIME RUSH: EVOLUTION on an ISOLATED clean profile (fresh save, zero Essence),
# so first-run onboarding can be tested without touching the main save.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_HOME="${SLIME_RUSH_CLEAN_HOME:-$(mktemp -d /tmp/slime_rush_clean_home.XXXXXX)}"
echo "Clean profile: $CLEAN_HOME"
echo "Your normal save in ~/Library/Application Support/Godot/app_userdata/ is untouched."
exec env HOME="$CLEAN_HOME" "$DIR/SlimeRushEvolution.app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$DIR/SlimeRushEvolution.app/Contents/Info.plist")" "$@"
EOF
chmod +x "$PKG_DIR/launch_clean_profile.command"

cat > "$PKG_DIR/BUILD_INFO.txt" << EOF
Game: SLIME RUSH: EVOLUTION (v$VERSION Personal Playtest Build)
Platform: macOS Universal (arm64 + x86_64), Metal renderer (Forward Mobile)
Godot Engine: $GODOT_VER
Git Branch: $BRANCH
Git Commit SHA: $COMMIT_SHA
Bundle ID: com.turpalitto.slimerush
Code signature: ad-hoc ("codesign --sign -"), hardened runtime flag set.
  This is NOT a Developer ID signature and the app is NOT notarized by Apple.
Live Ads / Real-Money IAP / Cloud Analytics: DISABLED (offline stubs only)
Default Background Music: OFF (toggleable in Settings)
EOF

cat licenses/THIRD_PARTY_LICENSES.txt > "$PKG_DIR/THIRD_PARTY_NOTICES.txt" 2>/dev/null || \
  cp resources/fonts/LICENSE-DejaVu.txt "$PKG_DIR/THIRD_PARTY_NOTICES.txt"

cat > "$PKG_DIR/PLAYTEST_GUIDE_RU_EN.txt" << 'EOF'
========================================================================
SLIME RUSH: EVOLUTION — ПАМЯТКА ДЛЯ ЛИЧНОГО ПЛЕЙТЕСТА НА macOS (RU / EN)
========================================================================

1. ЗАПУСК
------------------------------------------------------------------------
Распакуйте архив (двойной клик в Finder) и перетащите
SlimeRushEvolution.app в «Программы» (или запускайте прямо из папки).

Запуск с чистым профилем (новое сохранение, 0 эссенции, ваш основной
прогресс не затрагивается):
  двойной клик по launch_clean_profile.command
(при первом запуске macOS может спросить разрешение для Terminal —
 это нормально, скрипт лишь подменяет HOME для процесса игры).

Если macOS блокирует запуск («Не удалось проверить разработчика»):
  Системные настройки → Конфиденциальность и безопасность →
  «Всё равно открыть». Приложение подписано ad-hoc, а не Developer ID,
  и не нотаризовано — это ожидаемо для локального плейтеста.

2. УПРАВЛЕНИЕ
------------------------------------------------------------------------
• Движение:
  - Мышь/тачпад: зажмите левую кнопку в нижней части окна и тяните
    виртуальный джойстик (как пальцем на телефоне).
  - Клавиатура: WASD или стрелки.
• Рывок (после мутации «Рывок»): кнопка «РЫВОК» справа внизу,
  Shift / Space, либо быстрый двойной тап по зоне джойстика.
• Двойник/Деление (после мутации): кнопка справа внизу, клавиши Q / E.
• Выбор мутации в драфте: клик по карточке или клавиши 1 / 2 / 3.
• Пауза: кнопка «II» справа вверху, либо Esc / P.

3. НА ЧТО ПОСМОТРЕТЬ
------------------------------------------------------------------------
1) Удобство движения и резких разворотов мышью/клавиатурой.
2) Понятность съедобного и опасного.
3) Ощущение роста, мутаций и синергий.
4) Читаемость телеграфов и атак Стража.
5) Где скучно / слишком сложно / непонятно.
6) Хочется ли ещё один забег.

========================================================================
ENGLISH QUICK SUMMARY
========================================================================
• Launch: double-click SlimeRushEvolution.app
• Clean profile: double-click launch_clean_profile.command
• Move: left-click & drag the virtual joystick (bottom area) OR WASD / arrows
• Dash: DASH button (bottom-right), Shift / Space, or quick double-tap
• Split/Clone: bottom-right button, or Q / E
• Mutation draft: click a card, or press 1 / 2 / 3
• Pause: "II" button (top-right), or Esc / P
• Ad-hoc signed, not notarized: if Gatekeeper blocks it, use
  System Settings → Privacy & Security → "Open Anyway".
EOF

ARCHIVE="$OUT_DIR/SlimeRushEvolution_macOS_Universal_Playtest_v$VERSION.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$PKG_DIR" "$ARCHIVE"

SHA_APP="$(shasum -a 256 "$APP_PATH/Contents/MacOS/$BIN_PATH" | cut -d' ' -f1)"
SHA_ZIP="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"

cat > "$OUT_DIR/SlimeRushEvolution_macOS_Universal_Playtest_v$VERSION.sha256" << EOF
$SHA_ZIP  $(basename "$ARCHIVE")
$SHA_APP  $APP_NAME/Contents/MacOS/$BIN_PATH
EOF

cat > "$OUT_DIR/SlimeRushEvolution_macOS_Universal_Playtest_v$VERSION.build.json" << EOF
{
  "game": "Slime Rush: Evolution",
  "version": "$VERSION",
  "platform": "macOS",
  "architecture": "universal (arm64 + x86_64)",
  "godot_version": "$GODOT_VER",
  "git_branch": "$BRANCH",
  "git_commit": "$COMMIT_SHA",
  "bundle_id": "com.turpalitto.slimerush",
  "signing": "ad-hoc (codesign --sign -), hardened runtime; not Developer ID, not notarized",
  "export_preset": "$PRESET_NAME",
  "app_path": "$APP_PATH",
  "archive_path": "$ARCHIVE",
  "archive_sha256": "$SHA_ZIP",
  "binary_sha256": "$SHA_APP",
  "binary_file_info": "$ARCH_INFO"
}
EOF

echo "------------------------------------------------------------"
echo "App:     $APP_PATH"
echo "Archive: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "Godot:   $GODOT_VER"
echo "Commit:  $COMMIT_SHA ($BRANCH)"
echo "SHA256 (zip):    $SHA_ZIP"
echo "SHA256 (binary): $SHA_APP"
echo "Binary:  $ARCH_INFO"
