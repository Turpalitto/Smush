extends TestSuiteBase
## Tests Rewarded Ads (SDK confirmation, duplicate-callback guard, per-run caps, commercial mock block),
## Google Play Billing (non-P2W entitlements, restore_purchases, commercial safety), and Analytics KPIs.


func _init() -> void:
	super("MonetizationAndAnalyticsSuite")


func run() -> void:
	_test_rewarded_ads_and_duplicate_protection()
	_test_commercial_mode_blocks_fakes()
	_test_billing_entitlements_and_restore()
	_test_analytics_consent_and_kpis()
	_test_delayed_ad_callbacks()
	_test_native_billing_payload()
	_test_analytics_denominators()

	# Restore clean defaults
	BuildConfig.force_commercial_mode = false
	Ads._select_default_adapter()
	Billing._test_adapter = null


func _test_rewarded_ads_and_duplicate_protection() -> void:
	BuildConfig.force_commercial_mode = false
	var mock_ads := Ads.TestMockAdAdapter.new()
	mock_ads.simulated_available = true
	mock_ads.simulated_complete_success = false
	Ads.set_test_adapter(mock_ads)
	Ads.reset_run_limits()

	# 1. Dismissed ad MUST NOT grant reward
	var state_box := {"grants": 0, "billing_err": ""}
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, func(granted: bool, _reason: String) -> void:
		if granted:
			state_box["grants"] = int(state_box["grants"]) + 1
	)
	assert_eq(int(state_box["grants"]), 0, "Dismissed ad grants zero rewards")
	assert_true(Ads.can_offer(Ads.PLACEMENT_REVIVE), "Placement still available after dismissed attempt")

	# 2. Duplicate SDK callback MUST only grant reward ONCE!
	mock_ads.simulated_complete_success = true
	mock_ads.simulate_duplicate_callback = true
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, func(granted: bool, _reason: String) -> void:
		if granted:
			state_box["grants"] = int(state_box["grants"]) + 1
	)
	assert_eq(int(state_box["grants"]), 1, "Anti-duplicate token ledger blocks second callback for same ad")

	# 3. Per-run cap (1 revive per run) blocks second request in same run
	assert_false(Ads.can_offer(Ads.PLACEMENT_REVIVE), "Revive placement capped after 1 use in run")
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, func(granted: bool, _reason: String) -> void:
		if granted:
			state_box["grants"] = int(state_box["grants"]) + 1
	)
	assert_eq(int(state_box["grants"]), 1, "Second revive request in same run denied")


func _test_commercial_mode_blocks_fakes() -> void:
	SaveData.data = SaveData.create_default_data()
	BuildConfig.force_commercial_mode = true
	var mock_ads := Ads.TestMockAdAdapter.new()
	mock_ads.simulated_available = true
	mock_ads.simulated_complete_success = true

	# Even if someone tries to query mock adapter in commercial mode, it returns unavailable
	assert_false(mock_ads.is_available(Ads.PLACEMENT_DOUBLE_REWARD), "Mock ad unavailable in commercial build")

	Ads._select_default_adapter()
	assert_false(Ads.can_offer(Ads.PLACEMENT_DOUBLE_REWARD), "Offline commercial build cleanly reports ad unavailable")

	var res_box := {"reason": ""}
	var conn := func(_sku: String, reason: String) -> void: res_box["reason"] = reason
	Billing.purchase_failed.connect(conn)
	Billing.purchase_sku("com.turpalitto.slimerush.no_ads")
	Billing.purchase_failed.disconnect(conn)
	assert_eq(str(res_box["reason"]), "billing_unavailable", "Commercial build never simulates real-money IAP")
	BuildConfig.force_commercial_mode = false


func _test_billing_entitlements_and_restore() -> void:
	SaveData.data = SaveData.create_default_data()
	var mock_iap := Billing.TestMockBillingAdapter.new()
	Billing.set_test_adapter(mock_iap)

	assert_false(SaveData.has_no_ads(), "No Ads initially false")
	Billing.purchase_sku("com.turpalitto.slimerush.no_ads")
	assert_true(SaveData.has_no_ads(), "Verified No Ads purchase activates entitlement")

	Billing.purchase_sku("com.turpalitto.slimerush.skin_astral_jelly")
	assert_true((SaveData.data["unlocked_forms"] as Array).has("astral_jelly"), "Cosmetic skin unlocked")

	# Simulate fresh reinstall and call restore_purchases()
	SaveData.data = SaveData.create_default_data()
	assert_false(SaveData.has_no_ads(), "Fresh local profile has no entitlements before restore")
	Billing.restore_purchases()
	assert_true(SaveData.has_no_ads(), "restore_purchases() restores No Ads")
	assert_true((SaveData.data["unlocked_forms"] as Array).has("astral_jelly"), "restore_purchases() restores cosmetic skin")


func _test_analytics_consent_and_kpis() -> void:
	Analytics.get_buffered_events().clear()
	SaveData.set_setting("analytics_consent", false)
	Analytics.track("run_started", {"mode": "standard", "email": "secret@example.com"})
	assert_eq(Analytics.get_buffered_events().size(), 0, "Events are not buffered/exported without user consent")

	SaveData.set_setting("analytics_consent", true)
	Analytics.track("run_started", {"mode": "standard", "email": "secret@example.com"})
	assert_eq(Analytics.get_buffered_events().size(), 1, "Event recorded when consent enabled")
	var props: Dictionary = Analytics.get_buffered_events()[0]["props"]
	assert_false(props.has("email"), "PII fields stripped automatically")

	var kpis := Analytics.get_kpi_snapshot()
	assert_true(kpis.has("d1_retention") and kpis.has("d7_retention") and kpis.has("boss_win_rate") and kpis.has("arpdau_usd"), "KPI snapshot exposes retention, boss win rate, and ARPDAU")


class DeferredAds extends RefCounted:
	var requests: Array[Dictionary] = []
	func is_available(_placement: String) -> bool:
		return true
	func show_rewarded(_placement: String, token: String, cb: Callable) -> void:
		requests.append({"token": token, "cb": cb})
	func finish(index: int, earned: bool) -> void:
		requests[index]["cb"].call(earned, requests[index]["token"], "test_delayed")


class NativeBillingFixture extends BillingClient:
	var acknowledged_tokens: Array[String] = []
	func acknowledge_purchase(purchase_token: String):
		acknowledged_tokens.append(purchase_token)


func _test_delayed_ad_callbacks() -> void:
	var adapter := DeferredAds.new()
	Ads.set_test_adapter(adapter)
	Ads.reset_run_limits()
	var state := {"grants": 0, "cancelled": 0, "busy": ""}
	var callback := func(granted: bool, reason: String) -> void:
		if granted:
			state["grants"] += 1
		elif reason == "run_changed":
			state["cancelled"] += 1
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, callback)
	Ads.request_rewarded_ad(Ads.PLACEMENT_DOUBLE_REWARD, func(_ok: bool, reason: String) -> void: state["busy"] = reason)
	assert_eq(state["busy"], "ad_already_pending", "Concurrent ad request rejected without losing first callback")
	Ads.reset_run_limits()
	assert_eq(state["cancelled"], 1, "Run reset completes cancelled request once")
	Ads.request_rewarded_ad(Ads.PLACEMENT_REVIVE, callback)
	adapter.finish(0, false)
	assert_false(Ads._pending_token.is_empty(), "Old failure does not cancel current ad")
	adapter.finish(0, true)
	assert_eq(state["grants"], 0, "Old success cannot reward new run")
	adapter.finish(1, true)
	adapter.finish(1, true)
	assert_eq(state["grants"], 1, "Current reward delivered exactly once")
	Ads.reset_run_limits()


func _test_native_billing_payload() -> void:
	SaveData.data = SaveData.create_default_data()
	Billing._processed_tokens.clear()
	var original_client: BillingClient = Billing._billing_client
	var fixture := NativeBillingFixture.new()
	Billing._billing_client = fixture
	var no_ads := "com.turpalitto.slimerush.no_ads"
	var skin := "com.turpalitto.slimerush.skin_astral_jelly"
	Billing._on_product_details({"response_code": 0, "product_details": [{
		"product_id": no_ads, "one_time_purchase_offer_details_list": [{
			"formatted_price": "2,99 €", "purchase_option_id": "buy", "offer_id": ""
		}]
	}]})
	assert_eq(Billing.get_display_price(no_ads), "2,99 €", "Native 3.3.0 offer list supplies localized price")
	var payload := {"response_code": 0, "purchases": [{
		"purchase_state": BillingClient.PurchaseState.PURCHASED,
		"purchase_token": "native_fixture", "is_acknowledged": false,
		"product_ids": [no_ads, skin]
	}]}
	Billing._on_purchases_updated(payload)
	Billing._on_purchases_updated(payload)
	assert_eq(fixture.acknowledged_tokens.size(), 1, "Repeated purchase update acknowledges token once")
	assert_false(SaveData.has_no_ads(), "Unacknowledged purchase does not grant entitlement")
	Billing._on_acknowledge_response({"response_code": 6, "token": "native_fixture"})
	assert_false(SaveData.has_no_ads(), "Failed acknowledgement grants nothing")
	Billing._on_purchases_updated(payload)
	Billing._on_acknowledge_response({"response_code": 0, "token": "native_fixture"})
	assert_true(SaveData.has_no_ads(), "Native token acknowledgement grants No Ads")
	assert_true(Billing.is_sku_owned(skin), "Multiple products in one purchase token all granted")
	Billing._on_acknowledge_response({"response_code": 0, "token": "native_fixture"})
	assert_eq((SaveData.data["owned_skus"] as Array).size(), 2, "Duplicate acknowledgement does not duplicate products")
	assert_eq(SaveData.data["stats"]["revenue_usd_total"], 0.0, "Store events never invent USD revenue")
	SaveData.data = SaveData.create_default_data()
	payload["purchases"][0]["is_acknowledged"] = true
	Billing._on_purchases_updated(payload)
	assert_true(SaveData.has_no_ads(), "Already acknowledged token restores after local save rollback")
	Billing._finalize_verified_purchase("unknown.sku", "bad_token")
	assert_false(Billing.is_sku_owned("unknown.sku"), "Unknown SKU never becomes owned")
	Billing._billing_client = original_client
	fixture.free()


func _test_analytics_denominators() -> void:
	SaveData.data = SaveData.create_default_data()
	Analytics.start_session()
	Analytics._session_start_unix = Time.get_unix_time_from_system() - 6.0
	Analytics.end_session()
	Analytics.end_session()
	assert_eq(SaveData.data["stats"]["session_count"], 1, "Repeated lifecycle notifications end one session only")
	Analytics.track("run_duration", {"seconds": 30})
	Analytics.track("run_duration", {"seconds": 90})
	Analytics.track("boss_encountered")
	SaveData.data["stats"]["total_runs"] = 5
	SaveData.data["stats"]["bosses_defeated"] = 1
	SaveData.data["stats"]["rewarded_offered"] = 4
	SaveData.data["stats"]["rewarded_started"] = 2
	SaveData.data["stats"]["rewarded_completed"] = 1
	var snapshot := Analytics.get_kpi_snapshot()
	assert_approx(float(snapshot["avg_session_duration_sec"]), 6.0, 0.2, "Session mean uses ended sessions, not active days")
	assert_eq(snapshot["avg_run_duration_sec"], 60.0, "Run mean uses finished run duration events")
	assert_eq(snapshot["boss_win_rate"], 1.0, "Boss win rate uses encounters, not all runs")
	assert_eq(snapshot["rewarded_ad_opt_in_rate"], 0.5, "Ad opt-in counts starts, not completions")
	assert_eq(snapshot["rewarded_ad_completion_rate"], 0.5, "Ad completion has a separate denominator")
	assert_eq(snapshot["arpdau_usd"], null, "ARPDAU unknown without verified revenue")
	assert_eq(snapshot["d7_retention"], null, "New install not classified as a failed D7 retention")
	Analytics.start_session()
