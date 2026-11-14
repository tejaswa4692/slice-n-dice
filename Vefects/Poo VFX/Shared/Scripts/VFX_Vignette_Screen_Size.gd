@tool
extends Node3D
## Scales this node to the camera frustum at its distance, so the screen overlay under it covers the whole view
## (Unity SC_Vefects_Vignette_Screen_Size_Auto_Scale). Keep the effect as a child of the camera.
## scale_compensation makes the overlay larger than the screen; the particle renderer's Max Particle Size (1 =
## the viewport height) then clamps it to exactly the screen.

@export var scale_compensation := 10.0

var _size := Vector2i.ZERO


func _ready() -> void:
	_match_screen()


func _process(_delta: float) -> void:
	var s := get_viewport().get_visible_rect().size
	if Vector2i(s) != _size:
		_match_screen()


func _match_screen() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	_size = Vector2i(vp.get_visible_rect().size)
	var cam := vp.get_camera_3d()
	if cam == null or _size.y == 0:
		return
	var distance := global_position.distance_to(cam.global_position)
	var height := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) * distance * scale_compensation
	var aspect := float(_size.x) / float(_size.y)
	scale = Vector3(height * aspect, height, 1.0)
