extends Node
## Press Space to instance to_spawn_vfx under where_to_spawn (Unity SC_Vefects_Easy_Spawn): the demo uses it to
## spawn a screen vignette inside the camera.

@export var to_spawn_vfx: PackedScene
@export var where_to_spawn: NodePath


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and to_spawn_vfx:
		var parent := get_node_or_null(where_to_spawn)
		if parent:
			parent.add_child(to_spawn_vfx.instantiate())
