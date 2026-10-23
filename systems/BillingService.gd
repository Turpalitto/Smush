extends Node
## In-App Purchases service (Autoload: Billing).
## Wraps official GodotGooglePlayBilling (BillingClient v3.3.0 / Play Billing 9.1.0)
## with acknowledgement, purchase restoration, zero pay-to-win, and no simulated live transactions.

signal purchase_succeeded(sku: String)
signal purchase_failed(sku: String, reason: String)
signal purchases_restored(restored_skus: Array[String])
signal catalog_updated()

var _billing_client: BillingClient = null
var _product_prices: Dictionary = {}
var _pending_sku: String = ""
var _processed_tokens: Dictionary = {}
var _awaiting_ack: Dictionary = {}
var _product_offers: Dictionary = {}
var _test_adapter: RefCounted = null


class TestMockBillingAdapter extends RefCounted:
	## Test-only billing adapter strictly blocked in commercial builds.
	var should_succeed: bool = true
	var owned_remote_skus: Array[String] = []
	var _token_seq: int = 0

	func purchase(sku: String) -> Dictionary:
		if BuildConfig.is_commercial_build():
			return {"ok": false, "reason": "commercial_mock_blocked"}
		if not should_succeed:
			return {"ok": false, "reason": "user_canceled"}
		_token_seq += 1
		if not owned_remote_skus.has(sku):
			owned_remote_skus.append(sku)
		return {
			"ok": true,
			"purchase_token": "mock_tok_%d_%s" % [_token_seq, sku],
			"acknowledged": false
		}

	func query_owned() -> Array[String]:
		if BuildConfig.is_commercial_build():
			return []
		return owned_remote_skus.duplicate()


func _ready() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		_billing_client = BillingClient.new()
		add_child(_billing_client)
		_billing_client.connected.connect(_on_billing_connected)
		_billing_client.query_product_details_response.connect(_on_product_details)
		_billing_client.on_purchase_updated.connect(_on_purchases_updated)
		_billing_client.query_purchases_response.connect(_on_purchases_updated)
		_billing_client.acknowledge_purchase_response.connect(_on_acknowledge_response)
		_billing_client.start_connection()


func set_test_adapter(adapter: RefCounted) -> void:
	if BuildConfig.is_commercial_build():
		push_error("Mock billing adapter is forbidden in commercial builds!")
		return
	_test_adapter = adapter


func is_store_available() -> bool:
	if _billing_client != null and _billing_client.is_ready():
		return true
	if _test_adapter != null and not BuildConfig.is_commercial_build():
		return true
	return false


func get_display_price(sku: String) -> String:
	if _product_prices.has(sku):
		return str(_product_prices[sku])
	var item: Dictionary = ConfigDB.store_catalog.get(sku, {})
	return str(item.get("price_display_fallback", "—"))


func is_sku_owned(sku: String) -> bool:
	var owned: Array = SaveData.data.get("owned_skus", [])
	return owned.has(sku)


func purchase_sku(sku: String) -> void:
	if not ConfigDB.store_catalog.has(sku):
		purchase_failed.emit(sku, "unknown_sku")
		return
	if is_sku_owned(sku):
		purchase_failed.emit(sku, "already_owned")
		return

	Analytics.track("purchase_started", {"sku": sku})
	_pending_sku = sku

	# 1. Real Google Play Billing path
	if _billing_client != null and _billing_client.is_ready():
		var offer: Dictionary = _product_offers.get(sku, {})
		var result := _billing_client.purchase(sku, str(offer.get("purchase_option_id", "")), str(offer.get("offer_id", "")))
		if int(result.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
			purchase_failed.emit(sku, "billing_launch_failed")
			_pending_sku = ""
		return

	# 2. Isolated automated test adapter (strictly disabled in commercial builds)
	if _test_adapter != null and not BuildConfig.is_commercial_build():
		var res: Dictionary = _test_adapter.call("purchase", sku)
		if bool(res.get("ok", false)):
			var tok: String = str(res.get("purchase_token", ""))
			_finalize_verified_purchase(sku, tok)
		else:
			purchase_failed.emit(sku, str(res.get("reason", "failed")))
		return

	# 3. Offline / Play Store unavailable: never fake a real-money transaction!
	purchase_failed.emit(sku, "billing_unavailable")


func restore_purchases() -> void:
	if _billing_client != null and _billing_client.is_ready():
		_billing_client.query_purchases(BillingClient.ProductType.INAPP)
		return

	if _test_adapter != null and not BuildConfig.is_commercial_build():
		var skus: Array[String] = _test_adapter.call("query_owned")
		var restored: Array[String] = []
		for sku in skus:
			if ConfigDB.store_catalog.has(sku):
				SaveData.apply_sku_entitlement(sku)
				restored.append(sku)
		purchases_restored.emit(restored)
		return

	purchases_restored.emit([])


func _on_billing_connected() -> void:
	var skus := PackedStringArray(ConfigDB.store_order)
	_billing_client.query_product_details(skus, BillingClient.ProductType.INAPP)
	_billing_client.query_purchases(BillingClient.ProductType.INAPP)


func _on_product_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		return
	for detail: Dictionary in response.get("product_details", []):
		var pid: String = str(detail.get("product_id", ""))
		# Billing plugin 3.3.0 exposes a list of one-time offers (see Utils.kt).
		var offers: Variant = detail.get("one_time_purchase_offer_details_list", [])
		if not ConfigDB.store_catalog.has(pid) or not offers is Array:
			continue
		for offer: Dictionary in offers:
			if offer.has("formatted_price"):
				_product_prices[pid] = str(offer["formatted_price"])
				_product_offers[pid] = offer
				break
	catalog_updated.emit()


func _on_purchases_updated(response: Dictionary) -> void:
	var code: int = int(response.get("response_code", -1))
	if code != BillingClient.BillingResponseCode.OK:
		if not _pending_sku.is_empty():
			purchase_failed.emit(_pending_sku, "play_billing_code_%d" % code)
			_pending_sku = ""
		return

	var restored: Array[String] = []
	for p: Dictionary in response.get("purchases", []):
		if int(p.get("purchase_state", 0)) != BillingClient.PurchaseState.PURCHASED:
			continue
		var token: String = str(p.get("purchase_token", ""))
		if token.is_empty():
			continue
		var skus: Array[String] = []
		# Native 3.3.0 serializes Purchase.products as product_ids, not products.
		for product_id in p.get("product_ids", []):
			var sku := str(product_id)
			if ConfigDB.store_catalog.has(sku) and not skus.has(sku):
				skus.append(sku)
		if skus.is_empty():
			continue
		if bool(p.get("is_acknowledged", false)):
			for sku in skus:
				_finalize_verified_purchase(sku, token)
				restored.append(sku)
		elif _billing_client != null and not _awaiting_ack.has(token):
			_awaiting_ack[token] = skus
			_billing_client.acknowledge_purchase(token)
	if not restored.is_empty():
		purchases_restored.emit(restored)


func _on_acknowledge_response(response: Dictionary) -> void:
	# Native plugin returns the acknowledged purchase token in the `token` field.
	var token: String = str(response.get("token", ""))
	if not _awaiting_ack.has(token):
		return
	var skus: Array[String] = _awaiting_ack[token]
	_awaiting_ack.erase(token)
	if int(response.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		for sku in skus:
			purchase_failed.emit(sku, "acknowledgement_failed")
		return
	for sku in skus:
		_finalize_verified_purchase(sku, token)
	purchases_restored.emit(skus)


func _finalize_verified_purchase(sku: String, purchase_token: String) -> void:
	if purchase_token.is_empty() or not ConfigDB.store_catalog.has(sku):
		return
	var grant_key := purchase_token + ":" + sku
	if _processed_tokens.has(grant_key):
		# Restore must also repair a rolled-back local save in the same app process.
		if not is_sku_owned(sku):
			SaveData.apply_sku_entitlement(sku)
		return
	_processed_tokens[grant_key] = true
	var already_owned := is_sku_owned(sku)
	SaveData.apply_sku_entitlement(sku)
	# Restores and test transactions are not new revenue. Currency conversion and
	# net USD revenue require verified store reports, never guessed catalog prices.
	if not already_owned:
		Analytics.track("purchase_completed", {"sku": sku})
	_pending_sku = ""
	purchase_succeeded.emit(sku)
