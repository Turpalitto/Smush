extends Node
## Privacy-friendly, consent-respecting analytics & KPI engine (Autoload: Analytics).
## Collects zero PII. Tracks all 14 required product events and retention/monetization KPIs.

const VALID_EVENTS: PackedStringArray = [
	"first_launch",
	"tutorial_started",
	"tutorial_completed",
	"run_started",
	"run_finished",
	"run_duration",
	"mutation_selected",
	"boss_encountered",
	"boss_defeated",
	"grove_awakened",
	"rewarded_ad_offered",
	"rewarded_ad_completed",
	"purchase_started",
	"purchase_completed",
	"session_end"
]

var _session_start_unix: float = 0.0
var _session_open: bool = false
var _event_log: Array[Dictionary] = []
var max_buffered_events: int = 250


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_session()
	_record_cohort_day()

	var stats: Dictionary = SaveData.data.get("stats", {})
	if not bool(stats.get("first_launch_recorded", false)):
		stats["first_launch_recorded"] = true
		SaveData.save_to_disk()
		track("first_launch", {"version": BuildConfig.APP_VERSION})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		end_session()


func _record_cohort_day() -> void:
	if SaveData.data.is_empty():
		return
	var stats: Dictionary = SaveData.data["stats"]
	var today_bucket: int = int(Time.get_unix_time_from_system() / 86400.0)
	var days: Array = stats.get("active_days", [])
	if not days.has(today_bucket):
		days.append(today_bucket)
		stats["active_days"] = days
		SaveData.save_to_disk()


func has_user_consent() -> bool:
	return bool(SaveData.get_setting("analytics_consent", false))


func track(event_name: String, props: Dictionary = {}) -> void:
	if not VALID_EVENTS.has(event_name):
		push_warning("Unknown analytics event: " + event_name)
		return

	# Always update anonymous local aggregate counters needed for achievements/stats,
	# while gating external/detailed event telemetry strictly on user consent.
	_update_local_aggregates(event_name, props)

	if not has_user_consent():
		return

	var sanitized := _strip_pii(props)
	var record := {
		"event": event_name,
		"ts": int(Time.get_unix_time_from_system()),
		"props": sanitized
	}
	_event_log.append(record)
	if _event_log.size() > max_buffered_events:
		_event_log.pop_front()


func _strip_pii(props: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	var forbidden := ["email", "name", "phone", "ip", "gps", "device_id", "advertising_id"]
	for k in props.keys():
		var ks := str(k).to_lower()
		if forbidden.has(ks):
			continue
		clean[ks] = props[k]
	return clean


func _update_local_aggregates(event_name: String, props: Dictionary) -> void:
	if SaveData.data.is_empty():
		return
	var st: Dictionary = SaveData.data["stats"]
	match event_name:
		"session_end":
			st["session_count"] = int(st.get("session_count", 0)) + 1
			st["session_time_sec"] = float(st.get("session_time_sec", 0.0)) + maxf(0.0, float(props.get("duration_sec", 0.0)))
		"run_duration":
			st["finished_run_count"] = int(st.get("finished_run_count", 0)) + 1
			st["finished_run_time_sec"] = float(st.get("finished_run_time_sec", 0.0)) + maxf(0.0, float(props.get("seconds", 0.0)))
		"tutorial_started":
			st["tutorial_starts"] = int(st.get("tutorial_starts", 0)) + 1
		"tutorial_completed":
			st["tutorial_completions"] = int(st.get("tutorial_completions", 0)) + 1
		"rewarded_ad_offered":
			st["rewarded_offered"] = int(st.get("rewarded_offered", 0)) + 1
		"rewarded_ad_completed":
			st["rewarded_completed"] = int(st.get("rewarded_completed", 0)) + 1
		"boss_encountered":
			st["boss_encounters"] = int(st.get("boss_encounters", 0)) + 1
		"purchase_completed":
			if bool(props.get("revenue_verified", false)):
				st["revenue_usd_total"] = float(st.get("revenue_usd_total", 0.0)) + maxf(0.0, float(props.get("price_usd", 0.0)))
				st["revenue_verified"] = true


func start_session() -> void:
	if _session_open:
		return
	_session_start_unix = Time.get_unix_time_from_system()
	_session_open = true


func end_session() -> void:
	if not _session_open:
		return
	_session_open = false
	var duration := maxf(0.0, Time.get_unix_time_from_system() - _session_start_unix)
	track("session_end", {"duration_sec": snappedf(duration, 0.1)})
	if not SaveData.data.is_empty():
		SaveData.save_to_disk()


func get_kpi_snapshot() -> Dictionary:
	var st: Dictionary = SaveData.data.get("stats", {})
	var first_day: int = int(int(st.get("first_launch_unix", 0)) / 86400)
	var days: Array = st.get("active_days", [])
	var d1_retained: bool = days.has(first_day + 1)
	var d7_retained: bool = days.has(first_day + 7)

	var total_runs: int = int(st.get("total_runs", 0))
	var bosses_won: int = int(st.get("bosses_defeated", 0))
	var offered: int = int(st.get("rewarded_offered", 0))
	var completed: int = int(st.get("rewarded_completed", 0))
	var started: int = int(st.get("rewarded_started", 0))
	var session_count: int = int(st.get("session_count", 0))
	var encounters: int = int(st.get("boss_encounters", 0))
	var tutorial_starts: int = int(st.get("tutorial_starts", 0))
	var finished_runs: int = int(st.get("finished_run_count", 0))
	var today: int = int(Time.get_unix_time_from_system() / 86400)
	var active_day_count: int = maxi(1, days.size())
	var revenue_usd: float = float(st.get("revenue_usd_total", 0.0))

	return {
		"d1_retention": d1_retained if today >= first_day + 1 else null,
		"d7_retention": d7_retained if today >= first_day + 7 else null,
		"avg_session_duration_sec": float(st.get("session_time_sec", 0.0)) / float(session_count) if session_count > 0 else null,
		"runs_per_user": total_runs,
		"tutorial_completed_rate": float(st.get("tutorial_completions", 0)) / float(tutorial_starts) if tutorial_starts > 0 else null,
		"boss_win_rate": (float(bosses_won) / float(encounters)) if encounters > 0 else null,
		"rewarded_ad_opt_in_rate": (float(started) / float(offered)) if offered > 0 else null,
		"rewarded_ad_completion_rate": (float(completed) / float(started)) if started > 0 else null,
		"avg_run_duration_sec": float(st.get("finished_run_time_sec", 0.0)) / float(finished_runs) if finished_runs > 0 else null,
		"arpdau_usd": revenue_usd / float(active_day_count) if bool(st.get("revenue_verified", false)) else null
	}


func get_buffered_events() -> Array[Dictionary]:
	return _event_log
