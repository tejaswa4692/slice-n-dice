@tool
extends Node
## Vefects - plays, pauses, stops and restarts every particle system under this node at once, instanced effects
## included, like Unity's Particle Effect panel. Attach it to any parent (an effect's root, the demo's "_ VFX" node)
## and use the buttons in the Inspector, in the editor or in game; scripts can call play(), pause(), stop() and
## restart(). Auto Replay restarts everything every Replay Interval seconds, one-shot systems included.
## What the buttons change in the editor is not saved: the scene is written with the values the systems had before.

const PARTICLE_CLASSES := ["GPUParticles3D", "GPUParticles2D", "CPUParticles3D", "CPUParticles2D"]

@export_tool_button("Play", "Play") var play_button := play
@export_tool_button("Pause / Resume", "Pause") var pause_button := pause
@export_tool_button("Stop", "Stop") var stop_button := stop
@export_tool_button("Restart", "Reload") var restart_button := restart

## In game, starts every system when the scene starts, also those saved with Emitting off.
@export var play_on_start := true
## Stop also removes the particles alive; off, they finish their lifetime.
@export var clear_on_stop := true

@export_group("Auto Replay")
## Restarts every system every Replay Interval seconds, in the editor and in game.
@export var auto_replay := false:
	set(value):
		auto_replay = value
		_time = 0.0
		# A script attached in the editor gets no _ready() until the scene is reopened, so _process() is off.
		set_process(value)
@export_range(0.1, 60.0, 0.1, "or_greater", "suffix:s") var replay_interval := 3.0

var paused := false

var _time := 0.0
## Speed Scale of each system before pause(): { node: float }.
var _speed := {}
## Editor only: [emitting, speed_scale] of each system when the scene was opened, and of each system the buttons
## changed, put back while the scene is saved: { node: Array }.
var _opened := {}
var _changed := {}
var _live := {}


func _ready() -> void:
	set_process(auto_replay)
	if Engine.is_editor_hint():
		for node in _particles():
			_opened[node] = _state(node)
	elif play_on_start:
		restart()


func _process(delta: float) -> void:
	if not auto_replay or paused:
		return
	if Engine.is_editor_hint():
		# The editor only draws a new frame when something changes on screen: redraw the 3D viewport's container
		# (the parent of the viewport this node is in) so the replays show without moving the mouse.
		var container := get_viewport().get_parent() as Control
		if container:
			container.queue_redraw()
	_time += delta
	if _time >= replay_interval:
		restart()


## Resumes paused systems and starts those not emitting (a finished one-shot system plays again).
func play() -> void:
	_resume()
	for node in _particles():
		_touch(node)
		if not node.emitting:
			node.emitting = true


## Freezes every system where it is; called again, resumes.
func pause() -> void:
	if paused:
		_resume()
		return
	paused = true
	for node in _particles():
		_touch(node)
		_speed[node] = node.speed_scale
		node.speed_scale = 0.0


## Stops emitting; with Clear On Stop, the particles alive are removed too.
func stop() -> void:
	_resume()
	for node in _particles():
		_touch(node)
		if clear_on_stop:
			node.restart()
		node.emitting = false
	if clear_on_stop:
		_clear_trails(self)


## Starts every system from the beginning, also those saved with Emitting off.
func restart() -> void:
	_resume()
	_time = 0.0
	for node in _particles():
		_touch(node)
		node.restart()
		node.emitting = true
	_clear_trails(self)


func _resume() -> void:
	if not paused:
		return
	paused = false
	for node in _speed:
		if is_instance_valid(node):
			node.speed_scale = _speed[node]
	_speed.clear()


func _particles(node: Node = self, found: Array[Node] = []) -> Array[Node]:
	if node.get_class() in PARTICLE_CLASSES:
		found.append(node)
	for child in node.get_children():
		_particles(child, found)
	return found


## Trail renderers (VFX_Trail_Renderer.gd) keep their points after a restart.
func _clear_trails(node: Node) -> void:
	var script := node.get_script() as Script
	if script and script.resource_path.ends_with("VFX_Trail_Renderer.gd") and node.has_method("clear"):
		node.clear()
	for child in node.get_children():
		_clear_trails(child)


func _state(node: Node) -> Array:
	return [node.emitting, node.speed_scale]


func _apply(node: Node, state: Array) -> void:
	if node.emitting != state[0]:
		node.emitting = state[0]
	if node.speed_scale != state[1]:
		node.speed_scale = state[1]


func _touch(node: Node) -> void:
	if Engine.is_editor_hint() and not _changed.has(node):
		_changed[node] = _opened.get(node, _state(node))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_live.clear()
			for node in _changed:
				if is_instance_valid(node):
					_live[node] = _state(node)
					_apply(node, _changed[node])
		NOTIFICATION_EDITOR_POST_SAVE:
			for node in _live:
				if is_instance_valid(node):
					_apply(node, _live[node])
			_live.clear()
