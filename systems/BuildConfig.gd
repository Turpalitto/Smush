class_name BuildConfig
extends RefCounted
## Central build & SDK configuration separating Commercial Release behavior from Test/Sandbox adapters.

const APP_VERSION: String = "1.0.0"
const APP_VERSION_CODE: int = 1
const APPLICATION_ID: String = "com.turpalitto.slimerush"

# Google official public AdMob test Rewarded Unit IDs (safe ONLY in non-commercial debug builds)
const ADMOB_TEST_REWARDED_ANDROID: String = "ca-app-pub-3940256099942544/5224354917"
const ADMOB_TEST_REWARDED_IOS: String = "ca-app-pub-3940256099942544/1712485313"

# Replace via owner's environment / export config before Play Store production rollout
static var production_rewarded_unit_android: String = ""
static var production_rewarded_unit_ios: String = ""
static var force_commercial_mode: bool = false
static var allow_test_adapters_in_debug: bool = false


static func is_commercial_build() -> bool:
	if force_commercial_mode:
		return true
	# In exported release builds (non-debug), commercial mode is strictly enforced:
	# mock ads and simulated purchases are completely disabled.
	return not OS.is_debug_build()


static func can_use_mock_adapters() -> bool:
	if is_commercial_build():
		return false
	return allow_test_adapters_in_debug
