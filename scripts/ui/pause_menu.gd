extends Control
## Escape / Start pauses the run. Not while a dialogue, the gift picker or the
## end screen already owns the pause.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var panel: Control = %PausePanel
@onready var settings: SettingsMenu = %Settings
@onready var bestiary: Bestiary = %Bestiary
@onready var save_menu: SaveMenu = %SaveMenu
var chapter_map: ChapterMap


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
	# Saving is solo: a session's rooms are the host's (see Saves).
	%SaveRow.visible = not Net.active
	%OpenSave.pressed.connect(_open_saves.bind("save"))
	%OpenLoad.pressed.connect(_open_saves.bind("load"))
	save_menu.closed.connect(func() -> void: panel.visible = true; %OpenSave.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if visible:
		if settings.visible or bestiary.visible or save_menu.visible or chapter_map.visible:
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
	%Resume.grab_focus()


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
