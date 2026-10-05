extends RefCounted
class_name RoomLayers
## The three planes of a painted room, kept apart.
##
##   far     what lies beyond the playable stone: the inpainted plates behind the
##           painting's openings (DepthWindows) and the clouds, clipped to the
##           sky's opening. Only this plane slides against the camera, and only
##           inside the holes the painting leaves for it.
##   middle  the painting itself, and everything standing on it: props, decor,
##           enemies, the hero — and the fog, which drifts on its own but is
##           anchored to the world, so it never drags a wall along with the view.
##   front   low clutter over the feet (DecorFront, z 1), weather and the room's
##           living details (z 2).
##
## An opening whose plate is not distance — a recess in the catacombs'
## masonry, water at the hero's own level, a pillar that stands in front of
## the view — stays put: moving it would move a wall. FAR_WINDOWS lists, per
## room, which openings really look out (reviewed plate by plate); the rest
## keep their plate still.

const FAR_WINDOWS := {
	"village_night": [1, 2, 3],
	"graveyard_cross": [1, 2, 3],
	"graveyard_arches": [1, 2, 3],
	"graveyard_tree": [1, 2, 3],
	"swamp_threshold": [1],    # the distant hill above the opened cemetery gate
	"swamp_moon": [1, 2],        # 3: the pool under the lower gallery
	"swamp_red": [1, 2],         # 3: the water by the pier
	"swamp_crypt": [1, 2],       # 3: the water under the boat
	"catacombs_threshold": [1], # distant marsh beyond the causeway
	"catacombs_1": [],           # every opening is a recess in the same wall
	"catacombs_2": [],
	"catacombs_3": [],
	"crypt_threshold": [1],    # the blue cemetery beyond the broken roof
	"crypt_skulls": [1, 2, 3],   # the drowned city beyond the arches
	"crypt_lava": [2],           # 1 carries the painted pillar and cage, 3 the lava rock
	"ashes_threshold": [1],     # blue night outside the left church window
	"hell_gate": [1, 2, 3],
}


static func arrange(room: Node2D) -> void:
	if room.get_node_or_null("Painting") == null:
		return
	var key := room.scene_file_path.get_file().get_basename()
	var fog := room.get_node_or_null("FogFar") as Parallax2D
	if fog != null:
		fog.scroll_scale = Vector2.ONE
	var decor := room.get_node_or_null("DecorBack") as Parallax2D
	if decor != null:
		decor.scroll_scale = Vector2.ONE
	_clip_clouds(room)


## How far a window's plate may travel with the camera: 0 keeps it still.
static func window_factor(room: Node2D, index: int, factor: float) -> float:
	var key := room.scene_file_path.get_file().get_basename()
	if not FAR_WINDOWS.has(key):
		return factor
	return factor if (FAR_WINDOWS[key] as Array).has(index) else 0.0


## The outline of one opening, rebuilt from its feather triangles
## (centre, corner k, corner k + 1).
static func window_outline(room: Node2D, index: int) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var windows := room.get_node_or_null("DepthWindows")
	if windows == null:
		return outline
	var edge := 1
	while true:
		var triangle := windows.get_node_or_null("Window%dFeather%d" % [index, edge]) as Polygon2D
		if triangle == null:
			break
		outline.append(triangle.polygon[1])
		edge += 1
	return outline


## Clouds belong to the sky. Unclipped, a translucent bank drifting at a fifth
## of the camera's speed slides across towers, trees and bridges. Inside the
## sky's opening (window 1, the one every outdoor panel cuts along its
## skyline) they pass behind all of it.
static func _clip_clouds(room: Node2D) -> void:
	var layers: Array[Node] = []
	for name in ["CloudsFar", "CloudsNear"]:
		var layer := room.get_node_or_null(name)
		if layer != null:
			layers.append(layer)
	if layers.is_empty():
		return
	var outline := window_outline(room, 1)
	if outline.size() < 3:
		for layer in layers:
			(layer as CanvasItem).visible = false
		return
	var sky := Polygon2D.new()
	sky.name = "SkyClip"
	sky.polygon = outline
	sky.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	sky.z_index = -28
	room.add_child(sky)
	var windows := room.get_node_or_null("DepthWindows")
	if windows != null:
		room.move_child(sky, windows.get_index() + 1)
	for layer in layers:
		layer.reparent(sky, false)
		(layer as CanvasItem).z_index = 0
