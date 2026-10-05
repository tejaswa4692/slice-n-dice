extends Node
class_name PlayerWalkController

@export var animation_tree: AnimationTree
@export var friction: float = 40.0
@export var gravity: float = 20.0
@export var turn_speed: float = 1.8
@export var lean_angle_deg: float = 25.0
@export var lean_smoothing: float = 6.0
@export var walk_multiplyer: float = 1.0
@export var run_speed: float = 10.0
@export var acceleration: float = 40.0
@export var flip_exit_time: float = 0.1
@export var jump_velocity: float = 1
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.35

@onready var left_hand_ground_ik: CCDIK3D = $"../rig/Skeleton3D/LeftHIK"
@onready var right_hand_ground_ik: CCDIK3D = $"../rig/Skeleton3D/RightHIK"
@onready var step_left: AudioStreamPlayer3D = $"../Step1"
@onready var step_right: AudioStreamPlayer3D = $"../Step2"
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")

var moving: bool = false
var running: bool = false
var flipping: bool = false
var flip_seen: bool = false
var dashing: bool = false
var dash_timer: float = 0.0
var steer: float = 0.0


func update(body: CharacterBody3D, delta: float) -> void:
	var turn: float = Input.get_axis("left", "right") if !flipping and !dashing else 0.0
	moving = Input.is_action_pressed("up")
	running = moving and Input.is_action_pressed("run")
	if moving and not dashing and not flipping and Input.is_action_just_pressed("dash"):
		dashing = true
		dash_timer = dash_duration
		playback.travel(&"Dash")
	if dashing:
		dash_timer -= delta
	if running and not flipping and not dashing and Input.is_action_just_pressed("backflip"):
		body.velocity.y = jump_velocity
		flipping = true
		flip_seen = false
		playback.travel(&"BackFlip")
	body.rotate_y(-turn * turn_speed * delta)
	steer = turn if running else 0.0
	if dashing:
		apply_dash_motion(body)
	elif running or flipping:
		apply_run_motion(body, delta)
	elif moving:
		apply_root_motion(body, delta)
	else:
		decelerate(body, delta)

func apply_root_motion(body: CharacterBody3D, delta: float) -> void:
	var motion: Vector3 = body.quaternion * animation_tree.get_root_motion_position() * walk_multiplyer
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

func stop(body: CharacterBody3D, delta: float) -> void:
	moving = false
	running = false
	dashing = false
	steer = 0.0
	decelerate(body, delta)

func apply_gravity(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= gravity * delta

func lean(mesh: Node3D, delta: float) -> void:
	if not flipping:
		var max_lean := deg_to_rad(lean_angle_deg)
		var target_lean := max_lean * steer
		mesh.rotation.x = lerp_angle(mesh.rotation.x, target_lean, lean_smoothing * delta)
		if mesh.rotation.x < 0:
			left_hand_ground_ik.influence = clamp(abs(mesh.rotation.x) / max_lean, 0.0, 1.0)
		else:
			right_hand_ground_ik.influence = clamp(abs(mesh.rotation.x) / max_lean, 0.0, 1.0)
	else:
		mesh.rotation.x = lerp_angle(mesh.rotation.x, 0, lean_smoothing * delta)
		left_hand_ground_ik.influence = 0
		right_hand_ground_ik.influence = 0

func update_animation(delta: float) -> void:
	if animation_tree == null:
		return
	if dashing:
		if dash_timer > 0.0:
			return
		dashing = false
	if flipping:
		if playback.get_current_node() == &"BackFlip":
			flip_seen = true
			if playback.get_current_length() - playback.get_current_play_position() >= flip_exit_time:
				return
		elif not flip_seen:
			return
		flipping = false
		flip_seen = false
	if running:
		playback.travel(&"Run")
	elif moving:
		playback.travel(&"Walk")
	else:
		playback.travel(&"Idle")

func footstep(foot: int, gait: String) -> void:
	if String(playback.get_current_node()) != gait:
		return
	var player: AudioStreamPlayer3D = step_left if foot == 0 else step_right
	player.play()
