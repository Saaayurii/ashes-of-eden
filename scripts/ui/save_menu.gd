extends Control
class_name SaveMenu
## The slots: the autosave and three of the player's own. One screen, two
## modes — "load" from the main menu and the pause menu, "save" from the pause
## menu (it writes the Run's checkpoint, see Saves). Every filled slot can be
## exported (a file, and a text code on the clipboard); import takes a file or
## a pasted code into the first free slot. Overwriting and deleting ask twice.

signal closed

const DIM := Color(0.55, 0.53, 0.58)

var mode := "load"
var _checkpoint: Dictionary = {}
var _armed := ""  # "<action>:<slot>" waiting for its second press
var _export_slot := ""
var _dialog_for := ""  # "export" | "import"
var _web_callback: JavaScriptObject

@onready var title: Label = %Title
@onready var slots: VBoxContainer = %Slots
@onready var status: Label = %Status
@onready var code_panel: PanelContainer = %CodePanel
@onready var code_edit: TextEdit = %Code
@onready var file_dialog: FileDialog = %FileDialog


func _ready() -> void:
	visible = false
	%Back.pressed.connect(close)
	%ImportFile.pressed.connect(_import_file)
	%ImportCode.pressed.connect(_open_code_panel)
	%CodeOk.pressed.connect(func() -> void: _import_text(code_edit.text); code_panel.visible = false)
	%CodeCancel.pressed.connect(func() -> void: code_panel.visible = false; %ImportCode.grab_focus())
	file_dialog.file_selected.connect(_on_file_selected)
	Saves.changed.connect(_build)


## [param checkpoint] is what "save" writes; unused when loading.
func open(new_mode: String, checkpoint := {}) -> void:
	mode = new_mode
	_checkpoint = checkpoint
	_armed = ""
	status.text = ""
	code_panel.visible = false
	title.text = tr("SAVE_TITLE_SAVE") if mode == "save" else tr("SAVE_TITLE_LOAD")
	visible = true
	_build()
	var first := _first_enabled()
	(first if first != null else %Back as Button).grab_focus()


func close() -> void:
	visible = false
	code_panel.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if code_panel.visible:
		code_panel.visible = false
		%ImportCode.grab_focus()
	else:
		close()


# ------------------------------------------------------------------- rows ---

func _build() -> void:
	if not is_node_ready():
		return
	for child in slots.get_children():
		slots.remove_child(child)
		child.queue_free()
	for slot in Saves.SLOTS:
		slots.add_child(_row(slot))


func _row(slot: String) -> Control:
	var data := Saves.read(slot)
	var row := HBoxContainer.new()
	row.name = "Slot_" + slot
	row.add_theme_constant_override("separation", 6)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = tr("SAVE_SLOT_AUTO") if slot == Saves.AUTO else tr("SAVE_SLOT") % int(slot)
	name_label.add_theme_font_size_override("font_size", 12)
	text.add_child(name_label)
	var info := Label.new()
	info.text = "%s · %s" % [Saves.summary(data), Saves.saved_at_text(data)] if not data.is_empty() else tr("SAVE_EMPTY")
	info.add_theme_font_size_override("font_size", 9)
	info.add_theme_color_override("font_color", DIM)
	text.add_child(info)
	row.add_child(text)

	var main := _button("SAVE_DO_SAVE" if mode == "save" else "SAVE_DO_LOAD", _main_action.bind(slot, data))
	main.name = "Main"
	# the autosave is the game's to write; an empty slot has nothing to load
	main.disabled = (mode == "save" and (slot == Saves.AUTO or _checkpoint.is_empty())) \
		or (mode == "load" and data.is_empty())
	row.add_child(main)
	if not data.is_empty():
		row.add_child(_button("SAVE_EXPORT", _export.bind(slot, data)))
		var delete := _button("SAVE_DELETE", _delete.bind(slot))
		delete.name = "Delete"
		row.add_child(delete)
	return row


func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(action)
	return button


func _first_enabled() -> Button:
	for row in slots.get_children():
		var main := row.get_node_or_null("Main") as Button
		if main != null and not main.disabled:
			return main
	return null


## A second press within the same row confirms; anything else disarms.
func _confirm(action: String, slot: String, button_path: String) -> bool:
	var key := "%s:%s" % [action, slot]
	if _armed == key:
		_armed = ""
		return true
	_build()
	_armed = key
	var button := slots.get_node_or_null("Slot_%s/%s" % [slot, button_path]) as Button
	if button != null:
		button.text = tr("SAVE_CONFIRM")
		button.grab_focus()
	return false


# ---------------------------------------------------------------- actions ---

func _main_action(slot: String, data: Dictionary) -> void:
	if mode == "load":
		Audio.play(&"ui_click")
		Profile.save()
		Saves.start(data)
		return
	if not data.is_empty() and not _confirm("save", slot, "Main"):
		return
	if Saves.write(slot, _checkpoint):
		_say("SAVE_SAVED")
	_focus_row(slot)


func _delete(slot: String) -> void:
	if not _confirm("delete", slot, "Delete"):
		return
	Saves.delete(slot)
	_say("SAVE_DELETED")
	var first := _first_enabled()
	(first if first != null else %Back as Button).grab_focus()


## The code always goes to the clipboard; the file is a download on the Web and
## a save dialog elsewhere.
func _export(slot: String, data: Dictionary) -> void:
	DisplayServer.clipboard_set(Saves.to_code(data))
	var filename := "ashes_of_eden_%s.%s" % [slot, Saves.EXTENSION]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(JSON.stringify(data, "\t").to_utf8_buffer(), filename, "application/json")
		_say("SAVE_EXPORTED")
		return
	_export_slot = slot
	_dialog_for = "export"
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = filename
	file_dialog.popup_centered_ratio(0.7)
	_say("SAVE_CODE_COPIED")


func _import_file() -> void:
	if OS.has_feature("web"):
		_web_pick_file()
		return
	_dialog_for = "import"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	if _dialog_for == "export":
		var ok := Saves.to_file(Saves.read(_export_slot), path)
		_say("SAVE_EXPORTED" if ok else "SAVE_FILE_ERROR")
	else:
		var data := Saves.from_file(path)
		_store_import(data)


func _open_code_panel() -> void:
	var clip := DisplayServer.clipboard_get().strip_edges()
	code_edit.text = clip if clip.begins_with(Saves.CODE_PREFIX) else ""
	code_panel.visible = true
	code_edit.grab_focus()


func _import_text(text: String) -> void:
	_store_import(Saves.parse(text))


func _store_import(data: Dictionary) -> void:
	if data.is_empty():
		_say("SAVE_IMPORT_BAD")
		return
	var slot := Saves.first_free_manual()
	if slot == "":
		_say("SAVE_SLOTS_FULL")
		return
	Saves.write(slot, data)
	status.text = tr("SAVE_IMPORTED") % int(slot)
	_focus_row(slot)


## The browser has no file dialog of ours: a hidden <input type=file> reads the
## file as text and hands it back through a callback.
func _web_pick_file() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array) -> void: _import_text(str(args[0])))
	JavaScriptBridge.get_interface("window").aoeImportSave = _web_callback
	JavaScriptBridge.eval("""
		(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.aoesave,.json,.txt';
			input.onchange = function () {
				var file = input.files[0];
				if (!file) return;
				var reader = new FileReader();
				reader.onload = function () { window.aoeImportSave(reader.result); };
				reader.readAsText(file);
			};
			input.click();
		})();
	""", true)


func _say(key: String) -> void:
	status.text = tr(key)


func _focus_row(slot: String) -> void:
	var main := slots.get_node_or_null("Slot_%s/Main" % slot) as Button
	if main != null and not main.disabled:
		main.grab_focus()
