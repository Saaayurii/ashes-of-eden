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
FLYERS = {"shade", "wraith", "raven", "ophanim"}


def _surfaces(room):
    """Walkable surfaces (x, y, w) and the pairs joined by walking (ramps)."""
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


def _can_jump(a, b):
    ax, ay, aw = a
    bx, by, bw = b
    gap = max(0.0, bx - (ax + aw), ax - (bx + bw))
    rise = ay - by  # positive: b is higher
    if rise > 0:
        return rise <= JUMP_UP and gap <= JUMP_ACROSS - rise * 0.9
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
    for npc_id, x, y in room.get("npcs", []):
        try:
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
                (960, 625, 70, 30), (1050, 560, 230, 30), (1070, 635, 210, 40),
                (960, 655, 320, 65)],
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
        spawns=[("possessed_villager", 470, 515), ("possessed_villager", 760, 548), ("possessed_villager", 1150, 548),
                ("possessed_villager", 1050, 248), ("possessed_villager", 330, 333),
                ("shade", 500, 300), ("shade", 900, 200), ("raven", 700, 120)],
        props=[("pot", 280, 195), ("rubble", 370, 345), ("barrel_apples", 330, 527), ("box_goods", 365, 527), ("rubble", 500, 527),
               ("pot", 700, 560), ("rubble", 1000, 625), ("chest_wooden", 1200, 635),
               ("secret_wall_village", 1110, 635)],  # Severin's gate log, bricked up in the crypt (docs/CHAPTER1.md)
        decor=[],
        npcs=[("severin", 300, 345)],  # on the side ledge, where the possessed one spawns
        ambient="#c0bccc",
        lights=[(55, 188, "#ffb060", 50, 0.7, 0.3), (530, 212, "#ffb060", 40, 0.6, 0.3), (50, 390, "#ffb060", 36, 0.5, 0.3),
                (175, 402, "#ffb060", 36, 0.5, 0.3), (330, 522, "#ffb060", 36, 0.5, 0.3), (440, 495, "#ffb060", 50, 0.6, 0.3),
                (600, 402, "#ffb060", 36, 0.5, 0.3), (780, 552, "#ffb060", 36, 0.5, 0.3), (850, 640, "#ffb060", 40, 0.5, 0.3),
                (1235, 465, "#ff9a40", 70, 0.9, 0.3), (1190, 638, "#ff9a40", 50, 0.7, 0.3), (1090, 250, "#ffb060", 40, 0.6, 0.3),
                (1238, 245, "#ffb060", 50, 0.7, 0.3), (875, 75, "#c8d4ff", 220, 0.5, 0.0)],
        player=(40, 175), door=(1230, 232), shrine=(1150, 260)),
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
                (804, 385, 257, 14), (1091, 388, 189, 14), (1016, 220, 264, 16), (0, 655, 155, 14),
                (1005, 306, 90, 12)],
        ramps=[(985, 545, 1115, 415)],
        platforms=[(1120, 262, 56, 10)],  # one exit foothold; the bone mound is not a stepping-stone course
        spawns=[("possessed_villager", 400, 506), ("possessed_villager", 650, 506), ("cultist", 880, 533),
                ("possessed_villager", 900, 373), ("zealot", 1180, 376), ("shade", 600, 300), ("raven", 800, 150),
                ("wraith", 300, 600)],
        props=[("pot", 200, 254), ("barrel", 300, 348), ("crate", 700, 518), ("sack", 860, 545),
               ("chest_wooden", 70, 655), ("barrel_apples", 1000, 385)],
        decor=[], npcs=[("nun", 122, 655), ("stranger", 252, 254)], ambient="#c0bccc", lights="auto",
        player=(30, 234), door=(1240, 188), shrine=(1150, 220)),
    "graveyard_arches": dict(
        # Third panel: the old tree takes the right half; the way out is the
        # ruined arch with a candle, reached over the tree's roots.
        painting="graveyard_arches", width=1280, height=720, weather="ash", fog=0.2, intro="", music="graveyard",
        ground=[(0, 690, 1280, 30)],
        ledges=[(0, 220, 265, 14), (223, 257, 112, 12), (373, 275, 61, 12), (393, 350, 280, 14), (6, 389, 70, 12),
                (214, 494, 72, 12), (276, 513, 47, 10), (297, 525, 71, 10), (350, 552, 346, 14), (672, 572, 44, 10),
                (720, 594, 221, 14), (935, 603, 122, 14), (675, 484, 72, 14), (890, 512, 47, 12),
                (1066, 528, 44, 12), (1169, 387, 99, 14), (900, 316, 112, 14), (1050, 292, 110, 14)],
        ramps=[(945, 594, 885, 520)],
        # The root walk at y=552 must lead back to the first upper patrol.
        # Without this stone the descent was one-way and a living enemy above
        # could keep the exit locked forever.
        stone_steps=True,  # broken masonry at the tree, not green floating islands
        platforms=[(1130, 470, 56, 10), (1080, 350, 56, 10)],
        spawns=[("possessed_villager", 500, 338), ("possessed_villager", 450, 540), ("possessed_villager", 600, 540),
                ("cultist", 800, 582), ("zealot", 1220, 375), ("fallen_guard", 950, 304), ("shade", 750, 250),
                ("raven", 600, 120), ("wraith", 250, 620)],
        props=[("chest_iron", 150, 220), ("barrel", 420, 350), ("box_goods", 380, 552), ("sack", 900, 594), ("barrel_apples", 1000, 603),
               ("chest_gold", 40, 389), ("pot", 1230, 387)],
        decor=[], npcs=[], ambient="#bcb8cc", lights="auto",
        player=(30, 200), door=(1120, 260), shrine=(1062, 292)),
    "graveyard_tree": dict(
        # Fourth panel: the tree has grown over everything; a long bridge of
        # roots and stone leads to the chapel, the tower gate is top right.
        painting="graveyard_tree", width=1280, height=720, weather="ash", fog=0.25, intro="", music="graveyard",
        ground=[(0, 690, 1280, 30)],
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
                ("shade", 700, 250), ("wraith", 950, 600), ("raven", 500, 150)],
        props=[("pot", 110, 289), ("barrel", 350, 312), ("crate", 500, 419), ("rubble", 720, 419), ("barrel_apples", 1000, 365),
               ("chest_wooden", 760, 635), ("pot", 250, 563), ("crate", 1250, 445)],
        decor=[], npcs=[("mara", 955, 380)], ambient="#bcb8cc", lights="auto",
        player=(60, 245), door=(1180, 209), shrine=(1120, 241)),
    "swamp_moon": dict(
        # Fifth panel: the graveyard sinks into a swamp; rotten piers over
        # black water, the lantern post on the far pier marks the way on.
        painting="swamp_moon", width=1280, height=720, weather="fireflies", fog=0.3, intro="", music="graveyard",
        ground=[(0, 690, 1280, 30)],  # the swamp bed
        ledges=[(10, 201, 80, 12), (130, 231, 57, 10), (172, 252, 57, 10), (153, 264, 144, 12), (17, 351, 157, 14),
                (425, 338, 236, 14), (216, 456, 48, 10), (286, 474, 216, 14), (656, 415, 226, 14), (626, 474, 61, 10),
                (928, 474, 51, 10), (638, 535, 104, 12), (914, 550, 53, 10), (1165, 554, 78, 12), (512, 568, 144, 12),
                (594, 599, 75, 10), (376, 603, 45, 10), (1077, 413, 194, 14)],
        ramps=[],
        platforms=[(1120, 478, 56, 10), (1230, 625, 56, 10)],  # 478: the pier is a sure double jump, not a lucky one
        spawns=[("possessed_villager", 520, 326), ("cultist", 750, 403), ("possessed_villager", 400, 462),
                ("zealot", 1150, 401), ("fallen_guard", 580, 556), ("shade", 800, 300), ("wraith", 300, 600),
                ("raven", 900, 150), ("shade", 1000, 250)],
        props=[("barrel", 250, 264), ("pot", 600, 338), ("box_goods", 700, 415), ("sack", 350, 474),
               ("chest_wooden", 1200, 554), ("barrel_apples", 100, 351), ("pot", 680, 535)],
        decor=[], npcs=[("villager", 470, 474)], ambient="#b4b8cc", lights="auto",
        player=(40, 181), door=(1240, 381), shrine=(1100, 413)),
    "swamp_red": dict(
        # Sixth panel: the moon turns red over the swamp. Stepping stones and
        # pier stumps across the water; the fenced bank top right leads on.
        painting="swamp_red", width=1280, height=720, weather="embers", fog=0.3, intro="", music="dead_bridge",
        ground=[(0, 690, 1280, 30)],
        ledges=[(38, 347, 274, 14), (323, 404, 48, 10), (470, 395, 49, 10), (571, 405, 91, 12), (522, 434, 167, 12),
                (704, 329, 53, 10), (39, 505, 122, 12), (187, 499, 200, 12), (943, 412, 83, 12), (1047, 425, 150, 14),
                (1121, 255, 159, 14)],
        ramps=[],
        # The middle return step is a rotting timber pier rooted in the water
        # on this painting; only the far-right climb needs separate pieces.
        platforms=[(860, 452, 60, 10), (1220, 370, 56, 10), (1150, 310, 56, 10)],
        painted_platforms=[(860, 452, 60, 10)],
        spawns=[("possessed_villager", 200, 335), ("cultist", 600, 422), ("possessed_villager", 300, 487),
                ("zealot", 1120, 413), ("fallen_guard", 980, 400), ("wraith", 600, 300), ("shade", 850, 250),
                ("raven", 400, 150), ("elite_possessed", 1180, 243)],
        props=[("barrel", 120, 347), ("crate", 280, 347), ("pot", 640, 405), ("sack", 250, 499), ("barrel_apples", 1100, 425),
               ("chest_cursed", 80, 505), ("pot", 1160, 255)],
        decor=[], npcs=[], ambient="#c8b0b4", lights="auto",
        player=(60, 327), door=(1240, 223), shrine=(1140, 255)),  # the bank starts at x 38
    "swamp_crypt": dict(
        # Seventh panel: the swamp ends at a crypt door lit by candles; the
        # stairs beside it go down into the catacombs.
        painting="swamp_crypt", width=1280, height=720, weather="embers", fog=0.3, intro="", music="dead_bridge",
        ground=[(0, 690, 1280, 30), (930, 560, 130, 20)],
        ledges=[(28, 319, 177, 14), (0, 261, 60, 10), (218, 258, 64, 10), (15, 414, 203, 14), (276, 337, 67, 10),
                (285, 375, 56, 10), (301, 404, 47, 10), (394, 397, 94, 12), (387, 432, 86, 12), (451, 312, 54, 10),
                (533, 321, 44, 10), (506, 256, 196, 14), (649, 312, 78, 12), (780, 311, 74, 12), (919, 314, 102, 12),
                (1116, 311, 149, 14), (1105, 240, 75, 10), (1097, 175, 148, 14), (533, 451, 184, 14), (738, 459, 53, 10), (829, 472, 58, 10),
                (591, 386, 45, 10), (371, 540, 162, 12), (429, 583, 46, 10), (227, 586, 90, 12), (114, 606, 49, 10),
                (1097, 485, 76, 12), (1220, 488, 60, 12), (901, 548, 58, 10), (1033, 625, 81, 10),
                (783, 655, 86, 12)],
        ramps=[(1060, 560, 1130, 630)],
        platforms=[],  # painted masonry and roots already carry the whole route
        spawns=[("possessed_villager", 100, 402), ("cult_caller", 600, 244), ("possessed_villager", 600, 439),
                ("fallen_guard", 1200, 299), ("preacher_acolyte", 960, 302), ("zealot", 450, 528), ("wraith", 700, 400),
                ("shade", 300, 200), ("raven", 850, 120), ("elite_possessed", 690, 300)],
        props=[("barrel", 150, 319), ("chest_iron", 200, 414), ("box_goods", 560, 256), ("rubble", 680, 451), ("barrel_apples", 1000, 314),
               ("chest_wooden", 1130, 485), ("pot", 780, 655), ("box_goods", 1200, 311),
               ("secret_wall_swamp", 630, 451)],  # letters behind the tower masonry, not the red root mass
        decor=[], npcs=[], ambient="#c8b0b4", lights="auto",
        player=(40, 299), door=(995, 528), shrine=(925, 548)),
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
                ("possessed_villager", 300, 628), ("shade", 700, 300), ("wraith", 400, 500)],
        props=[("pot", 150, 157), ("barrel", 420, 260), ("crate", 700, 403), ("sack", 1200, 440), ("chest_gold", 1150, 191),
               ("barrel_apples", 250, 413), ("pot", 600, 556), ("crate", 900, 604), ("sack", 80, 582)],
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(70, 137), door=(1250, 578), shrine=(1205, 610)),
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
                ("wraith", 1000, 380), ("elite_possessed", 1050, 217)],
        props=[("pot", 80, 298), ("barrel", 250, 353), ("box_goods", 600, 424), ("sack", 1050, 521), ("barrel_apples", 500, 228),
               ("chest_wooden", 60, 579), ("pot", 300, 636), ("box_goods", 700, 651), ("sack", 1230, 630),
               ("secret_wall_catacombs", 1020, 695)],  # the bricked-up ossuary niche: names under the lid
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(60, 278), door=(1235, 226), shrine=(1200, 258)),
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
        props=[("pot", 100, 232), ("barrel", 200, 205), ("crate", 600, 242), ("rubble", 950, 312), ("barrel_apples", 150, 442),
               ("chest_gold", 60, 603), ("pot", 300, 664), ("crate", 700, 538), ("rubble", 1000, 583)],
        decor=[], npcs=[], ambient="#c4b4b0", lights="auto",
        player=(60, 126), door=(1250, 627), shrine=(1170, 659)),
    "crypt_skulls": dict(
        # Eleventh panel: the blue crypt over the underground river; the gate
        # with candles on the right wall.
        painting="crypt_skulls", width=1280, height=720, weather="none", fog=0.2, intro="", music="dead_bridge",
        ground=[(0, 700, 1280, 20)],
        ledges=[(43, 218, 65, 10), (37, 254, 196, 14), (418, 256, 53, 10), (458, 268, 59, 10), (508, 275, 56, 10),
                (583, 340, 53, 12), (919, 390, 68, 12), (836, 423, 206, 14), (1043, 404, 80, 12), (807, 449, 48, 10),
                (639, 457, 169, 14), (583, 472, 60, 10), (112, 428, 52, 10), (4, 465, 103, 12), (93, 475, 132, 12),
                (181, 464, 45, 10), (362, 569, 45, 10), (381, 581, 129, 12), (1160, 550, 120, 12), (1146, 603, 112, 12),
                (1004, 615, 104, 12), (886, 626, 79, 12), (929, 643, 70, 10), (853, 678, 45, 10), (687, 691, 107, 10),
                (593, 627, 62, 10), (675, 628, 45, 10), (282, 661, 63, 10)],
        ramps=[(190, 490, 320, 522)],
        platforms=[(300, 300, 56, 10)],
        spawns=[("possessed_villager", 500, 263), ("fallen_guard", 700, 445), ("zealot", 950, 411),
                ("cultist", 1080, 392), ("possessed_villager", 150, 463), ("possessed_villager", 450, 569),
                ("preacher_acolyte", 950, 631), ("wraith", 500, 400), ("shade", 800, 250), ("shade", 1100, 300)],
        props=[("chest_iron", 120, 254), ("barrel", 200, 254), ("box_goods", 600, 340), ("sack", 750, 457), ("barrel_apples", 1000, 423),
               ("chest_cursed", 300, 661), ("pot", 400, 581), ("box_goods", 1050, 615), ("sack", 1180, 603)],
        decor=[], npcs=[], ambient="#b8bccc", lights="auto",
        player=(60, 234), door=(1225, 518), shrine=(1175, 550)),
    "crypt_lava": dict(
        # Twelfth panel, the Knight of Ash: the crypt cracks open over lava. He
        # waits on the long gallery in the middle; the way on is the dark arch
        # top right. (The lava at the bottom is drawn only: a floor catches you.)
        painting="crypt_lava", width=1280, height=720, weather="embers", fog=0.2, intro="", music="boss_knight",
        intro_cutscene="knight_arrival",
        ground=[(0, 700, 1280, 20)],
        ledges=[(28, 173, 170, 14), (103, 222, 100, 10), (188, 235, 96, 10), (266, 252, 47, 10), (278, 261, 262, 14),
                (613, 259, 46, 10), (672, 200, 301, 16), (821, 180, 61, 10), (956, 180, 96, 12), (958, 226, 148, 12),
                (1097, 208, 183, 14), (581, 362, 93, 12), (424, 401, 98, 12), (513, 428, 54, 10), (584, 458, 208, 14),
                (796, 474, 177, 14), (846, 440, 63, 10), (992, 450, 173, 14), (632, 557, 97, 12), (1057, 564, 109, 12),
                (1155, 607, 60, 10), (116, 581, 47, 10), (227, 615, 59, 10), (306, 666, 131, 12), (472, 670, 111, 12)],
        ramps=[(240, 618, 330, 665)],
        platforms=[],  # use the painted gallery and stair, not blocks over lava
        hazards=[(590, 694, 560, 26)],  # the lava pool under the gallery
        spawns=[("knight_of_ash", 820, 188)],
        props=[("barrel", 120, 173), ("crate", 400, 261), ("pot", 700, 458), ("sack", 900, 474), ("barrel_apples", 1100, 450),
               ("chest_gold", 500, 670)],
        decor=[], npcs=[], ambient="#d0b4b0", lights="auto",
        player=(50, 153), door=(1240, 176), shrine=(1140, 208)),
    "hell_gate": dict(
        # Thirteenth panel, the Ophanim: the locked gate of the pit, a grand
        # stair up to it over a bridge of bone. The gate is the exit.
        painting="hell_gate", width=1280, height=720, weather="embers", fog=0.15, intro="ch1_ophanim", music="boss_ophanim",
        intro_cutscene="ophanim_arrival", outro_cutscene="ch1_finale",
        ground=[(0, 700, 1280, 20), (900, 372, 220, 30)],
        ledges=[(60, 142, 100, 12), (159, 176, 166, 14), (326, 254, 192, 14), (606, 310, 79, 12), (775, 358, 72, 12),
                (81, 393, 64, 10), (123, 416, 100, 12), (194, 447, 51, 10), (203, 462, 95, 10), (290, 492, 168, 14),
                (530, 484, 44, 10), (605, 482, 255, 16), (1039, 425, 201, 14),
                (453, 568, 151, 12), (563, 614, 46, 10), (648, 600, 45, 10), (79, 643, 60, 10), (125, 671, 80, 10),
                (1080, 633, 70, 10)],  # no phantom ledges below the continuous floor
        ramps=[(790, 494, 900, 384)],
        platforms=[],  # no isolated stones beside the boss gate
        hazards=[(425, 694, 102, 26), (641, 694, 150, 26), (990, 694, 88, 26)],  # the lakes between the rocks
        spawns=[("ophanim", 1000, 250)],
        props=[("pot", 250, 176), ("barrel", 400, 254), ("box_goods", 700, 482), ("rubble", 350, 492),
               ("chest_cursed", 1100, 633)],
        decor=[], npcs=[], ambient="#d8b8b0", lights="auto",
        player=(80, 122), door=(1000, 340), shrine=(930, 372)),
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
        decor=[("arch", 240, 360, "back"), ("arch", 480, 360, "back"), ("arch", 720, 360, "back")],
        spawns=[("blind_preacher", 640, 380)],
        props=[("pot", 60, 380), ("pot", 900, 380)],
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
        platforms=[(0, 290, 180, 14), (780, 290, 180, 14), (250, 338, 56, 10), (654, 338, 56, 10)],
        pillars=[(120, 380), (300, 380), (660, 380), (840, 380)],
        decor=[("arch", 210, 360, "back"), ("arch", 390, 360, "back"), ("arch", 570, 360, "back"), ("arch", 750, 360, "back")],
        spawns=[],
        props=[],
        npcs=[("matthew", 540, 380)],
        ambient="#d8d0d4",
        # indoors the lights multiply into dark stone, so they burn brighter than outside
        lights=[(120, 360, "#ffb060", 90, 1.0, 0.3), (300, 360, "#ffb060", 90, 1.0, 0.3), (660, 360, "#ffb060", 90, 1.0, 0.3),
                (840, 360, "#ffb060", 90, 1.0, 0.3), (480, 340, "#ffc080", 220, 1.3, 0.15),
                (210, 310, "#8fa8ff", 150, 0.8, 0.05), (390, 310, "#8fa8ff", 150, 0.8, 0.05),
                (570, 310, "#8fa8ff", 150, 0.8, 0.05), (750, 310, "#8fa8ff", 150, 0.8, 0.05)],
        bell=(480, 120),
        player=(60, 360), door=(926, 348), shrine=(480, 380)),
}
