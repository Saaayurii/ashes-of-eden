@tool
extends Marker2D
class_name EnemySpawn
## Where an enemy stands when the room starts. Rooms are hand-made scenes;
## an enemy is just a marker with an id from res://data/enemies.

@export var enemy_id: String = "possessed_villager"
## Hangs from a noose over this spot until a player comes near, then the
## rope snaps and it drops (Enemy.start_hanging; "hang" in the enemy's data).
@export var hanging := false
