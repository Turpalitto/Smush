# Upstream provenance

Official release: https://github.com/godot-sdk-integrations/godot-google-play-billing/releases/tag/3.3.0

License: MIT (LICENSE in this directory).

Release archive: `godot-google-play-billing.zip`
SHA256: `20d75623d6f337f08d8283c83098b73678d5f575e39247af5a8eb80588b18568`

The GDScript wrapper and debug/release AARs are from this release. The editor
exporter adds a guard to exclude native dependencies from the offline/non-Gradle
APK preset. Gradle exports keep the upstream Play Billing 9.1.0 dependency.

The purchase schema was checked against upstream `Utils.kt` and
`GodotGooglePlayBilling.kt`: `product_ids`,
`one_time_purchase_offer_details_list`, acknowledgement response `token`.
Native Play Store transactions still require an internal-test install on a device.
