#!/usr/bin/env bash
set -euo pipefail
# Builds a self-contained standalone Linux x86_64 Desktop Playtest archive for
# SLIME RUSH: EVOLUTION (no Godot Editor installation required on target Linux PC).
#
# Usage:
#   ./scripts/build_linux_playtest.sh [output_tar_gz]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ARCHIVE="${1:-$ROOT_DIR/deliverables/SlimeRushEvolution_Linux_x86_64_Playtest_v1.0.0.tar.gz}"
TEMPLATE_BIN="${LINUX_RELEASE_TEMPLATE:-/tmp/godot45/linux_release.x86_64}"
if [[ ! -f "$TEMPLATE_BIN" ]]; then
  echo "Error: Godot 4.5 Linux release template not found at $TEMPLATE_BIN" >&2
  exit 1
fi

COMMIT_SHA="$(git rev-parse HEAD)"
GODOT_VER="$("${GODOT_BIN:-/usr/local/bin/godot4}" --version | head -n 1)"

python3 tools/sync_godot_cache.py

STAGE_DIR="$(mktemp -d /tmp/smush_linux_playtest.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

APP_DIR="$STAGE_DIR/SlimeRushEvolution_Linux_x86_64"
mkdir -p "$APP_DIR"

cp "$TEMPLATE_BIN" "$APP_DIR/SlimeRushEvolution.x86_64"
chmod +x "$APP_DIR/SlimeRushEvolution.x86_64"

python3 tools/build_pck.py --exclude-tests "$APP_DIR/SlimeRushEvolution.pck"

cat > "$APP_DIR/launch_playtest.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/SlimeRushEvolution.x86_64" --rendering-method mobile "$@"
EOF
chmod +x "$APP_DIR/launch_playtest.sh"

cat > "$APP_DIR/launch_clean_profile.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Starts SLIME RUSH: EVOLUTION with an isolated clean save profile so you can test
# first-time onboarding and zero-Essence progression WITHOUT modifying your main save.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_DIR="${SLIME_RUSH_CLEAN_PROFILE_DIR:-$(mktemp -d /tmp/slime_rush_clean_playtest.XXXXXX)}"
echo "Starting SLIME RUSH: EVOLUTION on isolated clean profile: $CLEAN_DIR"
echo "(Your normal save in ~/.local/share/godot/app_userdata/Slime Rush- Evolution/ is untouched.)"
XDG_DATA_HOME="$CLEAN_DIR" exec "$DIR/SlimeRushEvolution.x86_64" --rendering-method mobile "$@"
EOF
chmod +x "$APP_DIR/launch_clean_profile.sh"

cat > "$APP_DIR/BUILD_INFO.txt" << EOF
Game: SLIME RUSH: EVOLUTION (v1.0.0 Personal Playtest Build)
Platform: Linux x86_64 Standalone Desktop (Wayland / X11, Vulkan 1.0+ / OpenGL 3 fallback)
Godot Engine Runtime: $GODOT_VER (official linux_release.x86_64 template)
Git Branch: arena/5c95bae5-smush
Git Commit SHA: $COMMIT_SHA
Live Ads / Real-Money IAP / Cloud Analytics: DISABLED (offline stubs only; zero network calls)
Default Background Music: OFF (toggleable in Settings)
EOF

cat > "$APP_DIR/PLAYTEST_GUIDE_RU_EN.txt" << 'EOF'
========================================================================
SLIME RUSH: EVOLUTION — КРАТКАЯ ПАМЯТКА ДЛЯ ЛИЧНОГО ПЛЕЙТЕСТА (RU / EN)
========================================================================

1. УСТАНОВКА И ЗАПУСК (Linux x86_64, без установки Godot)
------------------------------------------------------------------------
Распакуйте архив и запустите игру:
  tar -xzf SlimeRushEvolution_Linux_x86_64_Playtest_v1.0.0.tar.gz
  cd SlimeRushEvolution_Linux_x86_64
  ./launch_playtest.sh

(Если на вашей машине старый драйвер без Vulkan, можно запустить с OpenGL:
  ./launch_playtest.sh --rendering-driver opengl3 )

2. ЧИСТЫЙ ПРОФИЛЬ БЕЗ ПОТЕРИ ОСНОВНОГО СОХРАНЕНИЯ
------------------------------------------------------------------------
Чтобы проверить первый запуск, обучение и баланс с нуля, НЕ трогая свой
обычный сейв (~/.local/share/godot/app_userdata/Slime Rush- Evolution/):
  ./launch_clean_profile.sh

3. УПРАВЛЕНИЕ
------------------------------------------------------------------------
• Движение:
  - Мышь / тачпад / сенсорный экран: зажмите левую кнопку мыши в нижней
    части экрана и тяните виртуальный джойстик (как пальцем на телефоне).
  - Клавиатура: WASD или стрелки.
• Рывок (Dash — появляется после выбора мутации «Рывок»):
  - Кнопка «РЫВОК / DASH» справа внизу, клавиши Space / Shift, либо
    быстрый двойной тап по зоне джойстика.
• Разделение (Split — появляется после выбора мутации «Деление»):
  - Кнопка «КОПИЯ / SPLIT» справа внизу (над Рывком), либо клавиши Q / E.
• Пауза / Назад:
  - Кнопка «II» в правом верхнем углу, либо клавиши Esc / P.

4. НАСТРОЙКИ (Экран «Настройки / Settings» с главного экрана)
------------------------------------------------------------------------
• Тип джойстика: кнопка «Тип джойстика: Плавающий / Фиксированный»
  (по умолчанию — Плавающий с динамическим следованием базы за разворотом).
• Звук и музыка: ползунок громкости эффектов + переключатель
  «Включить фоновую музыку» (по умолчанию музыка ВЫКЛЮЧЕНА) + ползунок музыки.
• Язык (RU / EN): кнопка «Язык / Language: Русский / English» мгновенно
  переключает весь интерфейс.

5. НА ЧТО ПОСМОТРЕТЬ В ПЕРВОМ ПЛЕЙТЕСТЕ (6 ПУНКТОВ ДЛЯ ФИДБЕКА)
------------------------------------------------------------------------
1) Удобство движения и разворотов (особенно резкая смена направления).
2) Понятность съедобного и опасного (зелёные vs красные кольца существ, Лужи/шипы).
3) Ощущение роста и мутаций (темп эволюции, заметность эффектов и синергий).
4) Читаемость атак босса (коридор рывка Древнего стража, круги ударов, окно уязвимости).
5) Места, где скучно, слишком сложно или непонятно.
6) Желание сыграть ещё один забег после победы или поражения.

========================================================================
ENGLISH QUICK SUMMARY
========================================================================
• Launch (normal save): ./launch_playtest.sh
• Launch (isolated clean profile, preserves main save): ./launch_clean_profile.sh
• Move: Left-click & drag virtual joystick OR WASD / Arrow keys
• Dash (once drafted): Bottom-right DASH button, Space / Shift, or quick double-tap
• Split (once drafted): Bottom-right SPLIT button, or Q / E
• Pause: Top-right "II" button, or Esc / P
• Settings (Main Menu -> Settings): Toggle Floating/Fixed Joystick, SFX slider,
  Background Music toggle (OFF by default), and Russian/English language.
EOF

cat licenses/THIRD_PARTY_LICENSES.txt > "$APP_DIR/THIRD_PARTY_NOTICES.txt" 2>/dev/null || \
  cp resources/fonts/LICENSE-DejaVu.txt "$APP_DIR/THIRD_PARTY_NOTICES.txt"

mkdir -p "$(dirname "$OUT_ARCHIVE")"
tar -C "$STAGE_DIR" -czf "$OUT_ARCHIVE" SlimeRushEvolution_Linux_x86_64
echo "Built standalone Linux x86_64 playtest archive: $OUT_ARCHIVE ($(du -h "$OUT_ARCHIVE" | cut -f1))"
