class_name VisualStyle
extends RefCounted
## Experimental organic slime look (GLM visual lab) — switch only, no gameplay.
##
## The owner allowed the organic style ONLY as an option, never as the default, so
## this switch is deliberately runtime-only: it writes nothing to SaveData and
## touches no stat, so it cannot affect balance, progression or the save file, and a
## restart returns to the shipped look.
##
## Switching while a run is live replaces the visual node in place through
## PlayerSlime.apply_visual_style(): same body, same physics, same HUD — the run
## keeps going and switching back is instant.

static var organic_enabled: bool = true


## The single place that decides which visual class the player gets. Both the
## shipped path and the experiment go through here, so there is one architecture.
static func make_visual() -> SlimeVisual:
	if organic_enabled:
		return SlimeVisualClaude.new()
	return SlimeVisual.new()


static func set_enabled(on: bool) -> void:
	if organic_enabled == on:
		return
	organic_enabled = on
	Events.visual_style_changed.emit(on)


## 0..2 quality for the organic shader, taken from the existing fx_quality setting:
## the experiment must not introduce a second quality knob next to the shipped one.
static func quality_from_settings() -> int:
	match str(SaveData.get_setting("fx_quality", "high")):
		"low":
			return 0
		"medium":
			return 1
		_:
			return 2
