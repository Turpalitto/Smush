extends RefCounted
## Optional Poing AdMob 5.1.0 bridge. API verified against the release source,
## not the bundled quick-start examples (their UMP API differs from this release).
## Without native plugins/configuration this adapter remains unavailable.

const SDK_ROOT := "res://addons/admob/gdscript/src/"
var _sdk: Dictionary = {}
var _consent: Object
var _loader: Object
var _ad: Object
var _initialized: bool = false
var _loading: bool = false
var _showing: bool = false
var _completion: Callable = Callable()
var _token: String = ""


func initialize() -> void:
	if OS.get_name() not in ["Android", "iOS"]:
		return
	for singleton in ["PoingGodotAdMob", "PoingGodotAdMobRewardedAd", "PoingGodotAdMobConsentInformation", "PoingGodotAdMobUserMessagingPlatform"]:
		if not Engine.has_singleton(singleton):
			return
	if _unit_id().is_empty():
		return
	var paths := {
		"mobile": "api/MobileAds.gd", "loader": "api/RewardedAdLoader.gd",
		"request": "api/core/AdRequest.gd", "loaded": "api/listeners/RewardedAdLoadCallback.gd",
		"screen": "api/listeners/FullScreenContentCallback.gd",
		"earned": "api/listeners/OnUserEarnedRewardListener.gd",
		"init": "api/listeners/OnInitializationCompleteListener.gd",
		"consent": "ump/api/ConsentInformation.gd", "ump": "ump/api/UserMessagingPlatform.gd",
		"consent_params": "ump/core/ConsentRequestParameters.gd"
	}
	for key in paths:
		if not ResourceLoader.exists(SDK_ROOT + paths[key]):
			return
		_sdk[key] = load(SDK_ROOT + paths[key])
	_consent = _sdk["consent"].new()
	# Consent failure deliberately leaves ads off; offline gameplay is unaffected.
	_consent.call("update", _sdk["consent_params"].new(), _on_consent_updated, func(_error: Object) -> void: pass)


func _on_consent_updated() -> void:
	var status: int = int(_consent.call("get_consent_status"))
	if status == 2: # ConsentInformation.ConsentStatus.REQUIRED in v5.1.0
		_sdk["ump"].call("load_consent_form", _on_form_loaded, func(_error: Object) -> void: pass)
	elif status == 1 or status == 3: # NOT_REQUIRED / OBTAINED
		_initialize_mobile_ads()


func _on_form_loaded(form: Object) -> void:
	form.call("show", func(error: Object) -> void:
		if error == null:
			var status: int = int(_consent.call("get_consent_status"))
			if status == 1 or status == 3:
				_initialize_mobile_ads()
	)


func _initialize_mobile_ads() -> void:
	var listener: Object = _sdk["init"].new()
	listener.set("on_initialization_complete", func(_status: Object) -> void:
		_initialized = true
		_load_ad()
	)
	_sdk["mobile"].call("initialize", listener)


func _unit_id() -> String:
	var configured := BuildConfig.production_rewarded_unit_android if OS.get_name() == "Android" else BuildConfig.production_rewarded_unit_ios
	if not configured.is_empty():
		return configured
	if BuildConfig.is_commercial_build():
		return ""
	return BuildConfig.ADMOB_TEST_REWARDED_ANDROID if OS.get_name() == "Android" else BuildConfig.ADMOB_TEST_REWARDED_IOS


func _load_ad() -> void:
	if not _initialized or _loading or _ad != null:
		return
	_loading = true
	_loader = _sdk["loader"].new()
	var loaded: Object = _sdk["loaded"].new()
	loaded.set("on_ad_loaded", func(ad: Object) -> void:
		_loading = false
		_ad = ad
	)
	loaded.set("on_ad_failed_to_load", func(_error: Object) -> void:
		_loading = false
	)
	_loader.call("load", _unit_id(), _sdk["request"].new(), loaded)


func is_available(_placement: String) -> bool:
	if _initialized and not _loading and _ad == null and not _showing:
		_load_ad()
	return _ad != null and not _showing


func show_rewarded(_placement: String, grant_token: String, complete_cb: Callable) -> void:
	if _ad == null or _showing:
		complete_cb.call(false, grant_token, "ad_not_loaded")
		return
	_showing = true
	_token = grant_token
	_completion = complete_cb
	var screen: Object = _sdk["screen"].new()
	screen.set("on_ad_dismissed_full_screen_content", func() -> void: _close_ad("user_dismissed"))
	screen.set("on_ad_failed_to_show_full_screen_content", func(_error: Object) -> void: _close_ad("show_failed"))
	_ad.set("full_screen_content_callback", screen)
	var earned: Object = _sdk["earned"].new()
	earned.set("on_user_earned_reward", func(_reward: Object) -> void:
		var cb := _completion
		_completion = Callable()
		if cb.is_valid():
			cb.call(true, _token, "sdk_reward_earned")
	)
	_ad.call("show", earned)


func _close_ad(reason: String) -> void:
	var cb := _completion
	_completion = Callable()
	if _ad != null:
		_ad.call("destroy")
		_ad = null
	_showing = false
	if cb.is_valid():
		cb.call(false, _token, reason)
	_load_ad()


func show_privacy_options() -> void:
	if not _sdk.has("ump"):
		return
	_sdk["ump"].call("show_privacy_options_form", func(_error: Object) -> void:
		# Reload consent status before any further requests.
		_initialized = false
		if _ad != null and not _showing:
			_ad.call("destroy")
			_ad = null
		_on_consent_updated()
	)
