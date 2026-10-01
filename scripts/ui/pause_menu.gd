extends Control
## Escape / Start pauses the run. Not while a dialogue, the gift picker or the
## end screen already owns the pause.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var panel: Control = %PausePanel
@onready var settings: SettingsMenu = %Settings
@onready var bestiary: Bestiary = %Bestiary
@onready var save_menu: SaveMenu = %SaveMenu
var chapter_map: ChapterMap
var carried: CarriedGifts


func _ready() -> void:
	visible = false
	settings.visible = false
	%Resume.pressed.connect(_resume)
	%OpenSettings.pressed.connect(func() -> void: panel.visible = false; settings.open())
	%ToMenu.pressed.connect(_to_menu)
	settings.closed.connect(func() -> void: panel.visible = true; %Resume.grab_focus())
	%OpenBestiary.pressed.connect(func() -> void: panel.visible = false; bestiary.open())
	bestiary.closed.connect(func() -> void: panel.visible = true; %OpenBestiary.grab_focus())
	# The way through the night (ChapterMap), right under the bestiary.
	chapter_map = ChapterMap.new()
	chapter_map.name = "ChapterMap"
	add_child(chapter_map)
	var open_map := Button.new()
	open_map.name = "OpenMap"
	open_map.unique_name_in_owner = true
	open_map.text = tr("PAUSE_MAP")
	%OpenBestiary.add_sibling(open_map)
	open_map.owner = self  # so %OpenMap resolves like the buttons in the scene
	open_map.pressed.connect(func() -> void: panel.visible = false; chapter_map.open())
	chapter_map.closed.connect(func() -> void: panel.visible = true; open_map.grab_focus())
	# What the body carries tonight (CarriedGifts), under the map.
	carried = CarriedGifts.new()
	carried.name = "CarriedGifts"
	add_child(carried)
	var open_carried := Button.new()
	open_carried.name = "OpenCarried"
	open_carried.unique_name_in_owner = true
	open_carried.text = tr("PAUSE_CARRIED")
	open_map.add_sibling(open_carried)
	open_carried.owner = self
	open_carried.pressed.connect(func() -> void: panel.visible = false; carried.open())
	carried.closed.connect(func() -> void: panel.visible = true; open_carried.grab_focus())
	# Saving is solo: a session's rooms are the host's (see Saves).
	%SaveRow.visible = not Net.active and Game.daily == ""  # the night of the day is played once through
	%OpenSave.pressed.connect(_open_saves.bind("save"))
	%OpenLoad.pressed.connect(_open_saves.bind("load"))
	save_menu.closed.connect(func() -> void: panel.visible = true; %OpenSave.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if visible:
		if settings.visible or bestiary.visible or save_menu.visible or chapter_map.visible or carried.visible:
			return  # the overlay handles its own Escape
		_resume()
	elif not get_tree().paused:  # someone else (dialogue, picker, end screen) owns the pause
		get_viewport().set_input_as_handled()
		_open()


func _open() -> void:
	Net.set_paused(true)  # online the world keeps turning while you read
	Audio.play(&"ui_pause", -6.0, 0.0)
	visible = true
	panel.visible = true
	_show_omen()
	%Resume.grab_focus()


## The night's omen, over the buttons: what it trades, in its own words.
func _show_omen() -> void:
	var line := %Resume.get_parent().get_node_or_null("Omen") as Label
	if line == null:
		line = Label.new()
		line.name = "Omen"
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(220, 0)
		line.add_theme_font_size_override("font_size", 9)
		line.modulate = Color(0.95, 0.75, 0.7)
		%Resume.add_sibling(line)
		%Resume.get_parent().move_child(line, %Resume.get_index())
	var spec := Omens.spec(Game.omen)
	line.visible = not spec.is_empty()
	if line.visible:
		line.text = "%s: %s\n%s" % [tr("OMEN_LABEL"), tr(str(spec.get("name", ""))), tr(str(spec.get("description", "")))]


## A phone call, the home button, the notification shade, a browser tab
## switched away: the fight must not go on without the player. Solo only —
## online the other player is still there.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if not Net.active and not visible and not get_tree().paused and is_inside_tree():
			_open()


## What "Save" writes is the run's checkpoint: the state at this room's entrance.
func _open_saves(mode: String) -> void:
	panel.visible = false
	save_menu.open(mode, get_tree().current_scene.get("checkpoint") if get_tree().current_scene != null else {})


func _resume() -> void:
	Audio.play(&"ui_unpause", -6.0, 0.0)
	visible = false
	get_tree().paused = false


func _to_menu() -> void:
	Profile.save()  # kill counts gathered this far into the night
	Curtain.change_scene(MENU_SCENE, false, func() -> void:
		get_tree().paused = false
		Net.leave())
