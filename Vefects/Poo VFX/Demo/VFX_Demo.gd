extends Node3D
## Vefects Poo VFX - demo: browse every effect of the pack.
## Left / Right (or A / D): previous / next effect.  Space (or R): replay.
## Right mouse drag: orbit.  Mouse wheel: zoom.

## [scene, camera target, camera distance]
const EFFECTS := [
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Drips_01.tscn", Vector3(0.01, 0.3, 0), 2.4],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Drips_Puddle_01.tscn", Vector3(0.39, 0.3, 0.2), 5.7],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Goo_01.tscn", Vector3(0, 1, 0), 5.8],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Goo_Stream_01.tscn", Vector3(0, 1, 0), 5.8],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splash_01.tscn", Vector3(0, 0.3, 0), 3.7],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splash_01_Col.tscn", Vector3(0, 0.3, 0), 3.9],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splash_01_Col_Loop.tscn", Vector3(-0.11, 0.3, -0.26), 4.9],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splash_01_Loop.tscn", Vector3(0, 0.3, 0), 3.7],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_01_Floor.tscn", Vector3(0, 0.3, 0), 2.7],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_01_Floor_Bunch_Rand.tscn", Vector3(0, 0.3, 0), 4.8],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_01_Floor_Rot.tscn", Vector3(0, 0.3, 0), 2.7],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_01_Floor_Rot_GS_Pure.tscn", Vector3(0, 0.3, 0), 4.4],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_01_Floor_Rot_GS_Pure_02.tscn", Vector3(0, 0.3, 0), 4.4],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_02_Floor_Rot.tscn", Vector3(0, 0.3, 0), 4.4],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_Directional_01_Floor.tscn", Vector3(0, 0.3, 0), 3.4],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_Directional_01_Floor_Bunch.tscn", Vector3(0, 0.61, 0), 8.5],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_Directional_01_Floor_GS_Pure.tscn", Vector3(0, 0.62, 0), 8.5],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_Directional_01_Floor_GS_Pure_02.tscn", Vector3(0, 0.62, 0), 8.5],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poo_Splat_Directional_01_Floor_Rot.tscn", Vector3(0, 0.62, 0), 8.5],
	["res://Vefects/Poo VFX/VFX/Particles/VFX_Poorojectile_01_Demo.tscn", Vector3(0.02, 1.07, -3.13), 6],
]

var _index := 0
var _current: Node
var _yaw := 0.6
var _pitch := -0.3
var _distance := 8.0
var _target := Vector3(0.0, 1.0, 0.0)

@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $UI/Info
@onready var _vexa: Node3D = get_node_or_null("SM_Vefects_Vexa_Unity_01")


func _ready() -> void:
	var start := 0
	for i in EFFECTS.size():
		if String(EFFECTS[i][0]).ends_with("VFX_Fire_Hydrant_01_Prewarm_Loop.tscn"):
			start = i
	_show(start)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_D:
				_show(_index + 1)
			KEY_LEFT, KEY_A:
				_show(_index - 1)
			KEY_SPACE, KEY_R:
				_show(_index)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 0.6)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 200.0)


func _process(_delta: float) -> void:
	var offset := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0.0, 0.0, _distance)
	_camera.global_position = _target + offset
	_camera.look_at(_target, Vector3.UP)


func _show(index: int) -> void:
	_index = wrapi(index, 0, EFFECTS.size())
	if _current:
		_current.queue_free()
	var entry: Array = EFFECTS[_index]
	_current = (load(entry[0]) as PackedScene).instantiate()
	var path: String = entry[0]
	if path.contains("/Post Process/"):
		# Screen overlays live inside the camera.
		_camera.add_child(_current)
	else:
		add_child(_current)
		_target = entry[1]
		_distance = entry[2]
		# Vexa stands next to the effect, like in the stations of the overview scene.
		if _vexa:
			_vexa.position = Vector3(_target.x + clampf(_distance * 0.25, 1.2, 4.0), 0.0, _target.z)
	_label.text = "%d / %d   %s

Left / Right: change effect    Space: replay    Right drag: orbit    Wheel: zoom" % [
		_index + 1, EFFECTS.size(), path.get_file().get_basename()]
