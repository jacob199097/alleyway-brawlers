class_name Screen
extends Control
## Base for menu screens: a full 1920×1080 control with the shared theme.
## Esc returns to `back_to` (when set and no dialog is open).

var back_to := ""


func _enter_tree() -> void:
	theme = UI.theme()
	position = Vector2.ZERO
	size = Vector2(1920, 1080)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and back_to != "":
		get_viewport().set_input_as_handled()
		Game.go(back_to)


## Requires a signed-in player: in offline mode, shows a notice and returns false.
func needs_server(what: String) -> bool:
	if not Game.offline:
		return true
	var p := UI.panel(UI.RED)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	var h := UI.label("OFFLINE", 40, UI.RED, true)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	var t := UI.label("%s needs the game server: your cards, currency and decks live there.\nSign in when you're connected to play online." % what, 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	add_child(p)
	var sz := p.get_combined_minimum_size()
	p.position = (Vector2(1920, 1080) - sz) / 2
	return false
