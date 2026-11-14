extends AudioStreamPlayer3D
## Unity AudioSource with Linear or Custom rolloff (Godot has no such attenuation model).
## The node uses ATTENUATION_DISABLED and this script applies Unity's curve:
## gain = curve(distance to the listener / MaxDistance), Hermite keys (time, value, in slope, out slope).

@export var rolloff_keys: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
@export var max_distance_unity: float = 500.0

var _base_db := 0.0


func _ready() -> void:
	_base_db = volume_db
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var listener: Node3D = vp.get_audio_listener_3d()
	if listener == null:
		listener = vp.get_camera_3d()
	if listener == null:
		return
	var g := _eval(global_position.distance_to(listener.global_position) / maxf(max_distance_unity, 0.0001))
	volume_db = _base_db + (linear_to_db(g) if g > 0.0 else -80.0)


func _eval(t: float) -> float:
	var n := rolloff_keys.size() / 4
	if n == 0:
		return 1.0
	if t <= rolloff_keys[0] or n == 1:
		return rolloff_keys[1]
	if t >= rolloff_keys[(n - 1) * 4]:
		return rolloff_keys[(n - 1) * 4 + 1]
	for i in n - 1:
		var t0 := rolloff_keys[i * 4]
		var t1 := rolloff_keys[i * 4 + 4]
		if t <= t1:
			var dt := t1 - t0
			if dt <= 0.0:
				return rolloff_keys[i * 4 + 5]
			var u := (t - t0) / dt
			var v0 := rolloff_keys[i * 4 + 1]
			var o0 := rolloff_keys[i * 4 + 3]
			var v1 := rolloff_keys[i * 4 + 5]
			var i1 := rolloff_keys[i * 4 + 6]
			return (2.0 * u * u * u - 3.0 * u * u + 1.0) * v0 + (u * u * u - 2.0 * u * u + u) * dt * o0 \
				+ (-2.0 * u * u * u + 3.0 * u * u) * v1 + (u * u * u - u * u) * dt * i1
	return rolloff_keys[(n - 1) * 4 + 1]
