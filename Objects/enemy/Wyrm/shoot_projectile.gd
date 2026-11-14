extends Node

@onready var wyrm: Wyrm = get_parent()
var vomit_projectile = preload("res://Objects/enemy/Wyrm/vomit_projectile.tscn")

func shoot() -> void:
	var vom_inst: Vomit_Projectile = vomit_projectile.instantiate()
	get_tree().current_scene.add_child(vom_inst)
	var randomnum = randi_range(0,  len(wyrm.segments) - 1)
	vom_inst.set_track(wyrm.player, wyrm.segments[randomnum].global_position)
	print(vom_inst.global_position, " ", wyrm.segments[randomnum].global_position)

func shoot_timer_timeout() -> void:
	shoot()
