extends CharacterBody3D

var player: CharacterBody3D

func _ready() -> void:
	player = get_tree().get_nodes_in_group("player")[0]

func _process(delta: float) -> void:
	if player != null:
		var target_pos = player.global_position
		var target_transform = transform.looking_at(target_pos, Vector3.UP)
		transform = transform.interpolate_with(target_transform, 10.0 * delta)
		var direction := (target_pos - global_position).normalized()
		velocity = direction * 3.0
		
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		
		move_and_slide()
