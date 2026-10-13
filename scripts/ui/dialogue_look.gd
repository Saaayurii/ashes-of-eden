extends RefCounted
class_name DialogueLook
## How a dialogue's windows look and where they stand (docs/DIALOGUE_LOOKS.md).
##
## data/dialogue_looks.json holds the named styles (colours, borders, sizes; a
## key left out keeps the game's own look, so "default" is {}) and the speakers'
## portraits. A dialogue may carry "look", and any of its lines may carry one
## too, laid over the dialogue's key by key:
##   "style"     a style id
##   "panel"     [x, y, w, h]  the bottom panel, in 640×360 pixels
##   "caption"   [x, y, w]     the captions
##   "portrait"  [x, y, size]  the portrait window; false hides it for a line
##   "face"      res:// path   another picture for this line (a frown, a smile)
## Bubbles keep to the heads: only a style's colours reach them.
## The art studio's «Диалоги» drags these windows and edits the styles; its
## preview draws them as [DialogueBox] does — change one, change the other.

const PATH := "res://data/dialogue_looks.json"
## The screen the rectangles are written in; a wider window stretches them.
const BASE := Vector2(640, 360)
const COLORS := ["bg", "border", "speaker", "text", "caption", "portrait_bg", "portrait_border"]
const NUMBERS := {
	"border_width": Vector2i(0, 4), "radius": Vector2i(0, 12),
	"speaker_size": Vector2i(8, 24), "text_size": Vector2i(10, 28), "caption_size": Vector2i(9, 24),
}
## How many numbers each window's rectangle has.
const RECTS := {"panel": 4, "caption": 3, "portrait": 3}
const MIN_PANEL := Vector2(120, 48)
const MIN_CAPTION := 80
const PORTRAIT_SIZE := Vector2i(24, 160)

static var _doc: Dictionary = {}


static func doc() -> Dictionary:
	if _doc.is_empty() and DataDoc.exists(PATH):
		var parsed = DataDoc.doc(PATH)
		if parsed is Dictionary:
			_doc = parsed
	return _doc


## Forget the file, for a tool that has just rewritten it.
static func reload() -> void:
	_doc = {}


static func style(id: String) -> Dictionary:
	var styles: Dictionary = doc().get("styles", {})
	return styles.get(id, styles.get("default", {}))


## The dialogue's look with a line's own laid over it, key by key.
static func merged(dialogue_look: Dictionary, line_look: Dictionary) -> Dictionary:
	var out := dialogue_look.duplicate()
	for key in line_look:
		out[key] = line_look[key]
	return out


## Who says a line, as a picture: the file's own choice first, else the
## avatar of the person whose name is the speaker key (data/npcs).
static func portrait_of(speaker: String) -> String:
	var speakers: Dictionary = doc().get("speakers", {})
	if speakers.has(speaker):
		return str(speakers[speaker])
	var tree := Engine.get_main_loop() as SceneTree
	var data: Node = tree.root.get_node_or_null("Data") if tree != null else null
	if data != null:
		var npcs: Dictionary = data.get("npcs")
		for npc in npcs.values():
			if str(npc.get("name", "")) == speaker:
				return str(npc.get("avatar", ""))
	return ""


## A rectangle of the file on a screen of [param screen] pixels.
static func on_screen(values: Array, screen: Vector2) -> Rect2:
	var k := screen / BASE
	var at := Vector2(float(values[0]), float(values[1])) * k
	match values.size():
		4:
			return Rect2(at, Vector2(float(values[2]), float(values[3])) * k)
		3:
			return Rect2(at, Vector2.ONE * float(values[2]) * k.y)  # a square stays square
	return Rect2(at, Vector2.ZERO)


## A colour of a style, or [param fallback] when the style keeps the game's.
static func color(look_style: Dictionary, key: String, fallback: Color) -> Color:
	var value := str(look_style.get(key, ""))
	return Color.html(value) if Color.html_is_valid(value) else fallback
