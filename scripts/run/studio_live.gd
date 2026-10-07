class_name StudioLive
extends Node
## The art studio's sandbox («Песочница», tools/studio/README.md): the Web build
## in an iframe of the studio, started with `--studio-live` (studio-live.html,
## made by tools/studio/make_preview_page.py). The studio posts what she is
## drawing — strips as PNG, a cell, and the enemy it fights like — and this
## puts it in the practice yard at once: no pull request, no import, no export.
##
##   studio → game  {type: "ashes-live", id, name, extends, cell: [w, h], fps,
##                   strips: {idle: <base64 png>, walk: …, attack: …}}
##   game → studio  {type: "ashes-live-ready"} once the yard is up, and
##                  {type: "ashes-live-applied", animations: [...]} after each.
##
## The strips become textures here (Image.load_png_from_buffer) and reach the
## enemy through Fx.runtime_strips, so Enemy._setup_sprite builds its
## SpriteFrames exactly as it does from a res:// file. Only the page that
## embeds the game may talk to it, and the page keeps nothing
## (persistentPaths = []), like a preview.

const ARG := "--studio-live"
const ID := "studio_live"
const PREFIX := "studio://live/"
## Until her first post the yard has the straw man in it.
const WAITING_FOR := "training_dummy"

## Emitted after a post was laid into Data; Run swaps the foe.
signal applied(spec: Dictionary)

var _callback: JavaScriptObject  # held, or the browser's handle to it dies


static func requested(args := OS.get_cmdline_user_args()) -> bool:
	return args.has(ARG)


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_on_js_message)
	var window := JavaScriptBridge.get_interface("window")
	window.set("__ashesLive", _callback)
	# The filter lives on the JavaScript side: a message counts only when the
	# page holding this iframe sent it, and only ours.
	JavaScriptBridge.eval("""
		window.addEventListener('message', e => {
			if (e.source !== window.parent || window.parent === window || !e.data || e.data.type !== 'ashes-live') return;
			window.__ashesLive(JSON.stringify(e.data));
		});
		if (window.parent !== window) window.parent.postMessage({type: 'ashes-live-ready'}, '*');
	""", true)


func _on_js_message(args: Array) -> void:
	var msg = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if not msg is Dictionary:
		return
	var spec := apply(msg)
	if spec.is_empty():
		return
	JavaScriptBridge.eval("window.parent.postMessage({type: 'ashes-live-applied', animations: %s}, '*')"
		% JSON.stringify(spec.sprite.animations.keys()), true)


## Lays a post into the game: textures into Fx.runtime_strips, the creature
## into Data.enemies as ID. Returns its spec, or {} when the post holds no
## usable idle strip. Separate from the browser so a test can call it.
func apply(msg: Dictionary) -> Dictionary:
	var spec := build_spec(msg)
	if spec.is_empty():
		return {}
	Data.enemies[ID] = spec
	applied.emit(spec)
	return spec


## The creature a post describes, on the enemy it fights like; textures are
## registered on the way. Static and engine-only, for the test.
static func build_spec(msg: Dictionary) -> Dictionary:
	var cell := Vector2i(int(msg.get("cell", [0, 0])[0]), int(msg.get("cell", [0, 0])[1]))
	if cell.x <= 0 or cell.y <= 0:
		push_warning("[StudioLive] no cell in the post")
		return {}
	var animations := {}
	var strips: Dictionary = msg.get("strips", {})
	for slot in strips:
		var texture := texture_from_base64(str(strips[slot]))
		if texture == null or texture.get_height() != cell.y or texture.get_width() % cell.x != 0:
			push_warning("[StudioLive] strip %s is not whole %dx%d cells" % [slot, cell.x, cell.y])
			continue
		var path := PREFIX + str(slot) + ".png"
		Fx.runtime_strips[path] = texture
		animations[str(slot)] = path
	if not animations.has("idle"):
		push_warning("[StudioLive] no idle strip")
		return {}
	var base_id := str(msg.get("extends", "cultist"))
	if not Data.enemies.has(base_id) or Data.enemies[base_id].get("boss", false):
		base_id = "cultist"
	var spec: Dictionary = Data.enemies[base_id].duplicate(true)
	spec.id = ID
	spec.erase("_source")
	spec.tags = (spec.get("tags", []) as Array).filter(func(t) -> bool: return t != "elite")
	spec.sprite = {"cell": [cell.x, cell.y], "fps": float(msg.get("fps", 8)), "animations": animations}
	# a name she typed is shown as typed: tr() hands back a string it has no key for
	if str(msg.get("name", "")).strip_edges() != "":
		spec.name = str(msg.name)
	spec.voice = str(Data.enemies[base_id].get("voice", base_id))
	return spec


static func texture_from_base64(data: String) -> Texture2D:
	if data.begins_with("data:"):
		data = data.substr(data.find(",") + 1)
	var raw := Marshalls.base64_to_raw(data)
	var picture := Image.new()
	if raw.is_empty() or picture.load_png_from_buffer(raw) != OK:
		return null
	return ImageTexture.create_from_image(picture)
