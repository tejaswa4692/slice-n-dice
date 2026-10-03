extends CharacterBody3D
class_name Player

@onready var walk_controller: PlayerWalkController = $PlayerWalkController
@onready var raycast_circle: Node3D = $RaycastCircle

@onready var playermesh: Node3D = $rig


var canmove: bool = true

func _ready() -> void:
	$Step1.play()

func _physics_process(delta: float) -> void:
	walk_controller.apply_gravity(self, delta)
	if canmove:
		walk_controller.update(self, delta)
	else:
		walk_controller.stop(self, delta)
	move_and_slide()
	walk_controller.lean(playermesh, delta)
	walk_controller.update_animation(delta)
