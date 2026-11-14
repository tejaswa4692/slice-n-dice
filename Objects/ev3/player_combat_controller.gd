extends Node

@export var animation_tree: AnimationTree
@export var combo: Array[StringName] = [&"Swing", &"Swing2", &"Swing3"]
@export var buffer_time: float = 0.3
@export var chain_start: float = 0.45
@export var cancel_start: float = 0.35
@export var end_at: float = 0.9

@onready var drone_scene = preload("res://Objects/Ammunation/drone.tscn")
@export var drone_spawn_loc: Marker3D 

@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var walk_controller: PlayerWalkController = get_parent().get_node("PlayerWalkController")


var combo_index: int = -1
var buffer_timer: float = 0.0

func progress() -> float:
	var length: float = playback.get_current_length()
	if length <= 0.0:
		return 1.0
	return playback.get_current_play_position() / length

func start_swing(index: int) -> void:
	combo_index = index
	buffer_timer = 0.0
	walk_controller.state = PlayerWalkController.State.Attack
	playback.travel(combo[index])

func end_attack() -> void:
	combo_index = -1
	walk_controller.state = walk_controller.ground_state()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		buffer_timer = buffer_time
	elif walk_controller.state == PlayerWalkController.State.Attack and progress() >= cancel_start:
		if event.is_action_pressed("dash") or event.is_action_pressed("backflip"):
			end_attack()

func _physics_process(delta: float) -> void:
	buffer_timer = maxf(buffer_timer - delta, 0.0)
	if walk_controller.state != PlayerWalkController.State.Attack:
		combo_index = -1
		var blocked: bool = walk_controller.state == PlayerWalkController.State.Dash or walk_controller.state == PlayerWalkController.State.Flip
		if buffer_timer > 0.0 and not blocked:
			start_swing(0)
		return
	if playback.get_current_node() != combo[combo_index]:
		return
	var current: float = progress()
	if buffer_timer > 0.0 and current >= chain_start and combo_index < combo.size() - 1:
		start_swing(combo_index + 1)
	elif current >= end_at:
		end_attack()

func spawn_drone() -> void:
	var drone = drone_scene.instantiate()
	get_tree().root.add_child(drone)
	drone.global_position = drone_spawn_loc.global_position
