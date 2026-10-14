"""Rooms drawn as one painted panel each (assets/levels/*.png, 1280x720): the
picture is the level, the colliders trace the ledges and stairs painted on it.
See tools/rooms/trace_panel.py for how a panel becomes candidates, and
docs/DATA_FORMATS.md (Rooms) for the fields.

Fields beyond the usual: "painting" (the png), "ground" (painted solid
blocks), "ledges" (painted, jump-through), "ramps" (painted stairs as slopes),
"platforms" (extra broken steps drawn with sheet pieces where the painting
leaves a gap no double jump can cross), "lights" (candles, from the tracer).

Every room has an entrance (player) on the left and an exit (door) on the
right, and check_reach() proves the door can be reached from the entrance by
jumping: single jump 46 px, double 93 px, ~170 px across per double jump.
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---------------------------------------------------------------- reach ---

# Conservative rather than ballistic maxima: the player must be able to make
# the route from a short run-up, with a late second jump, not only from the
# mathematically perfect edge pixel at full speed.
JUMP_UP = 76.0
JUMP_ACROSS = 132.0
DROP_ACROSS = 105.0
# The hero's arc (scripts/player/player.gd BASE_STATS, player.tscn body): a
# jump and an air jump at its apex. A climb is judged on that arc, cut by
# REACH_MARGIN for a short run-up and a late second press; a flat line
# across a big rise underrated real hops by a third (swamp_moon's pier).
RUN_SPEED = 150.0
JUMP_VELOCITY = 320.0
GRAVITY = 1100.0
BODY_WIDTH = 14.0
REACH_MARGIN = 0.85
def _flyers():
    """Every creature that flies (behaviour "flyer", its own or through "extends"),
    the engine's and a laid-over game pack's (content/data): it needs no floor
    under its spawn."""
    docs = {}
    for root in (os.path.join(ROOT, "data", "enemies"), os.path.join(ROOT, "content", "data", "enemies")):
        for file in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            if file.endswith(".json"):
                with open(os.path.join(root, file), encoding="utf-8") as f:
                    docs.setdefault(file[:-5], {}).update(json.load(f))

    def behaviour(eid, seen=()):
        doc = docs.get(eid, {})
        if "behaviour" in doc or doc.get("extends") in (None, *seen):
            return doc.get("behaviour")
        return behaviour(doc["extends"], (*seen, eid))

    return {"ophanim"} | {eid for eid in docs if behaviour(eid) == "flyer"}  # ophanim: a boss over its arena


FLYERS = _flyers()


def _surfaces(room):
    """Walkable surfaces (x, y, w) and the pairs joined by walking (ramps).
    A crumbling platform is not one: it gives way, so the route never counts
    on it (reach_test.gd leaves it out too)."""
    out = []
    links = []
    for x, y, w, h in room.get("ground", []):
        out.append((x, y, w))
    for x, y, w, h in room.get("ledges", []):
        out.append((x, y, w))
    for x, y, w, h in room.get("platforms", []):
        out.append((x, y, w))
    for x0, y0, x1, y1 in room.get("ramps", []):
        # a ramp is walked end to end: both ends, plus its span
        base = len(out)
        out.append((min(x0, x1), min(y0, y1), abs(x1 - x0)))
        out.append((x0, y0, 4))
        out.append((x1, y1, 4))
        links += [(base, base + 1), (base, base + 2), (base + 1, base + 2)]
    return out, links


def _climb_reach(rise):
    """How far across a double jump carries the body onto a surface `rise` px up."""
    peak = JUMP_VELOCITY ** 2 / GRAVITY  # two apexes stacked
    airtime = 2.0 * JUMP_VELOCITY / GRAVITY + (2.0 * (peak - rise) / GRAVITY) ** 0.5
    # the body stands on an edge by half its width at either end
    return RUN_SPEED * airtime * REACH_MARGIN + BODY_WIDTH


def _can_jump(a, b):
    ax, ay, aw = a
    bx, by, bw = b
    gap = max(0.0, bx - (ax + aw), ax - (bx + bw))
    rise = ay - by  # positive: b is higher
    if rise > 0:
        return rise <= JUMP_UP and gap <= max(JUMP_ACROSS - rise * 0.9, _climb_reach(rise))
    return gap <= max(JUMP_ACROSS, DROP_ACROSS + min(120.0, -rise * 0.5))


def check_reach(name, room):
    valid = True
    surfaces, links = _surfaces(room)
    joined = {}
    for a, b in links:
        joined.setdefault(a, set()).add(b)
        joined.setdefault(b, set()).add(a)
    px, py = room["player"]
    dx, dy = room["door"]

    def under(x, y):
        best = None
        for i, (sx, sy, sw) in enumerate(surfaces):
            if sx - 8 <= x <= sx + sw + 8 and sy >= y - 4 and (best is None or sy < surfaces[best][1]):
                best = i
        return best

    start, goal = under(px, py), under(dx, dy)
    if start is None or goal is None:
        print(f"  !! {name}: entrance or exit stands on nothing")
        return False
    seen = {start}
    frontier = [start]
    while frontier:
        i = frontier.pop()
        for j in range(len(surfaces)):
            if j not in seen and (j in joined.get(i, ()) or _can_jump(surfaces[i], surfaces[j])):
                seen.add(j)
                frontier.append(j)
    if goal not in seen:
        print(f"  !! {name}: the exit cannot be reached from the entrance")
        valid = False
    lost = [surfaces[i] for i in range(len(surfaces)) if i not in seen and surfaces[i][2] > 8]
    if lost:
        print(f"  .. {name}: unreachable surfaces: {lost}")
    # a walker the player cannot get to keeps the door shut forever
    for enemy_id, x, y in room["spawns"]:
        if enemy_id in FLYERS:
            continue
        stand = under(x, y + 12)
        if stand is None:
            print(f"  !! {name}: {enemy_id} at ({x}, {y}) stands on nothing")
            valid = False
        elif stand not in seen:
            print(f"  !! {name}: {enemy_id} at ({x}, {y}) cannot be reached")
            valid = False
    for prop_id, x, y in room.get("props", []):
        stand = under(x, y)
        if stand is None:
            print(f"  !! {name}: prop {prop_id} at ({x}, {y}) stands on nothing")
            valid = False
        elif stand not in seen:
            print(f"  !! {name}: prop {prop_id} at ({x}, {y}) cannot be reached")
            valid = False
        elif abs(surfaces[stand][1] - y) > 2:
            print(f"  !! {name}: prop {prop_id} at ({x}, {y}) floats above its surface")
            valid = False
    # people, and every stop of their round: a person has no gravity
    for npc_index, (npc_id, x, y) in enumerate(room.get("npcs", [])):
        try:
            if "npc_paths" in room:
                stops = [(0, 0)] + room["npc_paths"][npc_index]
            else:
                with open(os.path.join(ROOT, "data", "npcs", npc_id + ".json")) as f:
                    stops = [(0, 0)] + [tuple(p) for p in json.load(f).get("path", [])]
        except OSError:
            stops = [(0, 0)]
        for dx, dy in stops:
            if under(x + dx, y + dy) is None:
                print(f"  !! {name}: {npc_id} at ({x + dx}, {y + dy}) stands on nothing")
                valid = False
    return valid


# ---------------------------------------------------------------- rooms ---

PAINTED = {
    "village_night": dict(
        # A painted room (docs/DATA_FORMATS.md, Rooms): the panel *is* the level
        # and the colliders trace the ledges and stairs drawn on it. Start at the
        # shrine niche top left, the gate is top right; the crypts below are a
        # detour for the chest. "ledges" and "ground" are painted (colliders
        # only), "platforms" are extra broken steps drawn with sheet pieces
        # where the painting leaves a gap no double jump can cross.
        painting="graveyard_moon", width=1280, height=720, weather="ash", fog=0.2, intro="", music="village_night",
        ground=[(0, 195, 310, 24), (0, 395, 80, 20), (80, 405, 40, 20), (120, 420, 80, 20),
                (280, 527, 320, 30), (600, 538, 40, 30), (640, 560, 200, 40), (840, 520, 120, 60),
                (940, 625, 90, 30), (1095, 520, 185, 30), (1045, 560, 50, 20),
                (1060, 655, 220, 65)],
        # The dark bone mound below the first stair is scenery, not a hidden
        # catch floor. A missed jump there is a fall out of the room.
        void_kill_y=690,
        # Cover the whole visible stair, including its upper and lower landings.
        # The old middle-only ramp left a 17 px wall at the lower foot.
        ramps=[(200, 420, 300, 527)],
        ledges=[(405, 220, 195, 14), (240, 345, 150, 14), (626, 421, 96, 14), (820, 325, 140, 16), (930, 260, 350, 20)],
        # This short return-climb balcony is now part of the painting itself,
        # supported by the carved stone of the lower shelf. No sheet pieces
        # or separate grid-textured pillar are drawn on top of it.
        platforms=[(690, 380, 70, 10)],
        painted_platforms=[(690, 380, 70, 10)],
        # The upper bridge breaks at the stair. The loose stone is visible,
        # holds long enough to react, then drops away and returns.
        crumbling_platforms=[(328, 217, 68)],
        spawns=[("possessed_villager", 470, 515), ("possessed_villager", 760, 548), ("possessed_villager", 1150, 508),
                ("possessed_villager", 1050, 248), ("possessed_villager", 330, 333),
                ("shade", 500, 300), ("shade", 900, 200), ("raven", 700, 120)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("possessed_villager", 1150, 508), ("cultist", 760, 548), ("possessed_villager", 1050, 248), ("raven", 700, 120)]],
        props=[("pot", 280, 195), ("rubble", 370, 345), ("barrel_apples", 330, 527), ("box_goods", 365, 527), ("rubble", 500, 527),
               ("pot", 700, 560), ("rubble", 1000, 625), ("chest_wooden", 1200, 655),
               ("secret_wall_village", 1110, 655)],  # Gate log at the crypt's painted floor, not an invisible shelf
        decor=[],
        npcs=[("severin", 300, 345)],  # on the side ledge, where the possessed one spawns
        ambient="#c0bccc",
        lights=[(55, 188, "#ffb060", 50, 0.7, 0.3), (530, 212, "#ffb060", 40, 0.6, 0.3), (50, 390, "#ffb060", 36, 0.5, 0.3),
                (175, 402, "#ffb060", 36, 0.5, 0.3), (330, 522, "#ffb060", 36, 0.5, 0.3), (440, 495, "#ffb060", 50, 0.6, 0.3),
                (600, 402, "#ffb060", 36, 0.5, 0.3), (780, 552, "#ffb060", 36, 0.5, 0.3), (850, 640, "#ffb060", 40, 0.5, 0.3),
                (1235, 465, "#ff9a40", 70, 0.9, 0.3), (1190, 638, "#ff9a40", 50, 0.7, 0.3), (1090, 250, "#ffb060", 40, 0.6, 0.3),
                (1238, 245, "#ffb060", 50, 0.7, 0.3), (875, 75, "#c8d4ff", 220, 0.5, 0.0)],
        player=(40, 175), door=(1242, 228)),
    "graveyard_cross": dict(
        # Second panel: the cross ledge over the chapel, a descent to the bone
        # crypt bottom left, painted stairs climbing to the right wall.
        painting="graveyard_cross", width=1280, height=720, weather="ash", fog=0.2, intro="", music="graveyard",
        intro_cutscene="stranger_meeting",  # the Stranger waits at the end of the first ledge
        # The bottom bone mound is scenery, not a hidden safe floor. Falling
        # below the crypt's last ledge is a void death instead of a walk under
        # the level. The visible bridge and stepping route remain intact.
        ground=[], void_kill_y=690,
        ledges=[(0, 254, 280, 14), (404, 278, 154, 14), (248, 348, 148, 14), (60, 400, 68, 12),
                (0, 520, 88, 12), (82, 538, 74, 12), (188, 518, 596, 14), (785, 545, 207, 14),
                (804, 385, 257, 14), (1061, 386, 30, 14),  # the floor under the arch: the way out
                (1091, 388, 189, 14), (1016, 220, 264, 16), (0, 655, 155, 14),
                (1005, 306, 90, 12)],
        ramps=[(985, 545, 1140, 388)],
        stone_steps=True,  # wall-mounted stone cornices, not green islands at the exit
        platforms=[(1120, 262, 56, 10)],  # one exit foothold; the bone mound is not a stepping-stone course
        crumbling_platforms=[(301, 264, 80)],
        spawns=[("possessed_villager", 400, 506), ("possessed_villager", 650, 506), ("cultist", 880, 533),
                ("possessed_villager", 900, 373), ("zealot", 1180, 376), ("shade", 600, 300), ("raven", 800, 150),
                ("wraith", 300, 600), ("cult_slinger", 1000, 373)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("possessed_villager", 400, 506), ("cultist", 650, 506), ("cult_slinger", 1180, 376),
                ("possessed_villager", 880, 533), ("shade", 600, 300)]],
        props=[("pot", 200, 254), ("barrel", 300, 348), ("crate", 700, 518), ("sack", 860, 545),
               ("chest_wooden", 70, 655), ("barrel_apples", 940, 385)],
        decor=[], npcs=[("nun", 122, 655), ("stranger", 252, 254)], ambient="#c0bccc", lights="auto",
        player=(30, 234), door=(1085, 353)),
    "graveyard_arches": dict(
        # Third panel: the old tree takes the right half; the way out is the
        # ruined arch with a candle, reached over the tree's roots.
        painting="graveyard_arches", width=1280, height=720, weather="ash", fog=0.2, intro="", music="graveyard", void_kill_y=690,
        ground=[],
        ledges=[(0, 220, 265, 14), (223, 257, 112, 12), (373, 275, 61, 12), (393, 350, 280, 14), (6, 389, 70, 12),
                (214, 494, 72, 12), (276, 513, 47, 10), (297, 525, 71, 10), (350, 552, 346, 14), (672, 572, 44, 10),
                (720, 594, 165, 14), (935, 603, 122, 14), (675, 484, 72, 14), (940, 512, 47, 12),
                (1066, 528, 44, 12), (1169, 387, 99, 14), (900, 316, 112, 14), (1050, 292, 110, 14)],
        ramps=[(885, 594, 945, 512)],
        # The root walk at y=552 must lead back to the first upper patrol.
        # Without this stone the descent was one-way and a living enemy above
        # could keep the exit locked forever.
        stone_steps=True,  # broken masonry at the tree, not green floating islands
        platforms=[(1130, 470, 56, 10), (1080, 350, 56, 10)],
        spawns=[("possessed_villager", 500, 338), ("possessed_villager", 450, 540), ("possessed_villager", 600, 540),
                ("cultist", 800, 582), ("zealot", 1220, 375), ("fallen_guard", 950, 304), ("shade", 750, 250),
                ("raven", 600, 120), ("wraith", 250, 620), ("cult_slinger", 1100, 280)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 600, 540), ("cultist", 450, 540), ("cult_slinger", 500, 338),
                ("possessed_villager", 800, 582), ("wraith", 250, 620)]],
        props=[("chest_iron", 150, 220), ("barrel", 420, 350), ("box_goods", 380, 552), ("sack", 850, 594), ("barrel_apples", 1000, 603),
               ("chest_gold", 242, 494), ("pot", 1230, 387)],
        decor=[], npcs=[], ambient="#bcb8cc", lights="auto",
        player=(30, 200), door=(1120, 260)),
    "graveyard_tree": dict(
        # Fourth panel: the tree has grown over everything; a long bridge of
        # roots and stone leads to the chapel, the tower gate is top right.
        painting="graveyard_tree", width=1280, height=720, weather="ash", fog=0.25, intro="", music="graveyard", void_kill_y=690,
        ground=[],
        ledges=[(40, 265, 60, 12), (80, 289, 64, 12), (137, 312, 240, 14), (42, 389, 77, 12), (289, 419, 480, 16),
                (101, 497, 51, 10), (120, 522, 95, 10), (180, 541, 60, 10), (225, 563, 71, 10),
                (435, 583, 60, 10), (481, 604, 56, 10), (538, 615, 270, 14), (732, 635, 150, 14),
                (799, 380, 183, 14), (991, 365, 63, 12), (1048, 410, 125, 12), (1104, 445, 176, 14),
                (1071, 339, 50, 12), (1097, 241, 120, 14)],
        ramps=[],
        stone_steps=True,
        platforms=[(1150, 300, 56, 10)],  # the only added step needed to return to the gate
        spawns=[("possessed_villager", 400, 407), ("possessed_villager", 650, 407), ("cultist", 880, 368),
                ("fallen_guard", 1200, 433), ("possessed_villager", 600, 603), ("zealot", 300, 300),
                ("shade", 700, 250), ("hollow_wraith", 950, 600), ("raven", 500, 150)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 650, 407), ("cultist", 400, 407), ("cult_slinger", 880, 368),
                ("possessed_villager", 600, 603), ("raven", 500, 150)]],
        props=[("pot", 110, 289), ("barrel", 350, 312), ("crate", 500, 419), ("rubble", 720, 419), ("blood_altar", 1000, 365),
               ("chest_wooden", 760, 635), ("pot", 250, 563), ("crate", 1250, 445)],
        decor=[], npcs=[("mara", 955, 380)], ambient="#bcb8cc", lights="auto",
        player=(60, 245), door=(1195, 209)),  # under the ruined arch between the gate pillars
    "swamp_moon": dict(
        # Fifth panel: the graveyard sinks into a swamp; rotten piers over
        # black water, the lantern post on the far pier marks the way on.
        painting="swamp_moon", width=1280, height=720, weather="fireflies", fog=0.3, intro="", music="graveyard", void_kill_y=690,
        ground=[],  # the painted water is not a walkable swamp bed
        ledges=[(10, 201, 80, 12), (130, 231, 57, 10), (172, 252, 57, 10), (153, 264, 144, 12), (17, 351, 157, 14),
                (425, 338, 236, 14), (216, 456, 48, 10), (286, 474, 216, 14), (656, 415, 226, 14), (626, 474, 61, 10),
                (928, 474, 51, 10), (638, 535, 104, 12), (914, 550, 53, 10), (1165, 554, 78, 12), (512, 568, 144, 12),
                (594, 599, 75, 10), (376, 603, 45, 10), (1077, 413, 194, 14)],
        ramps=[],
        platforms=[(1120, 478, 56, 10)],  # timber return step under the exit pier
        crumbling_platforms=[(325, 303, 72, "timber")],
        spawns=[("possessed_villager", 520, 326), ("cultist", 750, 403), ("possessed_villager", 400, 462),
                ("zealot", 1150, 401), ("fallen_guard", 580, 556), ("shade", 800, 300), ("wraith", 300, 600),
                ("raven", 900, 150), ("shade", 1000, 250)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("cultist", 750, 403), ("possessed_villager", 520, 326), ("cult_slinger", 1150, 401),
                ("possessed_villager", 580, 556), ("hollow_wraith", 300, 600)]],
        props=[("barrel", 250, 264), ("pot", 600, 338), ("box_goods", 780, 415), ("sack", 350, 474),
               ("chest_wooden", 1200, 554), ("barrel_apples", 100, 351), ("pot", 680, 535)],
        decor=[], npcs=[("villager", 470, 474)], ambient="#b4b8cc", lights="auto",
        player=(40, 181), door=(1195, 381)),
    "swamp_red": dict(
        # Sixth panel: the moon turns red over the swamp. Stepping stones and
        # pier stumps across the water; the fenced bank top right leads on.
        painting="swamp_red", width=1280, height=720, weather="embers", fog=0.3, intro="", music="dead_bridge", void_kill_y=690,
        ground=[],
        ledges=[(38, 347, 274, 14), (323, 404, 48, 10), (470, 395, 49, 10), (571, 405, 91, 12), (522, 434, 167, 12),
                (704, 329, 53, 10), (39, 505, 122, 12), (187, 499, 200, 12), (943, 412, 83, 12), (1047, 425, 150, 14),
                (1121, 255, 159, 14)],
        ramps=[],
        # The middle return step is a rotting timber pier rooted in the water
        # on this painting; only the far-right climb needs separate pieces.
        platforms=[(860, 452, 60, 10), (1220, 370, 56, 10), (1220, 310, 56, 10)],
        painted_platforms=[(860, 452, 60, 10)],
        crumbling_platforms=[(778, 366, 70, "timber")],
        spawns=[("possessed_villager", 200, 335), ("cultist", 600, 422), ("possessed_villager", 300, 487),
                ("zealot", 1120, 413), ("fallen_guard", 980, 400), ("wraith", 600, 300), ("shade", 850, 250),
                ("raven", 400, 150), ("elite_possessed", 1180, 243), ("cult_slinger", 1170, 413)],
        props=[("barrel", 120, 347), ("crate", 280, 347), ("pot", 580, 434), ("sack", 250, 499), ("barrel_apples", 1100, 425),
               ("chest_cursed", 80, 505), ("pot", 1160, 255)],
        decor=[], npcs=[], ambient="#c8b0b4", lights="auto",
        player=(60, 327), door=(1240, 223)),  # the bank starts at x 38
    "swamp_crypt": dict(
        # Seventh panel: the swamp ends at a crypt door lit by candles; the
        # stairs beside it go down into the catacombs.
        painting="swamp_crypt", width=1280, height=720, weather="embers", fog=0.3, intro="", music="dead_bridge", void_kill_y=690,
        ground=[(930, 560, 70, 20)],
        ledges=[(28, 319, 177, 14), (0, 261, 60, 10), (218, 258, 64, 10), (15, 414, 203, 14), (276, 337, 67, 10),
                (285, 375, 56, 10), (301, 404, 47, 10), (394, 397, 94, 12), (387, 432, 86, 12), (451, 312, 54, 10),
                (533, 321, 44, 10), (506, 256, 196, 14), (649, 312, 78, 12), (780, 311, 74, 12), (919, 314, 102, 12),
                (1116, 311, 149, 14), (1105, 240, 75, 10), (1097, 175, 148, 14), (533, 451, 184, 14), (738, 459, 53, 10), (829, 472, 58, 10),
                (591, 386, 45, 10), (371, 540, 162, 12), (429, 583, 46, 10), (227, 586, 90, 12), (114, 606, 49, 10),
                (1097, 485, 76, 12), (1220, 488, 60, 12), (901, 548, 58, 10), (1060, 603, 54, 10),
                (783, 655, 86, 12)],
        ramps=[(1000, 560, 1060, 603)],
        platforms=[],  # painted masonry and roots already carry the whole route
        spawns=[("possessed_villager", 100, 402), ("cult_caller", 600, 244), ("possessed_villager", 600, 439),
                ("fallen_guard", 1200, 299), ("preacher_acolyte", 960, 302), ("zealot", 450, 528), ("wraith", 700, 400),
                ("shade", 300, 200), ("raven", 850, 120), ("elite_possessed", 690, 300)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 600, 439), ("cultist", 100, 402), ("cult_slinger", 960, 302), ("possessed_villager", 450, 528)],
               [("fallen_champion", 1200, 299), ("hollow_wraith", 700, 400), ("cultist", 600, 439), ("cult_slinger", 600, 244)]],
        props=[("barrel", 150, 319), ("chest_iron", 200, 414), ("box_goods", 560, 256), ("rubble", 680, 451), ("barrel_apples", 1000, 314),
               ("chest_wooden", 1130, 485), ("pot", 560, 451), ("box_goods", 1200, 311),
               ("secret_wall_swamp", 630, 451)],  # letters behind the tower masonry, not the red root mass
        decor=[], npcs=[], ambient="#c8b0b4", lights="auto",
        player=(40, 299), door=(995, 528)),
    "catacombs_1": dict(
        # Eighth panel: inside. Galleries of bones on four floors, a ladder up
        # to the ossuary with the gilded coffin, the way on at the bottom right.
        painting="catacombs_1", width=1280, height=720, weather="none", fog=0.15, intro="", music="dead_bridge",
        intro_cutscene="voice_in_the_dark",  # the Voice asks its one question
        ground=[(0, 700, 1280, 20)],
        ledges=[(50, 157, 196, 14), (297, 178, 87, 12), (365, 260, 274, 14), (769, 204, 139, 12), (859, 240, 99, 12),
                (956, 234, 182, 14), (1109, 234, 171, 14), (1047, 191, 154, 12), (31, 332, 80, 12), (100, 344, 100, 12),
                (0, 413, 344, 14), (618, 356, 126, 12), (511, 403, 337, 14), (817, 430, 160, 14), (1003, 440, 277, 14),
                (438, 556, 292, 14), (8, 582, 89, 12), (135, 584, 63, 10), (129, 640, 266, 14), (766, 604, 202, 14),
                (1004, 643, 168, 14), (1195, 610, 85, 12)],
        ramps=[(170, 350, 250, 405)],
        platforms=[(1035, 385, 48, 10), (1035, 325, 48, 10), (1035, 268, 48, 10)],
        spawns=[("cultist", 500, 248), ("possessed_villager", 200, 401), ("possessed_villager", 600, 391),
                ("fallen_guard", 900, 418), ("zealot", 1150, 428), ("cult_caller", 800, 592), ("preacher_acolyte", 1050, 222),
                ("possessed_villager", 300, 628), ("shade", 700, 300), ("elder_wraith", 400, 500)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 600, 391), ("cultist", 200, 401), ("cult_slinger", 1150, 428),
                ("possessed_villager", 300, 628), ("hollow_wraith", 700, 300)]],
        props=[("pot", 150, 157), ("barrel", 420, 260), ("crate", 700, 403), ("sack", 1240, 440), ("chest_gold", 1150, 191),
               ("barrel_apples", 250, 413), ("pot", 600, 556), ("crate", 900, 604), ("sack", 80, 582)],
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(70, 137), door=(1167, 408)),
    "catacombs_2": dict(
        # Ninth panel: deeper galleries; the upper floor runs the whole width
        # and ends at the torch-lit arch top right.
        painting="catacombs_2", width=1280, height=720, weather="none", fog=0.15, intro="", music="dead_bridge",
        ground=[(0, 700, 1280, 20)],
        ledges=[(41, 298, 72, 12), (119, 335, 44, 10), (171, 353, 246, 14), (443, 228, 308, 14), (609, 220, 117, 12),
                (763, 229, 374, 14), (1191, 258, 89, 12), (461, 424, 257, 14), (661, 412, 165, 14), (809, 442, 50, 10),
                (834, 471, 58, 10), (885, 501, 73, 10), (929, 521, 197, 14), (1017, 499, 96, 12), (1099, 481, 181, 14),
                (5, 579, 121, 12), (141, 627, 91, 12), (224, 639, 99, 12), (284, 636, 158, 12), (458, 651, 344, 14),
                (665, 616, 45, 10), (772, 602, 94, 12), (767, 633, 168, 14), (893, 695, 387, 12)],
        # The lower-right painted stair is one continuous climb; overlapping
        # one-way rectangles left individual treads unreachable in physics.
        ramps=[(1188, 630, 1260, 680)],
        platforms=[(400, 295, 48, 10)],
        spawns=[("cultist", 350, 341), ("possessed_villager", 550, 412), ("fallen_guard", 1000, 509),
                ("zealot", 1200, 469), ("cultist", 700, 216), ("preacher_acolyte", 950, 217),
                ("possessed_villager", 600, 639), ("possessed_villager", 850, 621), ("shade", 500, 300),
                ("wraith", 1000, 380), ("elite_possessed", 1050, 217), ("cult_slinger", 220, 341)],
        props=[("pot", 80, 298), ("barrel", 250, 353), ("box_goods", 600, 424), ("sack", 1050, 521), ("barrel_apples", 500, 228),
               ("chest_wooden", 60, 579), ("pot", 300, 636), ("box_goods", 700, 651), ("sack", 1190, 481),
               ("secret_wall_catacombs", 1020, 695)],  # the bricked-up ossuary niche: names under the lid
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(60, 278), door=(1128, 197)),
    "catacombs_3": dict(
        # Tenth panel: the galleries give way to a cave on the right; the
        # tunnel keeps going down at the bottom right.
        painting="catacombs_3", width=1280, height=720, weather="none", fog=0.15, intro="", music="dead_bridge",
        ground=[(0, 700, 1280, 20)],
        ledges=[(46, 146, 80, 12), (2, 232, 201, 14), (139, 205, 278, 14), (444, 242, 228, 14), (742, 312, 274, 14),
                (1110, 382, 44, 10), (214, 405, 90, 10), (1, 442, 539, 14), (576, 458, 111, 12), (675, 538, 49, 10),
                (806, 550, 144, 14), (946, 583, 50, 10), (3, 603, 85, 12), (1085, 637, 57, 10), (1086, 653, 75, 10),
                (1151, 659, 129, 12), (165, 664, 173, 14), (507, 667, 121, 12), (625, 691, 149, 10)],
        ramps=[(583, 460, 675, 535)],
        platforms=[],
        spawns=[("cultist", 300, 193), ("possessed_villager", 550, 230), ("fallen_guard", 850, 300),
                ("zealot", 400, 430), ("possessed_villager", 100, 430), ("cultist", 880, 538),
                ("preacher_acolyte", 250, 652), ("possessed_villager", 560, 655), ("shade", 900, 450),
                ("wraith", 1150, 500), ("elite_possessed", 1180, 647)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 400, 430), ("cultist", 100, 430), ("cult_slinger", 850, 300), ("possessed_villager", 560, 655)],
               [("shield_bearer", 880, 538), ("cultist", 300, 193), ("cult_slinger", 550, 230), ("hollow_wraith", 900, 450),
                ("possessed_villager", 250, 652)]],
        props=[("pot", 100, 232), ("barrel", 200, 205), ("crate", 600, 242), ("rubble", 950, 312), ("barrel_apples", 150, 442),
               ("chest_gold", 60, 603), ("pot", 300, 664), ("crate", 700, 538), ("rubble", 1130, 583, "wide")],  # on the floor the seam added
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(60, 126), door=(965, 551)),
    "crypt_skulls": dict(
        # Eleventh panel: the blue crypt over the underground river; the gate
        # with candles on the right wall.
        painting="crypt_skulls", width=1280, height=720, weather="none", fog=0.2, intro="", music="dead_bridge",
        # the rock on either bank; the river between them is the edge of the map
        ground=[(0, 700, 230, 20), (680, 700, 600, 20)],
        ledges=[(43, 218, 65, 10), (37, 254, 196, 14), (418, 256, 53, 10), (458, 268, 59, 10), (508, 275, 56, 10),
                (919, 390, 68, 12), (836, 423, 206, 14), (1043, 404, 80, 12), (807, 449, 48, 10),
                (639, 457, 169, 14), (583, 472, 60, 10), (112, 428, 52, 10), (4, 465, 103, 12), (93, 475, 132, 12),
                (181, 464, 45, 10), (362, 569, 45, 10), (381, 581, 129, 12), (1160, 550, 120, 12), (1146, 603, 112, 12),
                (1004, 615, 104, 12), (886, 626, 79, 12), (929, 643, 70, 10), (853, 678, 45, 10), (687, 691, 107, 10),
                (593, 627, 62, 10), (675, 628, 45, 10), (282, 661, 63, 10)],
        ramps=[(190, 490, 320, 522)],
        platforms=[(300, 300, 56, 10)],
        spawns=[("possessed_villager", 500, 263), ("fallen_guard", 700, 445), ("zealot", 950, 411),
                ("elite_cultist", 1080, 392), ("possessed_villager", 150, 463), ("possessed_villager", 450, 569),
                ("preacher_acolyte", 950, 631), ("wraith", 500, 400), ("shade", 800, 250), ("shade", 1100, 300)],
        # reinforcements: each wave rises, awake, once the room before it is down
        waves=[[("shield_bearer", 700, 445), ("cultist", 150, 463), ("cult_slinger", 950, 411), ("possessed_villager", 450, 569)],
               [("fallen_guard", 950, 631), ("cultist", 500, 263), ("cult_slinger", 1080, 392), ("hollow_wraith", 500, 400),
                ("shade", 1100, 300)]],
        props=[("chest_iron", 120, 254), ("barrel", 200, 254), ("blood_altar", 890, 423), ("sack", 750, 457), ("funeral_offering", 1000, 423),
               ("chest_cursed", 300, 661), ("pot", 400, 581), ("box_goods", 1245, 603), ("sack", 1180, 603)],
        decor=[], npcs=[], ambient="#b8bccc", lights="auto",
        player=(60, 234), door=(1080, 583)),
    "crypt_lava": dict(
        # Twelfth panel, the Knight of Ash: the crypt cracks open over lava. He
        # waits on the long gallery in the middle; the way on is the dark arch
        # top right. Lava burns and returns the hero to safe footing; beyond
        # the panel there is no invisible safety floor.
        painting="crypt_lava", width=1280, height=720, weather="embers", fog=0.2, intro="", music="boss_knight",
        intro_cutscene="knight_arrival",
        ground=[],
        ledges=[(28, 173, 170, 14), (103, 222, 100, 10), (188, 235, 96, 10), (266, 252, 47, 10), (278, 261, 262, 14),
                (613, 259, 46, 10), (672, 200, 301, 16), (821, 180, 61, 10), (956, 180, 96, 12), (958, 226, 148, 12),
                (1097, 208, 49, 14), (581, 362, 93, 12), (424, 401, 98, 12), (513, 428, 54, 10), (584, 458, 208, 14),
                (796, 474, 177, 14), (846, 440, 63, 10), (992, 450, 173, 14), (632, 557, 97, 12), (1057, 564, 109, 12),
                (1155, 607, 60, 10), (116, 581, 47, 10), (227, 615, 59, 10), (306, 666, 131, 12), (472, 670, 111, 12)],
        ramps=[(240, 618, 330, 665), (1140, 208, 1280, 108)],
        platforms=[],  # use the painted gallery and stair, not blocks over lava
        hazards=[(590, 694, 560, 26)],  # the lava pool under the gallery
        spawns=[("knight_of_ash", 820, 188)],
        props=[("barrel", 120, 173), ("crate", 400, 261), ("pot", 700, 458), ("sack", 900, 474), ("barrel_apples", 1100, 450),
               ("chest_gold", 500, 670)],
        decor=[], npcs=[], ambient="#d0b4b0", lights="auto",
        player=(50, 153), door=(1130, 176)),
    "hell_gate": dict(
        # Thirteenth panel, the Ophanim: the locked gate of the pit, a grand
        # stair up to it over a bridge of bone. The gate is the exit.
        painting="hell_gate", width=1280, height=720, weather="embers", fog=0.15, intro="", music="boss_ophanim",
        intro_cutscene="ophanim_arrival", outro_cutscene="ch1_finale",  # its words are in the scene, not a caption under it
        ground=[(900, 372, 220, 30)],
        ledges=[(60, 142, 100, 12), (159, 176, 111, 14), (364, 239, 154, 14),
                (81, 393, 64, 10), (123, 416, 100, 12), (194, 447, 51, 10), (203, 462, 95, 10), (290, 492, 168, 14),
                (530, 484, 44, 10), (605, 482, 255, 16), (1039, 425, 201, 14),
                (453, 568, 151, 12), (563, 614, 46, 10), (648, 600, 45, 10), (79, 643, 60, 10), (125, 671, 80, 10),
                (1080, 633, 70, 10)],  # no phantom ledges below the continuous floor
        ramps=[(790, 494, 900, 384), (270, 176, 364, 239)],
        platforms=[],  # no isolated stones beside the boss gate
        hazards=[(425, 694, 102, 26), (641, 694, 150, 26), (990, 694, 88, 26)],  # the lakes between the rocks
        spawns=[("ophanim", 1000, 250)],
        props=[("pot", 250, 176), ("barrel", 400, 239), ("box_goods", 740, 482), ("rubble", 350, 492),
               ("chest_cursed", 670, 482)],  # reachable bridge cache, not a one-way drop into lava
        decor=[], npcs=[], ambient="#d8b8b0", lights="auto",
        player=(80, 122), door=(1000, 340)),
    "preacher_nave": dict(
        # The Blind Preacher's arena (docs/CHAPTER1.md, scene 7): the nave he
        # preached in, before the church proper. One fight, no adds but his own.
        interior=True, floor="ledge", width=960, height=420, weather="none", fog=0.1,
        intro="", intro_cutscene="preacher_arrival", music="arena",
        ground=[(0, 380, 960, 40)],
        # The central loft was isolated by both expansion seams and had no
        # combat role; keep the two reachable side balconies around the arena.
        platforms=[(140, 300, 140, 14), (680, 300, 140, 14)],
        pillars=[(90, 380), (330, 380), (630, 380), (870, 380)],
        decor=[("arch", 210, 360, "back"), ("arch", 480, 360, "back"), ("arch", 750, 360, "back")],
        spawns=[("blind_preacher", 640, 380)],
        props=[("pot", 120, 380), ("pot", 840, 380)],
        npcs=[],
        ambient="#c8bcc8",
        lights=[(90, 360, "#ffb060", 90, 1.0, 0.3), (330, 360, "#ffb060", 90, 1.0, 0.3), (630, 360, "#ffb060", 90, 1.0, 0.3),
                (870, 360, "#ffb060", 90, 1.0, 0.3), (480, 230, "#fff0c0", 200, 1.1, 0.1)],
        player=(60, 360), door=(926, 348)),
    "church": dict(
        # The church, between the crypts and the arenas: no enemies, one
        # priest. A nave of stone built from the sheet pieces until a painted
        # panel replaces it — two choir lofts, the altar (the save shrine) in
        # the middle, the bell tower above. Quiet on purpose (docs/CHAPTER1.md).
        # 420 tall so a screen taller than 16:9 still shows only church.
        interior=True, floor="ledge", width=960, height=420, weather="none", fog=0.0, intro="", music="church",
        intro_cutscene="church_matthew",  # the bell, and the priest at the altar
        ground=[(0, 380, 960, 40)],
        # The low choir steps overlap the gallery piers instead of hovering in
        # the nave; the 42/48 px rise still keeps both balconies reachable.
        platforms=[(0, 290, 180, 14), (780, 290, 180, 14), (170, 338, 56, 10), (730, 338, 56, 10)],
        pillars=[(120, 380), (300, 380), (660, 380), (840, 380)],
        decor=[("arch", 210, 360, "back"), ("arch", 390, 360, "back"), ("arch", 570, 360, "back"), ("arch", 750, 360, "back")],
        spawns=[],
        # the book of the condemned, beside the altar: it is there only once
        # Matthew has spoken of it (requires_flag in data/props/altar_book.json)
        props=[("altar_book", 420, 380)],
        npcs=[("matthew", 540, 380)],
        ambient="#d8d0d4",
        # indoors the lights multiply into dark stone, so they burn brighter than outside
        lights=[(120, 360, "#ffb060", 90, 1.0, 0.3), (300, 360, "#ffb060", 90, 1.0, 0.3), (660, 360, "#ffb060", 90, 1.0, 0.3),
                (840, 360, "#ffb060", 90, 1.0, 0.3), (480, 340, "#ffc080", 220, 1.3, 0.15),
                (210, 310, "#8fa8ff", 150, 0.8, 0.05), (390, 310, "#8fa8ff", 150, 0.8, 0.05),
                (570, 310, "#8fa8ff", 150, 0.8, 0.05), (750, 310, "#8fa8ff", 150, 0.8, 0.05)],
        bell=(480, 120),
        player=(60, 360), door=(926, 348), shrine=(480, 380)),
    # Chapter II, Seir (docs/CHAPTER2.md). Panels drawn by Codex from
    # docs/CHAPTER2_ART.md (credited in assets/CREDITS.md), traced with
    # tools/rooms/trace_panel.py. The cold harbour city: one long floor in most
    # rooms, because the people of Seir sit on it and wait.
    "seir_road": dict(
        # The coast road: the dead tree on the bluff, the city's gate tower on
        # the right. Lazarus lies by the milestone; the ravens are the fight.
        painting="seir_road", width=1280, height=720, weather="ash", fog=0.2, intro="", music="road",
        intro_cutscene="lazarus_on_the_road", void_kill_y=690,
        ground=[(0, 470, 222, 250), (0, 567, 1280, 153)],
        ledges=[(226, 477, 49, 12), (265, 508, 55, 12)],
        spawns=[("raven", 150, 250), ("raven", 270, 330)],
        props=[("rubble", 700, 567), ("pot", 980, 567)],
        decor=[], npcs=[("lazarus", 420, 567)], ambient="#bcc0cc", lights="auto",
        player=(40, 450), door=(1190, 535)),
    "seir_gate": dict(
        # The gatehouse: the wardens stand under the portcullis and wait, so the
        # way on is open from the start; the gallery above is reached by the stair.
        painting="seir_gate", width=1280, height=720, weather="none", fog=0.12, intro="", music="road", void_kill_y=690,
        ground=[(0, 545, 1280, 175)],
        # the gallery stops short of the stair's head, which rises under it
        ledges=[(28, 253, 352, 14), (511, 272, 339, 14)],
        ramps=[(175, 545, 490, 253)],
        spawns=[("gate_warden", 950, 533), ("gate_warden", 1050, 533), ("waiting_townsman", 620, 533),
                ("waiting_townsman", 300, 241), ("waiting_townsman", 700, 260)],
        props=[("seir_cache_jonah_sermon", 120, 253), ("crate", 430, 545), ("barrel", 760, 545)],
        decor=[], npcs=[], ambient="#c4bcb8", lights="auto",
        player=(40, 525), door=(1215, 513)),
    "seir_street": dict(
        # A street of doorsteps over the canal, a waiter on each; two shades in
        # the windows above are the only ones who move.
        painting="seir_street", width=1280, height=720, weather="ash", fog=0.18, intro="", music="village_night", void_kill_y=690,
        ground=[(0, 535, 1280, 185)],
        spawns=[("waiting_townsman", 50, 523), ("waiting_townsman", 165, 523), ("waiting_townsman", 565, 523),
                ("waiting_townsman", 660, 523), ("waiting_townsman", 905, 523), ("waiting_townsman", 1010, 523),
                ("shade", 300, 230), ("shade", 1000, 230)],
        props=[("barrel", 290, 535), ("pot", 760, 535)],
        decor=[], npcs=[], ambient="#bcc0cc", lights="auto",
        player=(110, 515), door=(1215, 503)),
    "seir_square": dict(
        # The square of the stopped clock. The dry fountain is the rest point;
        # Jonah preaches from the terrace on the east side, up its stair.
        painting="seir_square", width=1280, height=720, weather="ash", fog=0.15, intro="", music="village_night", void_kill_y=690,
        ground=[(0, 577, 1280, 143)],
        ledges=[(482, 527, 281, 12), (607, 487, 61, 10), (860, 362, 180, 14), (1097, 363, 143, 14)],
        ramps=[(885, 362, 1130, 577)],
        spawns=[("waiting_townsman", 200, 565), ("waiting_townsman", 330, 565), ("waiting_townsman", 520, 515),
                ("waiting_townsman", 1180, 565), ("waiting_townsman", 800, 565), ("cult_caller", 1180, 351)],
        props=[("pot", 150, 577), ("barrel", 1220, 363)],
        decor=[], npcs=[("jonah", 960, 362)], ambient="#c0bccc", lights="auto",
        player=(55, 557), door=(1235, 545)),
    "seir_roofs": dict(
        # Over the roofs (the square's fork): chimneys and a belfry, climbed
        # left to right; what lives up here flies. Below the tiles is the drop.
        painting="seir_roofs", width=1280, height=720, weather="ash", fog=0.2, intro="", music="village_night", void_kill_y=690,
        ground=[],
        ledges=[(0, 580, 349, 14), (56, 538, 62, 12), (173, 488, 230, 14), (438, 410, 263, 14), (491, 380, 83, 12),
                (652, 333, 334, 14), (949, 266, 211, 14), (1144, 274, 136, 14)],
        ramps=[(370, 488, 445, 410)],
        spawns=[("shade", 300, 300), ("shade", 780, 250), ("shade", 1050, 380),
                ("raven", 600, 150), ("raven", 1000, 150), ("raven", 250, 380)],
        props=[("pot", 300, 488), ("rubble", 860, 333)],
        decor=[], npcs=[], ambient="#c0bccc", lights="auto",
        player=(30, 560), door=(1240, 242)),
    "seir_canal": dict(
        # Along the canal (the square's fork): two quays and two bridges over
        # the red water; the drowned climb out of it. The water is a fall.
        painting="seir_canal", width=1280, height=720, weather="ash", fog=0.25, intro="", music="village_night", void_kill_y=690,
        ground=[(0, 413, 408, 307), (872, 413, 408, 307)],
        ledges=[(388, 377, 221, 14), (607, 395, 47, 12), (652, 377, 242, 14), (1162, 403, 96, 10)],
        spawns=[("drowned", 500, 365), ("drowned", 760, 365), ("drowned", 300, 401), ("drowned", 1000, 401),
                ("waiting_townsman", 150, 401), ("waiting_townsman", 1100, 401)],
        props=[("barrel", 120, 413), ("crate", 980, 413)],
        decor=[], npcs=[], ambient="#c8b8bc", lights="auto",
        player=(20, 393), door=(1225, 371)),
    "seir_quay": dict(
        # The quay: Naomi's lamp on the bench is the only warm light; the
        # sailors' shrine is the rest point.
        painting="seir_quay", width=1280, height=720, weather="ash", fog=0.25, intro="", music="dead_bridge",
        intro_cutscene="quay_arrival", void_kill_y=690,
        ground=[(0, 490, 1280, 230)],
        ledges=[(349, 436, 59, 12), (925, 452, 68, 12), (839, 413, 96, 12)],
        spawns=[("drowned", 180, 478), ("drowned", 700, 478), ("drowned", 1010, 478),
                ("waiting_townsman", 380, 478), ("waiting_townsman", 1110, 478)],
        props=[("barrel", 820, 490)],
        decor=[], npcs=[("naomi", 500, 490), ("lazarus_quay", 580, 490)], ambient="#bcbccc", lights="auto",
        player=(20, 470), door=(1255, 458)),
    "seir_wrecks": dict(
        # The burned hulls. The quay runs the whole way; the right hull's deck
        # (and the Orpah's sealed cabin on it) is climbed from the crane.
        painting="seir_wrecks", width=1280, height=720, weather="ash", fog=0.25, intro="", music="dead_bridge", void_kill_y=690,
        ground=[(0, 507, 1280, 213)],
        ledges=[(653, 350, 85, 12), (734, 354, 124, 12), (821, 358, 110, 12), (931, 362, 144, 12), (1075, 366, 167, 12)],
        platforms=[(540, 455, 50, 10), (600, 408, 50, 10)],  # two timber steps hung from the crane, up to the deck
        spawns=[("drowned", 200, 495), ("drowned", 400, 495), ("drowned", 860, 495), ("drowned", 1000, 495),
                ("drowned", 850, 342), ("sea_wraith", 300, 200), ("sea_wraith", 900, 250), ("drowned_bosun", 700, 495)],
        props=[("seir_cache_orpah_log", 1150, 366), ("barrel", 300, 507), ("crate", 1050, 507)],
        decor=[], npcs=[], ambient="#c4bcc4", lights="auto",
        player=(20, 486), door=(1212, 475)),
    "seir_warehouses": dict(
        # The grain stores (the harbour's fork): close quarters on one floor,
        # the gallery above out of reach. No story here.
        painting="seir_warehouses", width=1280, height=720, weather="none", fog=0.1, intro="", music="dead_bridge", void_kill_y=690,
        ground=[(0, 597, 1280, 123)],
        ledges=[(134, 552, 66, 12)],
        spawns=[("drowned", 350, 585), ("drowned", 560, 585), ("drowned", 800, 585), ("drowned", 1000, 585),
                ("waiting_townsman", 230, 585), ("waiting_townsman", 680, 585), ("waiting_townsman", 1100, 585),
                ("shade", 500, 200)],
        props=[("sack", 460, 597), ("barrel", 900, 597)],
        decor=[], npcs=[], ambient="#c8bcb4", lights="auto",
        player=(60, 577), door=(1210, 565)),
    "seir_breakwater": dict(
        # Out along the breakwater (the harbour's fork): three spans over the
        # red sea and the wind. A fall between them is a fall into the sea.
        painting="seir_breakwater", width=1280, height=720, weather="rain", fog=0.15, intro="", music="dead_bridge", void_kill_y=690,
        ground=[(0, 432, 431, 123), (462, 432, 358, 123), (848, 432, 432, 123)],
        spawns=[("sea_wraith", 300, 300), ("sea_wraith", 600, 250), ("sea_wraith", 900, 300), ("sea_wraith", 1100, 250),
                ("drowned", 300, 420), ("drowned", 950, 420)],
        props=[("barrel", 140, 432)],
        decor=[], npcs=[], ambient="#c4b8c4", lights="auto",
        player=(30, 412), door=(1228, 400)),
    "seir_lighthouse_stair": dict(
        # Up the lighthouse: four floors joined by stairs. The painting's third
        # stair starts right over the head of the second, where nobody could
        # stand, so the way to the upper floor is a run of cornices on the
        # wall instead; the first stair comes up through a gap in the floor above.
        painting="seir_lighthouse_stair", width=1280, height=720, weather="none", fog=0.1, intro="", music="graveyard", void_kill_y=700,
        ground=[(32, 651, 660, 69), (680, 680, 560, 40)],
        ledges=[(693, 483, 90, 14), (850, 483, 248, 14), (213, 380, 407, 14), (680, 292, 542, 14), (33, 206, 445, 14),
                (523, 119, 715, 14)],
        ramps=[(600, 651, 850, 483), (610, 380, 755, 483), (400, 206, 535, 119)],
        stone_steps=True,
        platforms=[(1040, 420, 50, 10), (1120, 357, 50, 10), (630, 235, 50, 10), (585, 180, 50, 10)],
        spawns=[("drowned", 300, 639), ("drowned", 900, 668), ("drowned", 420, 368),
                ("sea_wraith", 300, 500), ("sea_wraith", 1000, 400), ("drowned_bosun", 950, 471)],
        props=[("seir_cache_relief_order", 290, 380), ("crate", 1000, 680)],
        decor=[], npcs=[], ambient="#c8bcb4", lights="auto",
        player=(100, 631), door=(1190, 87)),
    "seir_lighthouse": dict(
        # The lamp room: the Watchman stands between Elian and the fire.
        painting="seir_lighthouse", width=1280, height=720, weather="none", fog=0.08, intro="", music="boss_knight",
        intro_cutscene="watchman_arrival", outro_cutscene="ch2_finale", void_kill_y=690,
        ground=[(0, 495, 1280, 225)],
        ledges=[(854, 442, 85, 12), (954, 396, 124, 12), (1068, 441, 56, 12)],
        spawns=[("watchman", 640, 483)],
        props=[],
        decor=[], npcs=[], ambient="#ccc0b8", lights="auto",
        player=(40, 475), door=(1250, 463)),
    # Chapter VI, the abbey on the Euphrates (docs/CHAPTER6.md), painted by Codex.
    "euphrates_bank": dict(
        # The bank under the storm: the mighty angel stands in the depth with the
        # little book. The ford is shallow water to wade, not a fall.
        painting="euphrates_bank", width=1280, height=720, weather="rain", fog=0.25, intro="", music="road",
        intro_cutscene="little_book", void_kill_y=700,
        ground=[(0, 522, 745, 198), (745, 576, 262, 144), (1005, 526, 275, 194)],
        liquids=[["water", 745, 540, 262, 36]],
        spawns=[("river_wraith", 820, 420), ("river_wraith", 930, 380), ("horseman", 1120, 514)],
        props=[("pot", 480, 522)],
        decor=[], npcs=[], ambient="#b8bccc", lights="auto",
        player=(30, 502), door=(1238, 494)),
    "euphrates_town": dict(
        # The feast in the street; the two witnesses lie in the middle of it.
        painting="euphrates_town", width=1280, height=720, weather="none", fog=0.15, intro="", music="village_night",
        intro_cutscene="witnesses_in_the_street", void_kill_y=700,
        ground=[(0, 503, 1280, 217)],
        spawns=[("flagellant", 300, 491), ("flagellant", 860, 491), ("flagellant", 1000, 491), ("river_wraith", 700, 380)],
        props=[("barrel", 1010, 503)],
        decor=[], npcs=[("euphrates_reveller", 420, 503), ("witness_left", 610, 503), ("witness_right", 690, 503),
                        ("malchus_far", 1100, 503)], ambient="#c8bcb4", lights="auto",
        player=(30, 483), door=(1185, 471)),
    "euphrates_gate": dict(
        # Inside the abbey gate: the porter's balcony up the stair, and the
        # chain-keepers' roll behind the bricked door on it.
        painting="euphrates_gate", width=1280, height=720, weather="none", fog=0.12, intro="", music="church", void_kill_y=700,
        ground=[(0, 600, 1280, 120)],
        ledges=[(825, 358, 400, 14)],
        ramps=[(500, 600, 828, 358)],
        stone_steps=True,
        spawns=[("flagellant", 300, 588), ("flagellant", 1000, 588), ("censer_monk", 950, 346), ("censer_monk", 640, 588)],
        props=[("euphrates_cache_chain_roll", 1120, 358)],
        decor=[], npcs=[], ambient="#c8bcb0", lights="auto",
        player=(40, 580), door=(1170, 568)),
    "euphrates_cloister": dict(
        # The cloister round its garth (the gate's fork). No story here.
        painting="euphrates_cloister", width=1280, height=720, weather="none", fog=0.15, intro="", music="church", void_kill_y=700,
        ground=[(0, 565, 1280, 155)],
        spawns=[("flagellant", 330, 553), ("flagellant", 650, 553), ("flagellant", 900, 553), ("censer_monk", 1050, 553),
                ("horseman", 520, 553)],
        props=[("pot", 980, 565)],
        decor=[], npcs=[], ambient="#c0bccc", lights="auto",
        player=(90, 545), door=(1205, 533)),
    "euphrates_scriptorium": dict(
        # The scriptorium (the gate's fork): walkways along the shelves, a
        # copyist chained to the ring by the desk. No story here.
        painting="euphrates_scriptorium", width=1280, height=720, weather="none", fog=0.08, intro="", music="church", void_kill_y=700,
        ground=[(0, 637, 1280, 83)],
        ledges=[(45, 438, 475, 14), (565, 333, 670, 14)],
        ramps=[(470, 438, 570, 333)],
        stone_steps=True,
        platforms=[(600, 575, 50, 10), (530, 508, 50, 10)],
        spawns=[("censer_monk", 250, 426), ("censer_monk", 800, 321), ("censer_monk", 1000, 625), ("flagellant", 400, 625),
                ("chained_penitent", 740, 625)],
        props=[("chain", 718, 637)],
        decor=[], npcs=[], ambient="#ccbcac", lights="auto",
        player=(85, 617), door=(1200, 605)),
    "euphrates_refectory": dict(
        # The refectory: the table laid for forty, the bread untouched; Saul by
        # the oven, which is the rest point.
        painting="euphrates_refectory", width=1280, height=720, weather="none", fog=0.1, intro="", music="church",
        intro_cutscene="refectory_arrival", void_kill_y=700,
        ground=[(0, 568, 1280, 152)],
        ledges=[(290, 505, 650, 12), (940, 503, 190, 12)],
        spawns=[("flagellant", 200, 556), ("flagellant", 600, 493), ("censer_monk", 140, 556)],
        props=[],
        decor=[], npcs=[("saul", 900, 568)], ambient="#ccbcac", lights="auto",
        player=(90, 548), door=(1215, 536)),
    "euphrates_bell_tower": dict(
        # The bell tower: two paintings, one over the other — the room is
        # tools/rooms/composed_rooms.json (live); this is its look and its lower picture.
        painting="euphrates_bell_tower", width=1280, height=720, weather="none", fog=0.1, intro="", music="church", void_kill_y=700,
        ground=[(0, 637, 1280, 83)],
        spawns=[], props=[],
        decor=[], npcs=[], ambient="#c4bcb4", lights="auto",
        player=(40, 617), door=(1200, 605)),
    "euphrates_altar_court": dict(
        # The golden altar with four horns; the voice speaks from them, and the
        # lion-headed horse wakes beside it.
        painting="euphrates_altar_court", width=1280, height=720, weather="none", fog=0.15, intro="", music="church",
        intro_cutscene="voice_from_the_horns", void_kill_y=700,
        ground=[(0, 535, 1280, 185)],
        ledges=[(380, 500, 515, 12), (455, 458, 365, 12)],
        spawns=[("lion_horse", 980, 523), ("flagellant", 250, 523), ("flagellant", 1100, 523), ("censer_monk", 560, 446),
                ("censer_monk", 760, 446), ("chained_penitent", 300, 523), ("chained_penitent", 1000, 523)],
        props=[("chain", 287, 535), ("chain", 985, 535)],
        decor=[], npcs=[], ambient="#c4bccc", lights="auto",
        player=(30, 515), door=(1240, 503)),
    "euphrates_crypt_of_chains": dict(
        # The crypt of chains (the altar's fork): rings at every height. No story here.
        painting="euphrates_crypt_of_chains", width=1280, height=720, weather="none", fog=0.12, intro="", music="graveyard", void_kill_y=700,
        ground=[(0, 565, 1280, 155)],
        ledges=[(595, 432, 130, 12), (880, 290, 360, 14)],
        ramps=[(725, 432, 872, 565), (725, 432, 885, 290)],
        stone_steps=True,
        spawns=[("chained_penitent", 255, 553), ("chained_penitent", 490, 553), ("chained_penitent", 950, 553),
                ("chained_penitent", 1100, 553), ("chained_penitent", 400, 553), ("fettered_angel", 1000, 220),
                ("fettered_angel", 620, 330), ("censer_monk", 1100, 278)],
        props=[("chain", 235, 565), ("chain", 510, 565), ("chain", 930, 565), ("chain", 1085, 565), ("chain", 380, 565)],
        decor=[], npcs=[], ambient="#bcbcc8", lights="auto",
        player=(75, 545), door=(1205, 533)),
    "euphrates_cistern": dict(
        # The cistern (the altar's fork): two walkways and three plinths over deep water.
        painting="euphrates_cistern", width=1280, height=720, weather="none", fog=0.2, intro="", music="dead_bridge", void_kill_y=715,
        ground=[(0, 522, 390, 198), (890, 522, 390, 198), (390, 710, 500, 10)],
        ledges=[(440, 500, 65, 12), (607, 500, 68, 12), (778, 500, 62, 12)],
        liquids=[["water", 390, 580, 500, 130]],
        spawns=[("river_wraith", 500, 400), ("river_wraith", 700, 380), ("river_wraith", 300, 350), ("river_wraith", 1000, 380),
                ("flagellant", 200, 510), ("flagellant", 1050, 510)],
        props=[],
        decor=[], npcs=[], ambient="#b8c0c8", lights="auto",
        player=(30, 502), door=(1210, 490)),
    "euphrates_river_stair": dict(
        # Down into the dry riverbed: the shrine on the middle landing is the
        # rest point; the novice's letter is in the bricked niche beside it.
        painting="euphrates_river_stair", width=1280, height=720, weather="none", fog=0.15, intro="", music="dead_bridge", void_kill_y=700,
        ground=[(0, 187, 255, 533), (255, 600, 1025, 120)],
        ledges=[(555, 370, 160, 14)],
        ramps=[(255, 187, 560, 370), (715, 370, 1030, 600)],
        stone_steps=True,
        spawns=[("horseman", 700, 588), ("horseman", 1000, 588), ("lion_horse", 450, 588), ("river_wraith", 800, 250),
                ("river_wraith", 1050, 300), ("chained_penitent", 650, 358)],
        props=[("chain", 690, 370), ("euphrates_cache_novice_envy", 745, 370)],
        decor=[], npcs=[], ambient="#bcb8c0", lights="auto",
        player=(30, 167), door=(1215, 568)),
    "euphrates_bound": dict(
        # Under the river: four pillars banded with gold, a ring at each foot.
        # The Four Bound stands at the first and swaps as each falls.
        painting="euphrates_bound", width=1280, height=720, weather="none", fog=0.12, intro="", music="boss_ophanim",
        intro_cutscene="the_four_bound", outro_cutscene="ch6_finale", void_kill_y=700,
        ground=[(0, 600, 1280, 120)],
        ledges=[(0, 575, 80, 12), (1200, 575, 80, 12)],
        spawns=[("four_bound", 640, 588)],
        props=[],
        decor=[], npcs=[], ambient="#c0c4d0", lights="auto",
        player=(40, 580), door=(1240, 568)),
}
