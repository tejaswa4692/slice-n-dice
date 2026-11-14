extends Node3D

@export var hurtbox_array: Array[Area3D] = []
var entities_hitable = []

func _ready() -> void:
	for i in hurtbox_array:
		i.connect("body_entered", enemy_entered_hurtbox)
		i.connect("body_exited", enemy_exited_hurtbox)


func enemy_entered_hurtbox(body: Node3D) -> void:
	if body.is_in_group("enemy"):
		entities_hitable.append(body)
		print(body, "entered")

func enemy_exited_hurtbox(body: Node3D) -> void:
	if body.is_in_group("enemy"):
		entities_hitable.erase(body)
		print(body, "left")

func hit() -> void:
	for i in entities_hitable.duplicate():
		i.queue_free()
		entities_hitable.erase(i)
		print("hit")
