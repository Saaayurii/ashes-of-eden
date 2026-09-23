extends Control
## In-run HUD: health bar, wave counter, list of gifts taken, and the two
## cooldowns the player actually plays around — the roll and the sword.

@onready var hp_bar: Range = %HpBar
@onready var wave_label: Label = %WaveLabel
@onready var gifts_label: Label = %GiftsLabel
@onready var boss_bar: Range = %BossBar
@onready var essence_bar: Range = %EssenceBar
@onready var level_label: Label = %LevelLabel
@onready var charges: Label = %Charges
@onready var charge_icons: HBoxContainer = %ChargeIcons
const POTION_ICON := preload("res://assets/ui/icons/potion.png")
@onready var boss_name: Label = %BossBar/BossName
@onready var dash_key: Label = %DashKey
@onready var dash_bar: Range = %DashBar
@onready var attack_key: Label = %AttackKey
@onready var attack_bar: Range = %AttackBar
@onready var block_key: Label = %BlockKey
@onready var block_bar: Range = %BlockBar
## The active skill's row, shown once a gift has given one.
@onready var skill_row: Control = %Skill
@onready var skill_key: Label = %SkillKey
@onready var skill_bar: Range = %SkillBar
@onready var combo_label: Label = %Combo
@onready var toast: Label = %Toast

## The body the meters belong to; looked up lazily because the HUD can be ready
## before the run has spawned anyone.
var _body: Player
var _toast_tween: Tween


func _ready() -> void:
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.room_started.connect(_on_room_started)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.ability_acquired.connect(_on_ability_acquired)
	EventBus.boss_hp_changed.connect(_on_boss_hp_changed)
	EventBus.essence_changed.connect(_on_essence_changed)
	EventBus.heal_charges_changed.connect(_on_charges_changed)
	EventBus.bestiary_unlocked.connect(_on_bestiary_unlocked)
	EventBus.run_restored.connect(func() -> void: _on_ability_acquired({}))
	_on_essence_changed(Game.essence, Game.essence_needed(), Game.level)
	EventBus.boss_died.connect(func() -> void: boss_bar.visible = false)
	# A boss spawns before room_started is emitted, so hide the bar only when
	# nothing with "boss" is actually standing in the room.
	EventBus.room_started.connect(func(_i: int) -> void: call_deferred("_hide_boss_bar_unless_boss"))
	wave_label.text = ""
	gifts_label.text = ""
	combo_label.text = ""
	_refresh_keys()
	Settings.changed.connect(_refresh_keys)
	# The player may be ready before us, so pull its initial state too.
	var body := _local_player()
	if body != null:
		_on_hp_changed(body.hp, body.stats.max_hp)


## Cooldowns move every frame, so they are polled rather than signalled.
func _process(_delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		_body = _local_player()
		if _body == null:
			return
	_set_meter(dash_bar, dash_key, _body.dash_ready_ratio())
	_set_meter(attack_bar, attack_key, _body.attack_ready_ratio())
	_set_meter(block_bar, block_key, _body.block_ready_ratio())
	skill_row.visible = not _body.skill.is_empty()
	if skill_row.visible:
		_set_meter(skill_bar, skill_key, _body.skill_ready_ratio())
	# combo_step() is how many swings of the chain have landed so far.
	combo_label.text = tr("HUD_COMBO") % _body.combo_step() if _body.combo_open() else ""


## Full and bright when the move is ready, dim while it fills back up.
func _set_meter(bar: Range, key: Label, ratio: float) -> void:
	bar.value = ratio
	var ready_now := ratio >= 1.0
	bar.modulate.a = 1.0 if ready_now else 0.55
	key.modulate.a = 1.0 if ready_now else 0.5


func _refresh_keys() -> void:
	dash_key.text = Settings.key_name("dash")
	attack_key.text = Settings.key_name("attack")
	block_key.text = Settings.key_name("block")
	skill_key.text = Settings.key_name("skill")


func _local_player() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority():
			return body
	return null


func _on_hp_changed(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp


func _on_room_started(index: int) -> void:
	wave_label.text = tr("HUD_AREA") % index


func _on_room_cleared(index: int) -> void:
	wave_label.text = "%s\n%s" % [tr("HUD_AREA") % index, tr("HUD_DOOR_OPEN")]


func _on_ability_acquired(_ability: Dictionary) -> void:
	gifts_label.text = "\n".join(Game.abilities.map(func(a: Dictionary) -> String: return tr(a.name)))


func _on_boss_hp_changed(name_key: String, hp: float, max_hp: float) -> void:
	boss_bar.visible = hp > 0.0
	boss_bar.max_value = max_hp
	boss_bar.value = hp
	boss_name.text = name_key


func _on_essence_changed(essence: float, needed: float, level: int) -> void:
	essence_bar.max_value = needed
	essence_bar.value = essence
	level_label.text = tr("HUD_LEVEL") % level


func _on_charges_changed(current: int, maximum: int) -> void:
	# One potion per charge; spent ones stay as dim outlines so the count is readable.
	for child in charge_icons.get_children():
		child.queue_free()
	for i in maximum:
		var icon := TextureRect.new()
		icon.texture = POTION_ICON
		icon.modulate = Color.WHITE if i < current else Color(1, 1, 1, 0.25)
		charge_icons.add_child(icon)
	charges.text = "† ".repeat(current).strip_edges()  # kept for the smoke test / screen readers


## A new page in the bestiary: a line that fades in, holds, and goes.
func _on_bestiary_unlocked(enemy_id: String) -> void:
	var named: Dictionary = Data.npcs.get(enemy_id.trim_prefix("npc:"), {}) if enemy_id.begins_with("npc:") else Data.enemies.get(enemy_id, {})
	toast.text = tr("BESTIARY_NEW") % tr(named.get("name", enemy_id))
	if _toast_tween != null:
		_toast_tween.kill()  # two firsts in a row: the newer line takes the slot
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)


func _hide_boss_bar_unless_boss() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("stats") is Dictionary and enemy.stats.get("boss", false) and not enemy.is_dead():
			return
	boss_bar.visible = false
