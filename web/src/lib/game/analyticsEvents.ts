export const ANALYTICS_EVENTS = [
  "first_launch",
  "tutorial_started",
  "tutorial_completed",
  "run_started",
  "run_finished",
  "run_duration",
  "mutation_selected",
  "boss_encountered",
  "boss_defeated",
  "rewarded_ad_offered",
  "rewarded_ad_completed",
  "purchase_started",
  "purchase_completed",
  "session_end",
] as const;

export type AnalyticsEventName = (typeof ANALYTICS_EVENTS)[number];
