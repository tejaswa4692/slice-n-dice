extends GPUParticles3D
## Unity "Rate over Distance" (world simulation space): emits `rate` particles for every metre this node travels,
## spread along the path it moved this frame. The node's own timed particles are discarded by the process shader
## (sub_emitter_child), so only these are drawn.

@export var rate := 1.0

var _last := Vector3.ZERO
var _acc := 0.0
var _started := false


func _process(_delta: float) -> void:
	var p := global_position
	if not _started or not emitting:
		_last = p
		_started = true
		return
	var step := p.distance_to(_last) * rate
	if step > 0.0:
		var total := _acc + step
		var n := mini(int(total), amount)
		for i in n:
			var t := (float(i + 1) - _acc) / step
			emit_particle(Transform3D(Basis(), _last.lerp(p, t)), Vector3.ZERO, Color.WHITE, Color.BLACK, EMIT_FLAG_POSITION)
		_acc = total - floorf(total)
	_last = p
