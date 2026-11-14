@tool
extends MeshInstance3D
## Unity LineRenderer: a strip through `points` (node space, or world space with use_world_space) rebuilt every frame,
## facing the camera (alignment 0, Unity "View") or across the node's Z axis (alignment 1, "Transform Z").
## Width = width * width_samples(t); vertex colors = color_samples(t) (gamma, like Unity's gradient); UV.x runs along
## the line (stretch: 0..1, tile: one repeat per world unit), both scaled by texture_scale.

@export var points := PackedVector3Array()
@export var width := 1.0
## The width curve sampled evenly over the line (t = 0..1).
@export var width_samples := PackedFloat32Array([1.0])
## The color gradient sampled evenly over the line (t = 0..1).
@export var color_samples := PackedColorArray([Color.WHITE])
## Unity Texture Mode: 0 stretch, 1 tile (other modes are drawn as stretch).
@export var texture_mode := 0
@export var texture_scale := Vector2.ONE
@export var loop := false
@export var use_world_space := false
@export var alignment := 0

var _mesh := ArrayMesh.new()


func _ready() -> void:
	mesh = _mesh
	# The strip is rebuilt every frame: keep it from being culled with a stale box.
	custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))


func _sample_f(arr: PackedFloat32Array, t: float) -> float:
	if arr.is_empty():
		return 1.0
	if arr.size() == 1:
		return arr[0]
	var x := clampf(t, 0.0, 1.0) * float(arr.size() - 1)
	var i := mini(int(x), arr.size() - 2)
	return lerpf(arr[i], arr[i + 1], x - float(i))


func _sample_c(arr: PackedColorArray, t: float) -> Color:
	if arr.is_empty():
		return Color.WHITE
	if arr.size() == 1:
		return arr[0]
	var x := clampf(t, 0.0, 1.0) * float(arr.size() - 1)
	var i := mini(int(x), arr.size() - 2)
	return arr[i].lerp(arr[i + 1], x - float(i))


func _camera() -> Camera3D:
	if Engine.is_editor_hint():
		var vp = EditorInterface.get_editor_viewport_3d(0)
		return vp.get_camera_3d() if vp else null
	return get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	_rebuild()


func _rebuild() -> void:
	var pts := PackedVector3Array()
	for p in points:
		pts.append(to_local(p) if use_world_space else p)
	if loop and pts.size() > 2:
		pts.append(pts[0])
	var n := pts.size()
	_mesh.clear_surfaces()
	if n < 2:
		return
	var cam := _camera()
	var cam_local := to_local(cam.global_position) if cam else Vector3(0, 0, 10)
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist[0] = 0.0
	for i in range(1, n):
		dist[i] = dist[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := maxf(dist[n - 1], 1e-6)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var tan := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var facing := (cam_local - pts[i]).normalized() if alignment == 0 else Vector3.BACK
		var side := tan.cross(facing)
		if side.length_squared() < 1e-12:
			side = tan.cross(Vector3.UP if absf(tan.y) < 0.99 else Vector3.RIGHT)
		side = side.normalized()
		var t := dist[i] / total
		var hw := 0.5 * width * _sample_f(width_samples, t)
		var u := (dist[i] if texture_mode == 1 else t) * texture_scale.x
		var c := _sample_c(color_samples, t)
		for k in 2:
			var s := -1.0 if k == 0 else 1.0
			verts.append(pts[i] + side * hw * s)
			norms.append(facing)
			tans.append_array([tan.x, tan.y, tan.z, 1.0])
			# Godot UV.y = 1 - Unity v (the shaders flip it back).
			uvs.append(Vector2(u, 1.0 - float(k) * texture_scale.y))
			cols.append(c)
		if i > 0:
			var a := (i - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
