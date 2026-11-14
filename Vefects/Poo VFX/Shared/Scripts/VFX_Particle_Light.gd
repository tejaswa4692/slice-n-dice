extends Node3D
## Vefects - Unity particle system Lights module for Godot.
##
## In Unity the light of these fires comes from a particle system whose renderer is off and whose Lights module
## attaches a copy of a light prefab (VFX_Point_Light) to its particles. GPU particles cannot drive lights, so this
## node runs the same particle system on the CPU (it only has a handful of particles) and moves one OmniLight3D per
## light, every frame:
##   - emission like Unity: rate over time from a continuous accumulator (particle k at k / rate), bursts at
##     k * duration + time, prewarm = the steady state of a system that started at t = 0;
##   - Unity's particle buffer order: a dying particle is replaced by the last one, new particles are appended; the
##     first `max_lights` particles of the buffer carry the lights (Lights module ratio 1);
##   - light color = prefab color * particle color, range = prefab range * range multiplier * particle size,
##     intensity = prefab intensity * intensity multiplier * particle alpha (Unity "Use Particle Color",
##     "Size Affects Range", "Alpha Affects Intensity").
## Unity point lights (URP, linear intensity) fall off with 1 / d^2 and the same range window as Godot's omni light
## with attenuation 2. The values are written by the scene (converted from the Unity prefab).

@export_group("Particle system")
@export var emitting := true
@export var looping := true
## Unity Duration (s).
@export var duration := 1.0
@export var prewarm := false
@export var start_delay := 0.0
## Unity World simulation space: particles stay where they were born when the node moves.
@export var world_space := true
## Rate over time (particles / s).
@export var rate := 0.0
## Bursts of one cycle: (time, count min, count max, probability).
@export var bursts := PackedVector4Array()
## Start lifetime (min, max).
@export var lifetime := Vector2(1.0, 1.0)
## Start size (min, max).
@export var start_size := Vector2(1.0, 1.0)
## Start color (Unity gamma space).
@export var start_color := Color(1.0, 1.0, 1.0, 1.0)
## Color over lifetime: color keys (r, g, b, time) and alpha keys (alpha, time); empty = off.
@export var color_keys := PackedVector4Array()
@export var alpha_keys := PackedVector2Array()
## Size over lifetime: Unity curve keys (time, value, in slope, out slope); empty = off.
@export var size_keys := PackedVector4Array()
@export var size_multiplier := 1.0

@export_group("Light")
## Prefab light color (gamma) including its color temperature.
@export var light_color := Color(1.0, 1.0, 1.0)
@export var light_intensity := 1.0
@export var light_range := 10.0
@export var intensity_multiplier := 1.0
@export var range_multiplier := 1.0
@export var use_particle_color := true
@export var size_affects_range := true
@export var alpha_affects_intensity := true
@export var max_lights := 1
@export var light_specular := 0.5

const STEP := 1.0 / 60.0

var _time := 0.0
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _pos: Array[Vector3] = []
var _lights: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in max_lights:
		var l := OmniLight3D.new()
		l.name = "Light%d" % i
		l.omni_attenuation = 2.0
		l.shadow_enabled = false
		l.light_specular = light_specular
		l.visible = false
		l.top_level = true
		add_child(l, false, Node.INTERNAL_MODE_FRONT)
		_lights.append(l)
	restart()


## Starts the system again (Unity Play): prewarmed loops start in their steady state.
func restart() -> void:
	_rng.randomize()
	_age.clear()
	_life.clear()
	_size.clear()
	_pos.clear()
	_time = -start_delay
	if prewarm and looping:
		# Run a whole number of emission periods (rate particles and bursts back in phase) longer than the longest
		# life: the system is in its steady state with the phase of one that started at t = 0.
		var period := duration
		if rate > 0.0:
			var k := 1
			while k < 1000 and absf(rate * duration * k - roundf(rate * duration * k)) > 1e-4:
				k += 1
			period = duration * k
		var pre := ceilf(lifetime.y / period) * period
		_time = 0.0
		while _time < pre - 1e-6:
			_step(minf(STEP, pre - _time))
	_update_lights()


func _process(delta: float) -> void:
	if not emitting and _age.is_empty():
		_update_lights()
		return
	_step(delta)
	_update_lights()


func _step(dt: float) -> void:
	var t0 := _time
	var t1 := _time + dt
	_time = t1
	# Age, then remove the dead (Unity: the last particle takes the free place).
	var i := 0
	while i < _age.size():
		_age[i] += dt
		i += 1
	i = 0
	while i < _age.size():
		if _age[i] > _life[i]:
			var last := _age.size() - 1
			_age[i] = _age[last]
			_life[i] = _life[last]
			_size[i] = _size[last]
			_pos[i] = _pos[last]
			_age.resize(last)
			_life.resize(last)
			_size.resize(last)
			_pos.resize(last)
		else:
			i += 1
	if not emitting or t1 <= 0.0:
		return
	var a := maxf(t0, 0.0)
	# Rate over time: particle k at k / rate (k >= 1); a one-shot system stops before t = duration.
	var end := t1 if looping else minf(t1, duration)
	if rate > 0.0 and end > a:
		var k0 := floori(a * rate + 1e-6)
		var k1 := floori(end * rate + 1e-6)
		if not looping:
			k1 = mini(k1, ceili(duration * rate - 1e-4) - 1)
		for k in range(k0 + 1, k1 + 1):
			_spawn(t1 - float(k) / rate)
	# Bursts: emitted in the step (t0, t1] that contains their instant (the first step also takes t = 0).
	for b in bursts:
		var c0 := floori(a / duration) if looping else 0
		var c1 := floori(t1 / duration) if looping else 0
		for c in range(c0, c1 + 1):
			var bt := c * duration + b.x
			var after := bt > t0 + 1e-6 if t0 > 1e-6 else bt >= -1e-6
			if not after or bt > t1 + 1e-6 or (not looping and bt > duration + 1e-6):
				continue
			if _rng.randf() >= b.w:
				continue
			for j in _rng.randi_range(int(b.y), int(b.z)):
				_spawn(t1 - bt)


func _spawn(age: float) -> void:
	_age.append(age)
	_life.append(_rng.randf_range(lifetime.x, lifetime.y))
	_size.append(_rng.randf_range(start_size.x, start_size.y))
	_pos.append(global_position if world_space else Vector3.INF)


func _gradient(t: float) -> Color:
	var c := Color(1.0, 1.0, 1.0, 1.0)
	if color_keys.size() > 0:
		var rgb := Vector3(color_keys[0].x, color_keys[0].y, color_keys[0].z)
		if t > color_keys[0].w:
			var lst := color_keys[color_keys.size() - 1]
			rgb = Vector3(lst.x, lst.y, lst.z)
			for i in color_keys.size() - 1:
				var ka := color_keys[i]
				var kb := color_keys[i + 1]
				if t >= ka.w and t <= kb.w:
					var f := (t - ka.w) / (kb.w - ka.w) if kb.w > ka.w else 1.0
					rgb = Vector3(ka.x, ka.y, ka.z).lerp(Vector3(kb.x, kb.y, kb.z), f)
					break
		c = Color(rgb.x, rgb.y, rgb.z, 1.0)
	if alpha_keys.size() > 0:
		var al := alpha_keys[0].x
		if t > alpha_keys[0].y:
			al = alpha_keys[alpha_keys.size() - 1].x
			for i in alpha_keys.size() - 1:
				var ka := alpha_keys[i]
				var kb := alpha_keys[i + 1]
				if t >= ka.y and t <= kb.y:
					al = lerpf(ka.x, kb.x, (t - ka.y) / (kb.y - ka.y) if kb.y > ka.y else 1.0)
					break
		c.a = al
	return c


func _curve(t: float) -> float:
	if size_keys.is_empty():
		return 1.0
	var k0 := size_keys[0]
	if size_keys.size() == 1 or t <= k0.x:
		return k0.y * size_multiplier
	var kl := size_keys[size_keys.size() - 1]
	if t >= kl.x:
		return kl.y * size_multiplier
	for i in size_keys.size() - 1:
		var p := size_keys[i]
		var q := size_keys[i + 1]
		if t <= q.x:
			var d := q.x - p.x
			if d <= 0.0:
				return q.y * size_multiplier
			var u := (t - p.x) / d
			var u2 := u * u
			var u3 := u2 * u
			return ((2.0 * u3 - 3.0 * u2 + 1.0) * p.y + (u3 - 2.0 * u2 + u) * d * p.w + (-2.0 * u3 + 3.0 * u2) * q.y + (u3 - u2) * d * q.z) * size_multiplier
	return kl.y * size_multiplier


func _update_lights() -> void:
	for li in _lights.size():
		var l := _lights[li]
		if li >= _age.size() or not is_visible_in_tree():
			l.visible = false
			continue
		var t := clampf(_age[li] / maxf(_life[li], 1e-4), 0.0, 1.0)
		# Particle color as Unity stores it (Color32).
		var g := _gradient(t)
		var pc := Color(roundf(255.0 * start_color.r * g.r) / 255.0, roundf(255.0 * start_color.g * g.g) / 255.0,
				roundf(255.0 * start_color.b * g.b) / 255.0, roundf(255.0 * start_color.a * g.a) / 255.0)
		var col := light_color
		if use_particle_color:
			col = Color(light_color.r * pc.r, light_color.g * pc.g, light_color.b * pc.b)
		var energy := light_intensity * intensity_multiplier * (pc.a if alpha_affects_intensity else 1.0)
		var rng := light_range * range_multiplier * (_size[li] * _curve(t) if size_affects_range else 1.0)
		l.light_color = col
		l.light_energy = energy
		l.omni_range = maxf(rng, 0.0001)
		l.global_position = _pos[li] if world_space else global_position
		l.visible = energy > 0.0
