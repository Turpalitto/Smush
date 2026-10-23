extends Node
## Central typed event bus (Autoload: Events) decoupling gameplay, UI, audio, and analytics.

signal game_state_changed(old_state: int, new_state: int)
signal locale_changed(new_locale: String)
signal settings_changed()

# Gameplay & Slime signals
signal player_mass_changed(current_mass: float, radius: float)
signal player_hp_changed(current_hp: float, max_hp: float)
signal player_damaged(amount: float, source_id: String)
signal player_shield_triggered()
signal player_shield_recharged()
signal entity_absorbed(entity_id: String, mass_gained: float, xp_gained: float, world_pos: Vector2)
signal essence_collected(amount: int, run_total: int)
signal narrow_passage_blocked()

# Evolution & Mutations
signal evolution_progress_changed(current_xp: float, threshold_xp: float, level: int)
## The body changed shape, not just a number: stage is 1..15 on the growth ladder.
signal growth_stage_changed(stage: int, name_key: String)
signal mutation_draft_requested(choices: Array)
signal mutation_applied(mutation_id: String, new_level: int)
signal synergy_activated(synergy_id: String)
signal active_skill_cooldown_updated(skill_id: String, remaining: float, duration: float)

# Run & Boss
signal run_started(mode_id: String)
signal run_timer_updated(elapsed_sec: float, target_sec: float)
signal miniboss_spawned(enemy_id: String)
signal boss_spawned(boss_id: String, max_hp: float)
signal boss_updated(current_hp: float, max_hp: float, phase: int)
signal boss_defeated(boss_id: String)
signal run_finished(victory: bool, summary: Dictionary)

# Progression, Monetization & Tutorial
signal upgrade_purchased(upgrade_id: String, new_level: int)
signal mutation_unlocked_permanently(mutation_id: String)
signal creature_discovered(creature_id: String)
signal achievement_unlocked(achievement_id: String, reward_essence: int)
signal slime_form_changed(form_id: String)
signal tutorial_step_shown(step_index: int, text_key: String)
signal tutorial_completed()
signal toast_requested(message: String, color: Color)
