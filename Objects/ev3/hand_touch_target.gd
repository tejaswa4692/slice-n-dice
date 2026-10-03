extends Node3D

@export var detector: Node3D
@export var left_target: Node3D
@export var right_target: Node3D
@export var blend_speed: float = 8.0
@export var follow_speed: float = 20.0

var left_hik: CCDIK3D
var right_hik: CCDIK3D

func _ready() -> void:
	left_hik = detector.left_hik
	right_hik = detector.right_hik

func _physics_process(delta: float) -> void:
	var point: Vector3 = detector.get_closest()
	var hit: bool = point != Vector3.ZERO
	var local_x: float = detector.to_local(point).x
	update_hand(right_hik, right_target, point, hit and local_x > 0.0, delta)
	update_hand(left_hik, left_target, point, hit and local_x < 0.0, delta)

func update_hand(hik: CCDIK3D, target: Node3D, point: Vector3, active: bool, delta: float) -> void:
	var goal: float = 1.0 if active else 0.0
	hik.influence = move_toward(hik.influence, goal, blend_speed * delta)
	if active:
		target.global_position = target.global_position.lerp(point, clampf(follow_speed * delta, 0.0, 1.0))
