extends Sprite2D
## Decorative corbel only: the existing one-way collider remains authoritative.
## Crop away the reference sprite's tall attachment column and transparent padding.
const ART_PATH := "res://assets/levels/depth/hell_cornice_v1.png"
const STONE_REGION := Rect2(215, 112, 1914, 545)

@export var walk_width := 125.0
@export var wall_on_right := false

func _ready() -> void:
	var art: Texture2D
	if ResourceLoader.exists(ART_PATH):
		art = load(ART_PATH) as Texture2D
	if art == null:
		var source := Image.load_from_file(ART_PATH)
		if source == null or source.is_empty():
			push_warning("Hell cornice art missing; keeping painted stone cap")
			return
		art = ImageTexture.create_from_image(source)
	texture = art
	centered = false
	region_enabled = true
	region_rect = STONE_REGION
	scale = Vector2.ONE * (walk_width / STONE_REGION.size.x)
	flip_h = wall_on_right
	# The generated source is large; average it down instead of aliasing its
	# fine texture into black speckles at the room's native pixel scale.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	modulate = Color(0.95, 0.92, 0.88, 1.0)
