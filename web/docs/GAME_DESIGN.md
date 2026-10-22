# GAME_DESIGN.md — Slime Rush: Evolution

## Pitch

A small slime crawls through the Enchanted Forest, absorbs creatures and
nutrients to grow, chooses mutations at evolution thresholds, and finally
faces the Ancient Forest Guardian. 5–8 minute sessions, one-thumb control,
honest monetization.

## Controls

- One-thumb virtual joystick, **fixed** or **floating** (Settings).
- Double-tap the joystick area to **Dash** (requires the Dash mutation).
- Auto-absorb toggle (default on): slightly enlarges the contact radius so
  nearby eligible targets are consumed without pixel-perfect contact —
  this is the "optional automatic absorption in contact radius" from the
  brief, not a magic vacuum (that's the Magnet/Vacuum mutations).

## Growth model

- `radius = BASE_RADIUS * (mass / BASE_MASS) ^ 0.33`, capped at `MAX_RADIUS`.
  Non-linear and diminishing — doubling mass does **not** double size.
- `speedMultiplier` decays smoothly toward a floor (`0.42x`) as mass grows
  (`src/lib/game/growth.ts`). Bigger = slower & more visible, not strictly
  better.
- HP scales with mass (`maxHp = 100 + mass * 0.07`), so bigger slimes survive
  longer but are easier for enemies/bosses to hit (bigger hitbox).

## Absorption rules (not "bigger always wins")

`canAbsorb(playerMass, target, activeMutations)`:

- Normal target: absorbable if `targetMass <= playerMass * 0.85`.
- **Armored** target (e.g. Stone Slug): ratio tightened to `* 0.47`
  (`0.85 * 0.55`) — you need a much bigger mass margin...
  - ...**unless** you have the **Spikes** mutation, which raises the
    effective ratio by `35%`, letting you crack armor earlier.
- Targets with `requiresAnyMutation` (reserved for future "protected"
  object types) are only absorbable if the player owns one of the listed
  mutations, regardless of mass, up to a mass-margin override.

## Evolution & mutation thresholds

`EVOLUTION_THRESHOLDS = [35, 80, 150, 260, 420, 640, 920, 1300]` mass.
Crossing a threshold pauses the run and offers **3 random mutation
choices** (weighted by rarity: common 60 / rare 30 / epic 10), excluding
mutations already at max level and mutations not yet unlocked. A rewarded
ad can add a 4th option once per evolution ("extra mutation" slot).

## The 12 mutations

| id | Name (RU) | Rarity | What it actually changes |
|---|---|---|---|
| `magnet` | Магнит | common | Pulls pellets/essence into a growing radius — stat-ish but changes positioning strategy. |
| `haste` | Ускорение | common | +speed multiplier, stacks 3x. |
| `spikes` | Шипы | common | Contact damage to enemies, cracks armored enemies, enables piercing-dash combo. **Behavioral**: turns contact from "bounce away" into "fight". |
| `poison_trail` | Ядовитый след | rare | Drops damaging puddles while moving — **behavioral**: rewards kiting pursuers through your own trail. |
| `split` | Разделение | epic | Spawns a temporary AI clone that independently absorbs nearby pellets. **Behavioral**: adds a pet/ally to manage. |
| `shield` | Щит | rare | Blocks the next hit entirely, then goes on cooldown. **Behavioral**: changes risk calculus around hazards. |
| `regen` | Регенерация | common | Passive HP/sec regen. |
| `dash` | Рывок | common | Double-tap burst movement with cooldown. **Behavioral**: enables dodging telegraphed boss attacks and crossing hazards. |
| `vacuum` | Поглощение на расстоянии | epic (locked) | Long-range pull of weak/small targets. |
| `electric` | Электроразряд | rare (locked) | Periodic AoE damage pulse around the player — **behavioral**: turns the player into a mobile damage source, key boss-DPS mutation. |
| `freeze` | Заморозка | rare (locked) | Aura that slows nearby enemies — **behavioral**: crowd control, enables outrunning packs. |
| `camouflage` | Мимикрия | epic (locked) | Shrinks enemy detection radius — **behavioral**: a stealth playstyle, avoids fights instead of winning them. |

6 of 12 are clearly behavior-changing (spikes, poison_trail, split, shield,
dash, electric, freeze, camouflage — actually 8), satisfying "at least half
must meaningfully change behavior, not just be numeric".

`vacuum`, `electric`, `freeze`, `camouflage` start **locked** and are
unlocked with meta-currency in Upgrades → Mutations, giving a clear early
progression goal within the first few runs.

## The 5 combos (data-driven, see `src/lib/game/mutations.ts#COMBOS`)

1. **Electromagnetic storm** (`magnet` + `electric`) — magnet now also serves
   the electric discharge by clustering enemies first.
2. **Toxic clones** (`poison_trail` + `split`) — clones also drop poison
   puddles.
3. **Piercing strike** (`dash` + `spikes`) — dashing deals spike damage to
   everything in the dash path (also chips boss HP).
4. **Ice armor** (`freeze` + `shield`) — blocking a hit with the shield also
   freezes the attacker.
5. **Biological vampirism** (`regen` + `vacuum`) — long-range absorbs grant
   bonus healing.

Combos are detected purely from the *set* of owned mutation ids
(`detectActiveCombos`), so adding a 13th mutation or a 6th combo later is a
data change, not an engine rewrite.

## Enemies (8 types, FSM-driven, no LLM involved)

| id | Behavior | Notes |
|---|---|---|
| `small_mushroom` | passive | Easiest food, no danger. |
| `forest_beetle` | flee | Runs once the player out-masses it. |
| `firefly` | erratic | Fast random-direction movement, high essence chance. |
| `stone_slug` | armored | Needs mass margin or Spikes. |
| `poison_toad` | hazard | Randomly drops damaging puddles. |
| `predator_flower` | ambush | Stationary, lunges when player is close. |
| `electric_beetle` | ranged | Periodic short-range shock zone. |
| `shadow_slime` | hunter | Actively chases the player; also the Guardian's summoned add. |

Each has mass/speed/detectRadius/damage/reward/essence-drop parameters in
`src/lib/game/enemies.ts` and a minimum evolution stage at which it can spawn,
so difficulty ramps with the player's own growth.

## Boss: Ancient Forest Guardian

3 phases driven by HP fraction (`src/lib/game/boss.ts`):

1. **Pursuit** (100–66% HP): chases, periodic telegraphed ground-slam AoE.
2. **Summoning** (66–33% HP): same slam, plus periodically spawns 2 Shadow
   Slime adds.
3. **Guardian's rage** (33–0% HP): faster, shorter telegraph window, more
   frequent slams and adds.

Every slam is **telegraphed**: a red circle appears at the target point for
`telegraphSec` before it deals damage, so losses come from player mistakes,
not surprise damage. The player cannot "absorb" the boss outright — damaging
it requires owning an offensive mutation (Spikes, Electric, or Dash);
without one, contact just bounces/damages the player. This forces a build
decision before the boss fight, as required by the brief.

## Run structure & rewards

- **Classic**: 6 minutes. Boss spawns once the player reaches evolution
  stage 4+ **and** 55% of the timer has elapsed. Defeating the boss before
  the timer ends → Victory. Timer elapsing without defeating an active boss
  → Defeat. No boss ever spawning (e.g. slow run) and surviving to the
  timer → Victory (a full survival run still counts).
- **Practice**: 3 minutes, no boss, no currency reward — a safe sandbox to
  learn controls/mutations.
- **Reward formula** (`calcRunReward`): `massReached*0.35 + durationSec*0.12
  + (bossDefeated ? 120 : 0)`, multiplied by `0.6` on defeat, `0` if
  abandoned. Deterministic and unit-tested.

## Meta-progression

- **Permanent upgrades** (Upgrades → Characteristics): starting mass,
  movement speed, essence drop chance — each with increasing currency cost.
- **Mutation unlocks** (Upgrades → Mutations): 4 locked mutations purchased
  with currency.
- **Collection**: 8 creatures + the boss (silhouette until first
  encountered), 8 slime evolution "forms" (unlocked by reaching mass
  thresholds), achievements (first victory, guardian slayer, colossal
  slime, persistent slime).
- First meaningful unlocks happen inside the **first run** already
  (creatures get discovered on sight, forms on first threshold crossed).

## Visual style

Soft gradients, glowing mushrooms/crystals, semi-transparent gradient-filled
slime body with squash/stretch on movement/dash, a bright pulsing "core",
expressive eyes that track movement direction, and mutation-specific visual
overlays (spikes ring, shield ring, magnet ring, frost aura). All rendered
procedurally via Canvas2D — no external art assets, so there is no licensing
risk, and it maps cleanly to a future Godot `AnimatedSprite2D` +
`GPUParticles2D` + shader implementation (see `ARCHITECTURE.md`).

## Audio

Every effect (move/absorb/evolve/mutation/attack/damage/victory/defeat/click
/boss) is synthesized at runtime with the Web Audio API — original, zero
licensing risk. Music is off by default and no track is bundled, matching
the brief's requirement that the game be complete without music.
