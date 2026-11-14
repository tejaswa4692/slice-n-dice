extends Node3D
## Frees this node (and the effect under it) after countdown_seconds (Unity SC_Vefects_Delete_After_Time).

@export var countdown_seconds := 5.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		get_tree().create_timer(countdown_seconds).timeout.connect(queue_free)
