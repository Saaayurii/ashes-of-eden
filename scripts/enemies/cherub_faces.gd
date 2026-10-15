class_name CherubFaces
extends AnimatedSprite2D
## The cherub's four faces (docs/CHAPTER7.md §6 and §9): its body is drawn
## headless, and the head is this sprite riding the neck. "sprite.faces" names
## a strip per face (man, lion, ox, eagle; tools/art/build_bestiary_assets.py,
## 4 idle frames then 3 of the swing), "head_at" is the idle head's centre from
## the cell's centre and "head_track" each body frame's collar offset from the
## idle one, both measured by the builder. A turn (Enemy._turn) swaps the face.
## Cosmetic, on every peer: the face shown is the turn the host announced.

const IDLE_FRAMES := 4
## Body poses whose head swings with it; the rest keep the face still.
const SWINGING := ["attack", "attack_alt", "special"]

var body: AnimatedSprite2D
var head_at := Vector2.ZERO
var track: Dictionary = {}
var face := ""
var _faces: Dictionary = {}
var _cell := Vector2i(32, 32)


## Laid on a fresh enemy whose sprite carries "faces" (Enemy._setup_sprite).
static func attach(enemy: Node2D, sprite: AnimatedSprite2D, spec: Dictionary) -> CherubFaces:
	var head := CherubFaces.new()
	head.name = "Head"
	head.body = sprite
	head._faces = spec.get("faces", {})
	var cell: Array = spec.get("face_cell", [32, 32])
	head._cell = Vector2i(int(cell[0]), int(cell[1]))
	var at: Array = spec.get("head_at", [0, -40])
	head.head_at = Vector2(float(at[0]), float(at[1]))
	head.track = spec.get("head_track", {})
	head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	enemy.add_child(head)
	head.show_face(str(spec.get("face", "man")))
	return head


func show_face(id: String) -> void:
	if not _faces.has(id) or id == face:
		return
	face = id
	var frames := SpriteFrames.new()
	var texture := load(str(_faces[id])) as Texture2D
	if texture == null:
		return
	var count := texture.get_width() / _cell.x
	for animation in ["idle", "attack"]:
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 6.0 if animation == "idle" else 9.0)
		frames.set_animation_loop(animation, animation == "idle")
		var first := 0 if animation == "idle" else IDLE_FRAMES
		var last := mini(IDLE_FRAMES, count) if animation == "idle" else count
		for i in range(first, last):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * _cell.x, 0, _cell.x, _cell.y)
			frames.add_frame(animation, atlas)
	if frames.has_animation("default"):
		frames.remove_animation("default")
	sprite_frames = frames
	play("idle")


func _process(_delta: float) -> void:
	if body == null or sprite_frames == null:
		return
	var offset := Vector2.ZERO
	var frames: Array = track.get(str(body.animation), [])
	if not frames.is_empty():
		var row: Array = frames[clampi(body.frame, 0, frames.size() - 1)]
		offset = Vector2(float(row[0]), float(row[1]))
	var side := -1.0 if body.flip_h else 1.0
	position = body.position + Vector2((head_at.x + offset.x) * side, head_at.y + offset.y) * body.scale
	flip_h = body.flip_h
	scale = body.scale
	modulate = body.modulate
	self_modulate = body.self_modulate
	visible = body.visible
	var wanted := "attack" if SWINGING.has(str(body.animation)) and body.is_playing() else "idle"
	if sprite_frames.has_animation(wanted) and animation != wanted:
		play(wanted)
