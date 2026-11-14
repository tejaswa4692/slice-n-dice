extends GPUParticles3D
## Unity "Inherit Velocity" (Initial mode, world simulation space): gives the process material the velocity this node
## moves with, so new particles start with `inherit_velocity` (process shader parameter) times that velocity.
## The process material is shared by the instances of the effect scene: with several moving instances the last one
## updated sets the velocity for all of them.

var _last := Vector3.ZERO
var _started := false


func _process(delta: float) -> void:
	var p := global_position
	var v := Vector3.ZERO
	if _started and delta > 0.0:
		v = (p - _last) / delta
	_last = p
	_started = true
	if process_material is ShaderMaterial:
		(process_material as ShaderMaterial).set_shader_parameter("emitter_velocity", v)
