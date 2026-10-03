extends Node
class_name PlayerWalkController

@export var animation_tree: AnimationTree
@export var blend_param: StringName = &"parameters/Blend3/blend_amount"
@export var friction: float = 40.0
@export var gravity: float = 20.0
@export var blend_smoothing: float = 8.0
@export var turn_speed: float = 1.8
@export var lean_angle_deg: float = 25.0
@export var lean_smoothing: float = 6.0

@onready var left_hand_ground_ik: CCDIK3D = $"../rig/Skeleton3D/LeftHIK"
@onready var right_hand_ground_ik: CCDIK3D = $"../rig/Skeleton3D/RightHIK"
@onready var step_left: AudioStreamPlayer3D = $"../Step1"
@onready var step_right: AudioStreamPlayer3D = $"../Step2"

@export var walk_multiplyer: float = 1.0
@export var run_speed: float = 10.0
@export var acceleration: float = 40.0


var blend: float = -1.0
var moving: bool = false
var running: bool = false
var steer: float = 0.0

func update(body: CharacterBody3D, delta: float) -> void:
	var turn: float = Input.get_axis("left", "right")
	moving = Input.is_action_pressed("up")
	running = moving and Input.is_action_pressed("run")
	body.rotate_y(-turn * turn_speed * delta)
	steer = turn if running else 0.0
	if running:
		apply_run_motion(body, delta)
	else:
		apply_root_motion(body, delta)

func apply_root_motion(body: CharacterBody3D, delta: float) -> void:
	var motion: Vector3 = body.quaternion * animation_tree.get_root_motion_position() * walk_multiplyer
	body.velocity.x = motion.x / delta
	body.velocity.z = motion.z / delta

func apply_run_motion(body: CharacterBody3D, delta: float) -> void:
	var target_velocity: Vector3 = body.global_transform.basis * Vector3.RIGHT * run_speed
	body.velocity.x = move_toward(body.velocity.x, target_velocity.x, acceleration * delta)
	body.velocity.z = move_toward(body.velocity.z, target_velocity.z, acceleration * delta)


func stop(body: CharacterBody3D, delta: float) -> void:
	moving = false
	running = false
	steer = 0.0
	body.velocity.x = move_toward(body.velocity.x, 0.0, friction * delta)
	body.velocity.z = move_toward(body.velocity.z, 0.0, friction * delta)

func apply_gravity(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= gravity * delta

func lean(mesh: Node3D, delta: float) -> void:
	var max_lean := deg_to_rad(lean_angle_deg)
	var target_lean := max_lean * steer
	mesh.rotation.x = lerp_angle(mesh.rotation.x, target_lean, lean_smoothing * delta)
	if mesh.rotation.x < 0:
		left_hand_ground_ik.influence = clamp(abs(mesh.rotation.x) / max_lean, 0.0, 1.0)
	else:
		right_hand_ground_ik.influence = clamp(abs(mesh.rotation.x) / max_lean, 0.0, 1.0)

func update_animation(delta: float) -> void:
	if animation_tree == null:
		return
	var target_blend: float = -1.0
	if running:
		target_blend = 1.0
	elif moving:
		target_blend = 0.0
	blend = lerp(blend, target_blend, delta * blend_smoothing)
	animation_tree.set(blend_param, blend)

func footstep(foot: int, gait: float) -> void:
	if absf(blend - gait) > 0.5:
		return
	var player: AudioStreamPlayer3D = step_left if foot == 0 else step_right
	player.play()
