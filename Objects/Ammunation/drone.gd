extends CharacterBody3D

var enemy_array = []

func _ready() -> void:
	enemy_array = get_tree().get_nodes_in_group("enemy")
	print(enemy_array)
