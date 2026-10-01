extends Node
## Global signal hub. Systems talk through here so they never hold
## references to each other (UI <-> combat <-> story).

signal enemy_died(enemy_id: StringName, position: Vector2)
## A boss asking for reinforcements. The run spawns them so a session can replicate them.
signal enemy_spawn_requested(enemy_id: String, position: Vector2)
signal player_hp_changed(hp: float, max_hp: float)
signal heal_charges_changed(charges: int, max_charges: int)
signal essence_changed(essence: float, needed: float, level: int)
signal level_up(level: int)
signal player_died
## Our own body took a blow: the share of the bar it cost (scripts/ui/screen_fx.gd reddens the frame).
signal player_hurt(fraction: float)
## Our own body is coming to, over this many seconds: the eyes blink open.
signal player_waking(seconds: float)
signal room_started(index: int)
signal room_cleared(index: int)
## Our own body came through the room it just cleared without a wound
## (Player._on_room_cleared); the Run pays for it.
signal player_unscathed(index: int)
## One of the moves in data/techniques was just done by our own body (or,
## for riposte and backstab, landed on an enemy): the practice yard ticks it.
signal technique_performed(technique_id: String)
signal ability_acquired(ability: Dictionary)
## A gift hand turned down (AbilityPicker's Refuse): our own body only.
signal gift_refused
## Our own body cut its hand over a blood altar (Prop "blood_price"): the run
## deals a hand of gifts, and the price is paid only if one is taken.
signal blood_offered(body: Node, price: float)
## The altar's hand settled: [param paid] when a gift was taken under its price.
signal blood_settled(paid: bool)
## A chest opened by our own body (Prop): its prop id, for the playtest log.
signal chest_opened(prop_id: String)
## Gifts taken together woke something none does alone (data/resonances).
signal resonance_awakened(resonance_id: String)
signal item_found(item: Dictionary)
## Our own body rested at a rest point (scripts/rooms/rest_point.gd), in this room.
signal player_rested(room_path: String)
signal alignment_changed(alignment: Dictionary)
signal boss_hp_changed(name_key: String, hp: float, max_hp: float)
signal boss_died
## A blow caught on a timed block (Player._parry).
signal player_parried
## A physical beat strong enough for the room to answer: footsteps stay local,
## while jumps, rolls, swings and hard landings bend fog and nearby foliage.
signal world_impulse(position: Vector2, direction: Vector2, strength: float, kind: StringName)
## First kill of a kind: the bestiary has a new page (Profile keeps the book).
signal bestiary_unlocked(enemy_id: String)
## A record (data/notes) was found in a secret cache; [param first] the first time ever.
signal note_found(note_id: String, first: bool)
signal cutscene_started(cutscene_id: String)
signal cutscene_finished(cutscene_id: String)
signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)
signal choice_made(dialogue_id: String, choice_id: String)
## A deed was done for the first time on this profile (data/achievements).
signal achievement_unlocked(achievement_id: String)
## The "Lighting" setting flipped; every GlowLight and ambient tint re-reads Settings.lighting.
signal lighting_changed
## A saved game was put back into Game and the body (Saves.restore): redraw what reads them.
signal run_restored
