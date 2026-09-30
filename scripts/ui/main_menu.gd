extends Control

const RUN_SCENE := "res://scenes/run/run.tscn"
const MULTIPLAYER_SCENE := "res://scenes/ui/multiplayer_menu.tscn"
## Language names are shown in their own language on purpose: never translated.
const NATIVE_NAMES := {"en": "English", "ru": "Русский", "uk": "Українська", "zh_CN": "简体中文"}

@onready var play_button: Button = %Play
@onready var together_button: Button = %Together
@onready var language: OptionButton = %Language
@onready var quit_button: Button = %Quit
## The painting and everything drawn on it (the hero, the lantern, the rain).
@onready var layers: Node2D = $Layers
@onready var figure: AnimatedSprite2D = $Layers/Elian
@onready var character_select: HBoxContainer = %CharacterSelect
@onready var character_name: Label = %CharacterName

## The figure by the house: the hero, or one of the people of the story
## (data/npcs), flipped through with the arrows. The choice is kept in the
## profile. Only the hero has a full move set, so a run is always Elian's.
const HERO := "elian"
const HERO_FRAMES := preload("res://assets/sprites/elian_frames.tres")
## The hero strips' cell (tools/art/slice_hero.py): his feet are on its bottom row.
const HERO_CELL := Vector2i(128, 64)
## Where the figure's feet stand on the painting, and its size on it.
const FIGURE_FEET := Vector2(160, 278)  # on the path in front of the fence
const FIGURE_SCALE := 2.0
var _characters: Array[String] = []
var _character := 0

## The painting is 640x360 but its last rows are empty dark; the layers use
## the 640x340 above them. With stretch aspect "expand" a taller or wider
## screen shows more than one screen, so the layers are scaled to cover it.
const PAINTING := Vector2(640, 340)


func _ready() -> void:
	_fit_layers()
	get_viewport().size_changed.connect(_fit_layers)
	_characters.assign([HERO])
	# Script-only characters stay hidden; each other person now has their own
	# animation strips, including the knight.
	for id in Data.npcs:
		if not Data.npcs[id].get("menu", true):
			continue
		_characters.append(id)
	_character = maxi(0, _characters.find(str(Profile.data.get("menu_character", HERO))))
	%Prev.pressed.connect(_turn_character.bind(-1))
	%Next.pressed.connect(_turn_character.bind(1))
	_show_character()
	# "godot --headless -- --server": no menu, just a referee for two browsers.
	if Net.start_from_cli():
		visible = false
		return
	Audio.music("menu")
	for i in Settings.LOCALES.size():
		var code: String = Settings.LOCALES[i]
		language.add_item(NATIVE_NAMES.get(code, code), i)
		if code == Settings.locale:
			language.select(i)
	language.item_selected.connect(func(index: int) -> void: Settings.set_locale(Settings.LOCALES[index]))
	# keep_closed: the run opens on its own chapter card, already in the black.
	play_button.pressed.connect(func() -> void: Saves.pending = {}; Curtain.change_scene(RUN_SCENE, true))
	%Continue.pressed.connect(_continue)
	%OpenLoad.pressed.connect(func() -> void: %SaveMenu.open("load"))
	%SaveMenu.closed.connect(func() -> void: _refresh_saves(); %OpenLoad.grab_focus())
	Saves.changed.connect(_refresh_saves)
	_refresh_saves()
	together_button.pressed.connect(func() -> void: Curtain.change_scene(MULTIPLAYER_SCENE))
	%OpenSettings.pressed.connect(%Settings.open)
	%Settings.closed.connect(%OpenSettings.grab_focus)
	%OpenBestiary.pressed.connect(%Bestiary.open)
	# the practice yard with its straw man: the moves, without a night at stake
	Game.practice = ""
	%OpenPractice.pressed.connect(func() -> void:
		Game.practice = "training_dummy"
		Curtain.change_scene(RUN_SCENE))
	%Bestiary.closed.connect(%OpenBestiary.grab_focus)
	# where the Ash goes (Relics): beside the bestiary in one row, like
	# Continue | Load, so the menu keeps its height and its title
	var reliquary := Reliquary.new()
	reliquary.name = "Reliquary"
	add_child(reliquary)
	var open_reliquary := Button.new()
	open_reliquary.name = "OpenReliquary"
	open_reliquary.text = "MENU_RELIQUARY"
	_pair(%OpenBestiary, open_reliquary, "BookRow")
	open_reliquary.pressed.connect(reliquary.open)
	reliquary.closed.connect(open_reliquary.grab_focus)
	quit_button.visible = not (OS.has_feature("web") or OS.has_feature("mobile"))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	# Settings | Quit share a row too: with every button on its own line the
	# column stood taller than the 360-pixel screen and pushed the title off it
	_pair(%OpenSettings, quit_button, "SystemRow")
	(%Continue if %Continue.visible else play_button).grab_focus()


## Puts [param first] and [param second] side by side in one row of the menu,
## where [param first] stood, as halves — the way Continue | Load are drawn.
func _pair(first: Control, second: Control, row_name: String) -> void:
	var row := HBoxContainer.new()
	row.name = row_name
	var saves_row := first.get_parent().get_node_or_null("SaveRow") as HBoxContainer
	if saves_row != null:
		row.add_theme_constant_override("separation", saves_row.get_theme_constant("separation"))
	first.add_sibling(row)
	for half in [first, second]:
		if half.get_parent() == null:
			row.add_child(half)
		else:
			half.reparent(row)
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.custom_minimum_size = Vector2.ZERO


## "Continue" is there only when there is something to continue: the newest save.
func _refresh_saves() -> void:
	%Continue.visible = Saves.any()


func _continue() -> void:
	var slot := Saves.latest_slot()
	if slot != "":
		Saves.start(Saves.read(slot))


func _fit_layers() -> void:
	var view := get_viewport_rect().size
	var scale_factor := maxf(view.x / PAINTING.x, view.y / PAINTING.y)
	layers.scale = Vector2.ONE * scale_factor
	layers.position = (view - PAINTING * scale_factor) / 2.0
	if character_select != null:
		_place_character_select()


## Left and right on the stick or keyboard flip the figure too, so the arrows
## are not mouse-only. Only while the menu itself has the screen.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or %Settings.visible or %Bestiary.visible:
		return
	if event.is_action_pressed("ui_left"):
		_turn_character(-1)
	elif event.is_action_pressed("ui_right"):
		_turn_character(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _turn_character(step: int) -> void:
	if _characters.is_empty():
		return
	_character = posmod(_character + step, _characters.size())
	Profile.data["menu_character"] = _characters[_character]
	Profile.save()
	Audio.play(&"ui_click", -8.0)
	_show_character()


func _show_character() -> void:
	if _characters.is_empty():
		return
	var id := _characters[_character]
	var cell := HERO_CELL
	if id == HERO:
		figure.sprite_frames = HERO_FRAMES
		figure.flip_h = false
		character_name.text = tr("SPEAKER_ELIAN")
	else:
		var spec: Dictionary = Data.npcs.get(id, {})
		var sprite_spec: Dictionary = spec.get("sprite", {})
		var size: Array = sprite_spec.get("cell", [32, 44])
		cell = Vector2i(int(size[0]), int(size[1]))
		var frames := SpriteFrames.new()
		var strips: Dictionary = sprite_spec.get("animations", {}).duplicate()
		if sprite_spec.has("path") and not str(sprite_spec.path).strip_edges().is_empty():
			strips["idle"] = sprite_spec.path
		for anim in strips:
			var path := str(strips[anim]).strip_edges()
			if path.is_empty() or not ResourceLoader.exists(path):
				push_warning("[MainMenu] Missing %s strip for %s: %s" % [anim, id, path])
				continue
			Fx.add_strip(frames, path, cell, float(sprite_spec.get("fps", 4)), str(anim), anim not in ["attack", "interact"])
		if frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			figure.sprite_frames = frames
		else:
			push_warning("[MainMenu] Missing idle animation for %s" % id)
			figure.sprite_frames = HERO_FRAMES
			cell = HERO_CELL
		figure.flip_h = spec.get("face", "right") == "left"
		character_name.text = tr(spec.get("name", id))
	figure.scale = Vector2.ONE * FIGURE_SCALE
	figure.position = FIGURE_FEET - Vector2(0, cell.y * FIGURE_SCALE / 2.0)
	if figure.sprite_frames.has_animation("idle"):
		figure.play("idle")
	_place_character_select.call_deferred()  # after the name label has its width


## The arrows and the name sit under the figure, wherever the layers ended up.
func _place_character_select() -> void:
	var under := layers.to_global(FIGURE_FEET + Vector2(0, 6))
	character_select.position = under - Vector2(character_select.size.x / 2.0, 0)
