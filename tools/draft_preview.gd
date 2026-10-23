extends Control
## Renders the mutation draft alone, with fixed fake choices, so the cards can be
## judged without playing to the first draft (which is ~30 s into a run and does not
## happen again on demand).
##
##   DRAFT_OUT   output PNG (required)
##   DRAFT_SIZE  WxH (default 720x1280)

const OUT_ENV := "DRAFT_OUT"
const SIZE_ENV := "DRAFT_SIZE"


func _ready() -> void:
	var out_path := OS.get_environment(OUT_ENV)
	if out_path.is_empty():
		push_error("DRAFT_OUT is not set")
		get_tree().quit(2)
		return
	var w := 720
	var h := 1280
	var spec := OS.get_environment(SIZE_ENV)
	if not spec.is_empty():
		var parts := spec.split("x")
		if parts.size() == 2:
			w = int(parts[0])
			h = int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))
	RenderingServer.set_default_clear_color(Color("#14231c"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var overlay := MutationDraftOverlay.new()
	add_child(overlay)
	overlay.visible = true
	# One of each rarity, so the halo difference is visible in a single frame.
	Events.mutation_draft_requested.emit([
		{"id": "dash", "rarity": "rare", "current_level": 0, "next_level": 1,
			"max_level": 5, "completes_synergy": ""},
		{"id": "magnet", "rarity": "common", "current_level": 1, "next_level": 2,
			"max_level": 5, "completes_synergy": ""},
		{"id": "spikes", "rarity": "epic", "current_level": 2, "next_level": 3,
			"max_level": 5, "completes_synergy": "em_storm"},
	])

	for i in range(4):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image")
		get_tree().quit(4)
		return
	var err := img.save_png(out_path)
	print("DRAFT_PREVIEW %s err=%d" % [out_path, err])
	get_tree().quit(0 if err == OK else 5)
