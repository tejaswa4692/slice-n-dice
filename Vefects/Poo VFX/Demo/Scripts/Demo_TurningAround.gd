extends Node3D
## Vefects demo - rotates the node continuously (Unity Demo_TurningAround: transform.Rotate(speed * globalSpeed * dt),
## local axes, degrees per second; Unity's left-handed Euler degrees map to Godot as (-x, -y, z)).

@export var rot_speed_x := 0.0
@export var rot_speed_y := 0.0
@export var rot_speed_z := 0.0
@export var global_speed := 1.0


func _process(delta: float) -> void:
	var k := global_speed * delta
	# Unity Rotate(euler) in local space applies z, then x, then y.
	rotate_object_local(Vector3.BACK, deg_to_rad(rot_speed_z * k))
	rotate_object_local(Vector3.RIGHT, deg_to_rad(-rot_speed_x * k))
	rotate_object_local(Vector3.UP, deg_to_rad(-rot_speed_y * k))
