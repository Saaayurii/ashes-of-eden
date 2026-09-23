extends SceneTree
## Confirms that the chapter's former dead flags now select an actual line,
## the Stranger has a four-frame human sheet, and the Preacher owns one intro.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		printerr("FAIL: " + message)


func _spoken(dialogue: Dictionary, flags: Array) -> Array[String]:
	var out: Array[String] = []
	var nodes: Dictionary = dialogue.get("nodes", {})
	var node_id := str(dialogue.get("start", ""))
	for step in 30:
		if node_id.is_empty():
			break
		_check(nodes.has(node_id), "missing dialogue node " + node_id)
		if not nodes.has(node_id):
			break
		var node: Dictionary = nodes[node_id]
		if node.has("branches"):
			var target := str(node.get("next", ""))
			for branch in node.branches:
				if str(branch.get("flag", "")) in flags:
					target = str(branch.get("next", ""))
					break
			node_id = target
			continue
		if node.has("text"):
			out.append(str(node.text))
		if node.has("choices"):
			break
		node_id = str(node.get("next", ""))
	return out


func _run() -> void:
	var data = root.get_node("Data")
	var stranger: Dictionary = data.npcs["stranger"].sprite
	var strip_path := str(stranger.animations.idle)
	var cell: Array = stranger.cell
	var strip := load(strip_path) as Texture2D
	_check(strip != null and strip_path.contains("stranger"), "Stranger has its own sheet")
	_check(strip != null and strip.get_width() == int(cell[0]) * 4 and strip.get_height() == int(cell[1]),
		"Stranger sheet has four complete cells")
	var room = load("res://scenes/rooms/preacher_nave.tscn").instantiate()
	_check(room.intro_cutscene == "preacher_arrival" and room.intro_dialogue == "",
		"Preacher intro is not played twice")
	room.free()
	var arrival: Dictionary = data.cutscenes.get("preacher_arrival", {})
	var has_preacher_words := false
	for step in arrival.get("steps", []):
		if step.get("do", "") == "dialogue" and step.get("id", "") == "ch1_preacher":
			has_preacher_words = true
	_check(has_preacher_words, "Preacher arrival contains his dialogue")
	var hooks := [
		["npc_nun", "severin_asked", "DLG_AGNES_SEVERIN_ASKED"],
		["npc_nun", "severin_thanked", "DLG_AGNES_SEVERIN_THANKED"],
		["npc_nun", "severin_told", "DLG_AGNES_SEVERIN_TOLD"],
		["npc_nun", "severin_knew", "DLG_AGNES_SEVERIN_KNEW"],
		["npc_mara", "agnes_asked", "DLG_MARA_AGNES_ASKED"],
		["npc_mara", "agnes_silenced", "DLG_MARA_AGNES_SILENCED"],
		["npc_mara", "agnes_blessed", "DLG_MARA_AGNES_BLESSED"],
		["npc_mara", "agnes_called", "DLG_MARA_AGNES_CALLED"],
		["npc_mara", "agnes_alone", "DLG_MARA_AGNES_ALONE"],
		["npc_villager", "mara_asked", "DLG_CRONE_MARA_ASKED"],
		["npc_villager", "mara_pressed", "DLG_CRONE_MARA_PRESSED"],
		["npc_villager", "mara_refused", "DLG_CRONE_MARA_REFUSED"],
		["npc_matthew", "crone_asked", "DLG_MATTHEW_CRONE_ASKED"],
		["npc_matthew", "crone_bitter", "DLG_MATTHEW_CRONE_BITTER"],
		["npc_matthew", "crone_sent_home", "DLG_MATTHEW_CRONE_HOME"],
		["ch1_preacher", "voice_no", "DLG_CH1_PREACHER_VOICE_NO"],
		["ch1_preacher", "voice_silent", "DLG_CH1_PREACHER_VOICE_SILENT"],
		["ch1_preacher", "voice_answered", "DLG_CH1_PREACHER_VOICE_ANSWERED"]
	]
	for hook in hooks:
		var dialogue: Dictionary = data.dialogues[hook[0]]
		_check(hook[2] in _spoken(dialogue, [hook[1]]), str(hook[1]) + " selects its line")
		_check(not hook[2] in _spoken(dialogue, []), str(hook[1]) + " stays conditional")
	var preacher: Dictionary = data.dialogues["ch1_preacher"]
	for flag in ["voice_no", "voice_silent", "voice_answered"]:
		var lines := _spoken(preacher, [flag])
		_check("DLG_CH1_PREACHER_MERCY_1" in lines and "DLG_CH1_PREACHER_MERCY_2" in lines,
			"Preacher's mercy exchange survives every voice branch")
	var matthew: Dictionary = data.dialogues["npc_matthew"]
	_check("DLG_MATTHEW_ROAD" in _spoken(matthew, []),
		"Matthew's wounded traveller line precedes his choice")
	var names_choice := false
	for choice in matthew.nodes.t3.choices:
		if choice.get("id", "") == "names":
			names_choice = choice.get("effect", {}).get("set_flags", []).has("matthew_book_revealed") \
				and choice.get("next", "") == "t_r_names"
	_check(names_choice, "asking for the names reveals the ledger")
	_check(data.dialogues["ch1_ophanim_fall"].nodes.f3.text == "DLG_CH1_OPHANIM_FALL_3",
		"Ophanim recognizes the hand behind the sentence")
	var finale: Dictionary = data.cutscenes["ch1_finale"]
	for flag in ["matthew_bell", "matthew_let_ring", "matthew_book_revealed"]:
		var found := false
		for step in finale.steps:
			if step.get("if", "") == flag and step.get("do", "") == "dialogue":
				found = data.dialogues.has(str(step.get("id", "")))
		_check(found, flag + " changes the finale")
	var original_locale := TranslationServer.get_locale()
	for locale in ["en", "ru", "uk", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for key in ["DLG_CH1_PREACHER_MERCY_1", "DLG_MATTHEW_ROAD",
			"DLG_MATTHEW_R_NAMES", "DLG_CH1_OPHANIM_FALL_3", "DLG_CH1_FINALE_NAMES"]:
			var sample := TranslationServer.translate(StringName(key))
			_check(not sample.is_empty() and sample != key,
				locale + " imports " + key)
	TranslationServer.set_locale(original_locale)
	print("CHAPTER1_HOOKS_%s: %d dialogue flags plus 3 finale flags" %
		["FAILED" if _failed else "OK", hooks.size()])
	quit(1 if _failed else 0)
