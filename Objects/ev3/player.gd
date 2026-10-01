extends CharacterBody3D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var camera_3d: Camera3D = $Camera3D

var speed := 0.5
var acceleration := 2.5
var walk_blend := 0.0

func _process(delta: float) -> void:
	var walking := Input.is_key_pressed(KEY_W)

	if walking:
		velocity.x = move_toward(velocity.x, speed, acceleration * delta)
		walk_blend = lerp(walk_blend, 1.0, delta * 5.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		walk_blend = lerp(walk_blend, 0.0, delta * 5.0)

	animation_tree.set("parameters/Walk/blend_amount", walk_blend)

	move_and_slide()
