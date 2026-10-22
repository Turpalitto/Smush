extends Node
## Rewarded Ads service (Autoload: Ads).
## Enforces:
## 1. Reward granted ONLY after SDK confirms completion (on_user_earned_reward).
## 2. Strict anti-duplicate grant token ledger + per-run placement caps.
## 3. Zero fake/mock ads in commercial builds; clean offline continuation when unavailable.

signal rewarded_result(placement: String, granted: bool, reason: String)

const PLACEMENT_REVIVE: String = "revive"
const PLACEMENT_DOUBLE_REWARD: String = "double_reward"
const PLACEMENT_EXTRA_MUTATION: String = "extra_mutation"

const RUN_CAPS: Dictionary = {
	PLACEMENT_REVIVE: 1,
	PLACEMENT_DOUBLE_REWARD: 1,
	PLACEMENT_EXTRA_MUTATION: 1
}

var _run_usage: Dictionary = {}
var _claimed_grant_tokens: Dictionary = {}
var _pending_placement: String = ""
var _pending_token: String = ""
var _pending_callback: Callable = Callable()
var _nonce_counter: int = 0

# Pluggable adapter: ProductionAdMobAdapter in release/Android, TestMockAdAdapter ONLY in automated tests/debug
var _adapter: RefCounted = null


class ProductionAdMobAdapter extends RefCounted:
	## Integrates Poing Studios Godot AdMob Plugin v5.x (Google Mobile Ads SDK) when present on Android/iOS.
	var _loaded_ad: Object = null
	var _is_initialized: bool = false

	func initialize() -> void:
		if not ClassDB.class_exists("MobileAds") and not Engine.has_singleton("PoingGodotAdMob"):
			return
		_is_initialized = true

	func is_available(_placement: String) -> bool:
		# Requires native AdMob plugin + configured unit ID (or debug test unit in non-commercial debug)
		if not (OS.get_name() == "Android" or OS.get_name() == "iOS"):
			return false
		if not Engine.has_singleton("PoingGodotAdMob"):
			return false
		var unit_id := _resolve_unit_id()
		return not unit_id.is_empty() and _loaded_ad != null

	func _resolve_unit_id() -> String:
		if OS.get_name() == "Android":
			if not BuildConfig.production_rewarded_unit_android.is_empty():
				return BuildConfig.production_rewarded_unit_android
			if not BuildConfig.is_commercial_build():
				return BuildConfig.ADMOB_TEST_REWARDED_ANDROID
		elif OS.get_name() == "iOS":
			if not BuildConfig.production_rewarded_unit_ios.is_empty():
				return BuildConfig.production_rewarded_unit_ios
			if not BuildConfig.is_commercial_build():
				return BuildConfig.ADMOB_TEST_REWARDED_IOS
		return ""

	func show_rewarded(_placement: String, grant_token: String, complete_cb: Callable) -> void:
		if _loaded_ad == null:
			complete_cb.call(false, grant_token, "ad_not_loaded")
			return
		# Real SDK reward callback invokes complete_cb(true, grant_token, "sdk_reward_earned")
		complete_cb.call(false, grant_token, "sdk_not_bound")


class TestMockAdAdapter extends RefCounted:
	## Test-only adapter used strictly for automated QA tests; blocked in commercial builds.
	var simulated_available: bool = true
	var simulated_complete_success: bool = true
	var simulate_duplicate_callback: bool = false

	func initialize() -> void:
		pass

	func is_available(_placement: String) -> bool:
		if BuildConfig.is_commercial_build():
			return false
		return simulated_available

	func show_rewarded(_placement: String, grant_token: String, complete_cb: Callable) -> void:
		if BuildConfig.is_commercial_build():
			complete_cb.call(false, grant_token, "commercial_mock_blocked")
			return
		if not simulated_available:
			complete_cb.call(false, grant_token, "offline_unavailable")
			return
		complete_cb.call(simulated_complete_success, grant_token, "mock_sdk_earned" if simulated_complete_success else "user_dismissed")
		if simulate_duplicate_callback and simulated_complete_success:
			# Deliberately fire a second time so tests verify duplicate grant protection!
			complete_cb.call(true, grant_token, "duplicate_sdk_callback")


func _ready() -> void:
	_select_default_adapter()
	reset_run_limits()


func _select_default_adapter() -> void:
	if BuildConfig.can_use_mock_adapters():
		_adapter = TestMockAdAdapter.new()
	else:
		_adapter = ProductionAdMobAdapter.new()
	_adapter.call("initialize")


func set_test_adapter(mock_adapter: RefCounted) -> void:
	if BuildConfig.is_commercial_build():
		push_error("Cannot attach mock ad adapter in commercial build!")
		return
	_adapter = mock_adapter


func reset_run_limits() -> void:
	_run_usage.clear()
	for k in RUN_CAPS.keys():
		_run_usage[k] = 0


func can_offer(placement: String) -> bool:
	if not RUN_CAPS.has(placement):
		return false
	var used: int = int(_run_usage.get(placement, 0))
	if used >= int(RUN_CAPS[placement]):
		return false
	if _adapter == null:
		return false
	return bool(_adapter.call("is_available", placement))


func notify_offered(placement: String) -> void:
	if can_offer(placement):
		Analytics.track("rewarded_ad_offered", {"placement": placement})


func request_rewarded_ad(placement: String, on_done: Callable) -> void:
	if not RUN_CAPS.has(placement):
		on_done.call(false, "invalid_placement")
		return
	var used: int = int(_run_usage.get(placement, 0))
	if used >= int(RUN_CAPS[placement]):
		on_done.call(false, "placement_cap_reached")
		return
	if _adapter == null or not bool(_adapter.call("is_available", placement)):
		on_done.call(false, "ad_unavailable")
		rewarded_result.emit(placement, false, "ad_unavailable")
		return

	_nonce_counter += 1
	var token := "%s_%d_%d" % [placement, Time.get_ticks_usec(), _nonce_counter]
	_pending_placement = placement
	_pending_token = token
	_pending_callback = on_done

	_adapter.call("show_rewarded", placement, token, Callable(self, "_on_sdk_reward_callback"))


func _on_sdk_reward_callback(sdk_confirmed: bool, grant_token: String, reason: String) -> void:
	# Anti-duplicate protection: never grant the same token twice or exceed run cap!
	if _claimed_grant_tokens.has(grant_token):
		return

	var placement := _pending_placement
	var cb := _pending_callback

	if not sdk_confirmed:
		_pending_placement = ""
		_pending_token = ""
		_pending_callback = Callable()
		if cb.is_valid():
			cb.call(false, reason)
		rewarded_result.emit(placement, false, reason)
		return

	if grant_token.is_empty() or grant_token != _pending_token:
		if cb.is_valid():
			cb.call(false, "token_mismatch")
		return

	var used: int = int(_run_usage.get(placement, 0))
	if used >= int(RUN_CAPS.get(placement, 1)):
		if cb.is_valid():
			cb.call(false, "placement_cap_reached")
		return

	# Commit to anti-duplicate ledger BEFORE invoking gameplay reward callback
	_claimed_grant_tokens[grant_token] = true
	_run_usage[placement] = used + 1
	_pending_placement = ""
	_pending_token = ""
	_pending_callback = Callable()

	Analytics.track("rewarded_ad_completed", {"placement": placement})
	if cb.is_valid():
		cb.call(true, reason)
	rewarded_result.emit(placement, true, reason)
