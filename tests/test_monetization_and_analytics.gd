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
