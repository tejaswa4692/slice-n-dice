extends Node3D
class_name Vomit_Projectile

@export var speed: float = 50
@export var lifetime: float = 6.0
@export var lead_time: float = 0.5

var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	set_process(false)

func set_track(player: CharacterBody3D, from: Vector3) -> void:
	global_position = from
	var flat_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var aim_point := player.global_position + flat_velocity * lead_time
	direction = (aim_point - from).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		look_at(global_position + direction, Vector3.UP)
	set_process(true)



func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	global_position += direction * speed * delta
