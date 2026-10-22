import {
  pgTable,
  text,
  integer,
  boolean,
  timestamp,
  jsonb,
  serial,
  uniqueIndex,
} from "drizzle-orm/pg-core";

// Anonymous device-bound player profile (mobile-style local progress,
// mirrored server-side so progress survives reinstalls if the device id
// is restored). No personal data is stored.
export const players = pgTable("players", {
  id: text("id").primaryKey(), // client-generated UUID (device id)
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).defaultNow().notNull(),
  currency: integer("currency").default(0).notNull(),
  totalRuns: integer("total_runs").default(0).notNull(),
  totalWins: integer("total_wins").default(0).notNull(),
  totalBossKills: integer("total_boss_kills").default(0).notNull(),
  bestMass: integer("best_mass").default(0).notNull(),
  bestDurationSec: integer("best_duration_sec").default(0).notNull(),
  // Map<upgradeKey, level>
  upgrades: jsonb("upgrades").$type<Record<string, number>>().default({}).notNull(),
  // mutation ids unlocked beyond the default starter pool
  unlockedMutations: jsonb("unlocked_mutations").$type<string[]>().default([]).notNull(),
  discoveredCreatures: jsonb("discovered_creatures").$type<string[]>().default([]).notNull(),
  discoveredForms: jsonb("discovered_forms").$type<number[]>().default([]).notNull(),
  achievements: jsonb("achievements").$type<string[]>().default([]).notNull(),
  settings: jsonb("settings")
    .$type<{
      joystickMode: "fixed" | "floating";
      sfxVolume: number;
      musicVolume: number;
      autoAbsorb: boolean;
      language: "ru" | "en";
    }>()
    .default({ joystickMode: "floating", sfxVolume: 0.8, musicVolume: 0, autoAbsorb: true, language: "ru" })
    .notNull(),
  noAds: boolean("no_ads").default(false).notNull(),
  ownedCosmetics: jsonb("owned_cosmetics").$type<string[]>().default([]).notNull(),
  equippedCosmetic: text("equipped_cosmetic"),
});

export const runs = pgTable("runs", {
  id: text("id").primaryKey(), // client-generated UUID
  playerId: text("player_id").notNull(),
  mode: text("mode").notNull(), // 'classic' | 'practice'
  startedAt: timestamp("started_at", { withTimezone: true }).defaultNow().notNull(),
  endedAt: timestamp("ended_at", { withTimezone: true }),
  result: text("result"), // 'victory' | 'defeat' | 'abandoned'
  massReached: integer("mass_reached").default(0).notNull(),
  durationSec: integer("duration_sec").default(0).notNull(),
  mutationsChosen: jsonb("mutations_chosen").$type<string[]>().default([]).notNull(),
  bossDefeated: boolean("boss_defeated").default(false).notNull(),
  currencyEarned: integer("currency_earned").default(0).notNull(),
  rewardedDoubleUsed: boolean("rewarded_double_used").default(false).notNull(),
  rewardedReviveUsed: boolean("rewarded_revive_used").default(false).notNull(),
});

export const analyticsEvents = pgTable("analytics_events", {
  id: serial("id").primaryKey(),
  playerId: text("player_id").notNull(),
  eventName: text("event_name").notNull(),
  payload: jsonb("payload").$type<Record<string, unknown>>().default({}).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

// Idempotency ledger for rewarded-ad grants, prevents double-granting the
// same reward slot (e.g. one revive per run) even on client retries.
export const adRewardGrants = pgTable(
  "ad_reward_grants",
  {
    id: serial("id").primaryKey(),
    playerId: text("player_id").notNull(),
    runId: text("run_id").notNull(),
    slot: text("slot").notNull(), // 'revive' | 'double' | 'extra_mutation'
    grantedAt: timestamp("granted_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => ({
    runSlotUnique: uniqueIndex("ad_reward_grants_run_slot_unique").on(table.runId, table.slot),
  }),
);

// Sandbox purchase ledger. This is a TEST adapter, not a real Google Play
// Billing integration (see MONETIZATION.md).
export const purchases = pgTable("purchases", {
  id: serial("id").primaryKey(),
  playerId: text("player_id").notNull(),
  productId: text("product_id").notNull(),
  status: text("status").default("completed").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
