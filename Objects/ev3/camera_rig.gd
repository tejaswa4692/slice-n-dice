extends Node3D

@onready var spring_arm_3d: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Camera3D

@export var sensitivity: float = 0.003

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

var fov_tween: Tween

func _unhandled_input(event: InputEvent) -> void:
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		spring_arm_3d.rotation.x = clamp(spring_arm_3d.rotation.x + event.relative.y * sensitivity, -1.2, 0.3)
	
	
	if event is InputEventKey:
		if Input.is_action_just_pressed("run"):
			tween_fov(90.0, 0.3)
		if Input.is_action_just_released("run"):
			tween_fov(60.0, 0.4)

func tween_fov(target_fov: float, duration: float) -> void:  #Used AI here
	if fov_tween:
		fov_tween.kill()
	fov_tween = create_tween()
	fov_tween.tween_property(camera_3d, "fov", target_fov, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
