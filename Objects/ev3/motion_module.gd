extends Node
class_name MotionModule

@onready var animation_tree = get_parent().playback
@onready var run_speed = get_parent().run_speed
@onready var acceleration = get_parent().acceleration
@onready var dash_speed = get_parent().dash_speed
@onready var friction = get_parent().friction

func apply_root_motion(body: CharacterBody3D, delta: float, multiplyer: float) -> void:
	var motion: Vector3 = body.quaternion * animation_tree.get_root_motion_position() * multiplyer
	body.velocity.x = motion.x / delta
	body.velocity.z = motion.z / delta

func apply_run_motion(body: CharacterBody3D, delta: float) -> void:
	var target_velocity: Vector3 = body.global_transform.basis * Vector3.RIGHT * run_speed
	body.velocity.x = move_toward(body.velocity.x, target_velocity.x, acceleration * delta)
	body.velocity.z = move_toward(body.velocity.z, target_velocity.z, acceleration * delta)

func apply_dash_motion(body: CharacterBody3D) -> void:
	var target_velocity: Vector3 = body.global_transform.basis * Vector3.RIGHT * dash_speed
	body.velocity.x = target_velocity.x
	body.velocity.z = target_velocity.z

func decelerate(body: CharacterBody3D, delta: float) -> void:
	body.velocity.x = move_toward(body.velocity.x, 0.0, friction * delta)
	body.velocity.z = move_toward(body.velocity.z, 0.0, friction * delta)
