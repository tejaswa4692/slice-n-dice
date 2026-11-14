extends Node
class_name PlayerWalkController

@export var playback: AnimationTree
@export var friction: float = 40.0
@export var gravity: float = 20.0
@export var turn_speed: float = 1.8
@export var lean_angle_deg: float = 25.0
@export var lean_smoothing: float = 6.0
@export var run_speed: float = 10.0
@export var acceleration: float = 40.0
@export var flip_exit_time: float = 0.1
@export var jump_velocity: float = 1.0
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.35

@export var attack_turn_scale: float = 0.4

@onready var left_hik: CCDIK3D = $"../rig/Skeleton3D/LeftHIK"
@onready var right_hik: CCDIK3D = $"../rig/Skeleton3D/RightHIK"
@onready var step_left: AudioStreamPlayer3D = $"../Step1"
@onready var step_right: AudioStreamPlayer3D = $"../Step2"
@onready var motion_module: MotionModule = $MotionModule
@onready var state_machine: AnimationNodeStateMachinePlayback = playback.get("parameters/playback")

enum State {Walk, Run, Idle, Flip, Attack, Dash}
var state: State = State.Idle
var flip_seen: bool = false
var dash_timer: float = 0.0
var steer: float = 0.0

func ground_state() -> State:
	if not Input.is_action_pressed("up"):
		return State.Idle
	if Input.is_action_pressed("run"):
		return State.Run
	return State.Walk

func update(body: CharacterBody3D, delta: float) -> void:
	var locked: bool = state == State.Dash or state == State.Flip
	var attacking: bool = state == State.Attack
	var turn: float = 0.0 if locked else Input.get_axis("left", "right")
	if attacking:
		turn *= attack_turn_scale
	if not locked and not attacking:
		state = ground_state()
		if state != State.Idle and Input.is_action_just_pressed("dash"):
			state = State.Dash
			dash_timer = dash_duration
			state_machine.travel(&"Dash")
		elif state == State.Run and Input.is_action_just_pressed("backflip"):
			state = State.Flip
			flip_seen = false
			body.velocity.y = jump_velocity
			state_machine.travel(&"BackFlip")
	if state == State.Dash:
		dash_timer -= delta
	body.rotate_y(-turn * turn_speed * delta)
	steer = turn if state == State.Run else 0.0
	match state:
		State.Dash:
			motion_module.apply_dash_motion(body)
		State.Run, State.Flip:
			motion_module.apply_run_motion(body, delta)
		State.Walk:
			motion_module.apply_root_motion(body, delta, 2.0)
		State.Attack:
			motion_module.apply_root_motion(body, delta, 2.0)
		_:
			motion_module.decelerate(body, delta)

func stop(body: CharacterBody3D, delta: float) -> void:
	state = State.Idle
	steer = 0.0
	motion_module.decelerate(body, delta)

func apply_gravity(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= gravity * delta

func lean(mesh: Node3D, delta: float) -> void:
	if state == State.Flip:
		mesh.rotation.x = lerp_angle(mesh.rotation.x, 0.0, lean_smoothing * delta)
		left_hik.influence = 0.0
		right_hik.influence = 0.0
		return
	var max_lean: float = deg_to_rad(lean_angle_deg)
	mesh.rotation.x = lerp_angle(mesh.rotation.x, max_lean * steer, lean_smoothing * delta)
	var amount: float = clampf(absf(mesh.rotation.x) / max_lean, 0.0, 1.0)
	if mesh.rotation.x < 0:
		left_hik.influence = amount
		right_hik.influence = 0.0
	else:
		right_hik.influence = amount
		left_hik.influence = 0.0

func update_animation(_delta: float) -> void:
	if playback == null or state == State.Attack:
		return
	if state == State.Dash:
		if dash_timer > 0.0:
			return
		state = ground_state()
	if state == State.Flip:
		if state_machine.get_current_node() == &"BackFlip":
			flip_seen = true
			if state_machine.get_current_length() - state_machine.get_current_play_position() >= flip_exit_time:
				return
		elif not flip_seen:
			return
		flip_seen = false
		state = ground_state()
	state_machine.travel(StringName(State.keys()[state]))

func footstep(foot: int, gait: String) -> void:
	if String(state_machine.get_current_node()) != gait:
		return
	var player: AudioStreamPlayer3D = step_left if foot == 0 else step_right
	player.play()
