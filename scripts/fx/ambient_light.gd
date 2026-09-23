extends CanvasModulate
## The room's night. Darkens everything in the canvas so the lights have
## something to light; the HUD lives on its own CanvasLayer and stays bright.
## Switched off together with the lights by the "Lighting" setting.


func _ready() -> void:
	add_to_group("ambient")
	_apply_setting()
	EventBus.lighting_changed.connect(_apply_setting)


func _apply_setting() -> void:
	visible = Settings.lighting
