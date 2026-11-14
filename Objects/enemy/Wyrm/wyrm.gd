extends Node3D
class_name Wyrm

@export var segment_count: int = 14
@export var segment_spacing: float = 1.1
@export var head_size: float = 1.8
@export var tail_size: float = 0.6

@export_group("Wave")
@export var wave_amplitude: float = 0.6
@export var wave_frequency: float = 2.5
@export var wave_phase: float = 0.5

@export_group("Orbit")
@export var speed: float = 8.0
@export var turn_rate: float = 1.2
@export var orbit_radius: float = 25.0
@export var orbit_height: float = 14.0
@export var height_variation: float = 4.0
@export var orbit_clockwise: bool = true
@export var correction_strength: float = 1.0

const TRAIL_STEP: float = 0.25

var player: Player
var segments: Array[MeshInstance3D] = []
var trail: Array[Vector3] = []
var heading: Vector3 = Vector3.FORWARD
var phase: float = 0.0
var time: float = 0.0

func _ready() -> void:
	create_segments()
	create_trail()
	await get_tree().process_frame
	player = PlayerRefrence.player

func _process(delta: float) -> void:
	if player == null:
		return

	time += delta
	turn_toward(get_desired_direction(), delta)
	move(delta)
	update_trail()
	update_body(delta)

func create_segments() -> void:
	for i in range(segment_count):
		var t := float(i) / maxf(segment_count - 1, 1)
		var size := lerpf(head_size, tail_size, t)
		segments.append(make_segment(SphereMesh.new(), size))

func make_segment(mesh: Mesh, size: float) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.mesh = mesh
	segment.top_level = true
	add_child(segment)
	segment.scale = Vector3.ONE * size
	segment.global_position = global_position
	return segment

func create_trail() -> void:
	var point_count := int(segment_count * segment_spacing / TRAIL_STEP) + 10
	for i in range(point_count):
		trail.append(global_position + Vector3.BACK * TRAIL_STEP * i)

func get_desired_direction() -> Vector3:
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0, to_player.z)
	var radial_out := -flat.normalized() if flat.length_squared() > 0.0001 else Vector3.RIGHT
	var tangent := Vector3(-radial_out.z, 0, radial_out.x)
	if not orbit_clockwise:
		tangent = -tangent

	var target_height := player.global_position.y + orbit_height + sin(time * 0.4) * height_variation
	var radial_err := clampf((orbit_radius - flat.length()) / orbit_radius, -1.0, 1.0)
	var height_err := clampf((target_height - global_position.y) / orbit_height, -1.0, 1.0)

	var radial_pull := radial_out * radial_err * correction_strength
	var height_pull := Vector3.UP * height_err * correction_strength
	return (tangent + radial_pull + height_pull).normalized()

func turn_toward(desired: Vector3, delta: float) -> void:
	var angle := heading.angle_to(desired)
	if angle < 0.0001:
		return

	var axis := heading.cross(desired)
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	heading = heading.rotated(axis.normalized(), minf(angle, turn_rate * delta)).normalized()

func move(delta: float) -> void:
	global_position += heading * speed * delta
	if absf(heading.dot(Vector3.UP)) < 0.999:
		look_at(global_position + heading, Vector3.UP)

func update_trail() -> void:
	if trail[0].distance_to(global_position) >= TRAIL_STEP:
		trail.push_front(global_position)
		trail.pop_back()

func point_along_trail(distance: float) -> Vector3:
	var previous := global_position
	for point in trail:
		var step := previous.distance_to(point)
		if step > 0.0 and step >= distance:
			return previous.lerp(point, distance / step)
		distance -= step
		previous = point
	return previous

func update_body(delta: float) -> void:
	phase = fmod(phase + wave_frequency * delta, TAU)
	for i in range(segments.size()):
		var position_on_trail := point_along_trail(i * segment_spacing)
		var wave := sin(phase - i * wave_phase) * wave_amplitude
		segments[i].global_position = position_on_trail + global_basis.y * wave
