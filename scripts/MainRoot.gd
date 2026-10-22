class_name MainRoot
extends Node
## Root application scene connecting ArenaController and all 12 mobile UI screens.

var arena: ArenaController
var ui_layer: CanvasLayer
var theme_root: Control
var hud: GameHUD
var draft_overlay: MutationDraftOverlay
var overlays: OverlaysController
var menus: MenuScreens


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	arena = ArenaController.new()
	arena.name = "Arena"
	arena.visible = false
	add_child(arena)

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	theme_root = Control.new()
	theme_root.name = "ThemeRoot"
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme_root.theme = UIThemeBuilder.build_theme()
	ui_layer.add_child(theme_root)

	hud = GameHUD.new()
	hud.name = "GameHUD"
	hud.visible = false
	hud.bind_arena(arena)
	theme_root.add_child(hud)

	draft_overlay = MutationDraftOverlay.new()
	draft_overlay.name = "MutationDraftOverlay"
	draft_overlay.bind_arena(arena)
	theme_root.add_child(draft_overlay)

	overlays = OverlaysController.new()
	overlays.name = "OverlaysController"
	overlays.bind_arena(arena)
	overlays.navigate_to_main_menu.connect(_return_to_main_menu)
	overlays.navigate_to_upgrades.connect(_open_upgrades_from_run)
	theme_root.add_child(overlays)

	menus = MenuScreens.new()
	menus.name = "MenuScreens"
	menus.start_run_requested.connect(_start_run)
	theme_root.add_child(menus)

	App.change_state(App.State.MAIN_MENU)


func _start_run(mode_id: String) -> void:
	menus.visible = false
	arena.visible = true
	hud.visible = true
	arena.start_new_run(mode_id)


func _return_to_main_menu() -> void:
	arena.visible = false
	hud.visible = false
	menus.visible = true
	App.change_state(App.State.MAIN_MENU)
	menus.show_page(MenuScreens.Page.HOME)


func _open_upgrades_from_run() -> void:
	arena.visible = false
	hud.visible = false
	menus.visible = true
	App.change_state(App.State.MAIN_MENU)
	menus.show_page(MenuScreens.Page.UPGRADES)
