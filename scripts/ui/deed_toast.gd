extends Label
class_name DeedToast
## Says a deed was done (data/achievements), one line at the top of the screen
## with the Ash it paid, and a bell. Several at once wait their turn. The book
## that lists them all is the bestiary's "Deeds" section. A resonance woken by
## a gift (data/resonances) is said the same way, with what it does.

const SHOW_FOR := 3.2

var _queue: Array[String] = []
var _busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # a deed done on the killing blow of a night still shows over the verdict
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 10)
	add_theme_color_override("font_color", Color(0.98, 0.86, 0.5))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	add_theme_constant_override("outline_size", 3)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -200
	offset_right = 200
	offset_top = 34
	offset_bottom = 64
	modulate.a = 0.0
	EventBus.achievement_unlocked.connect(announce)
	EventBus.resonance_awakened.connect(func(id: String) -> void: _say("res:" + id))


func announce(id: String) -> void:
	_say(id)


func _say(id: String) -> void:
	_queue.append(id)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty() or not is_inside_tree():
		_busy = false
		return
	_busy = true
	var id: String = _queue.pop_front()
	if id.begins_with("res:"):
		var resonance := Resonances.spec(id.trim_prefix("res:"))
		text = "%s\n%s" % [tr("RES_WOKEN") % tr(str(resonance.get("name", ""))), tr(str(resonance.get("description", "")))]
	else:
		var spec := Achievements.spec(id)
		text = tr("DEED_DONE") % tr(str(spec.get("name", "")))
		var ash := int(spec.get("ash", 0))
		if ash > 0:
			text += "   " + tr("DEED_ASH") % ash
	Audio.play(&"bell", -6.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(SHOW_FOR)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.finished.connect(_next)
