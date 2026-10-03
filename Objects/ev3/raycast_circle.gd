extends Node3D

@onready var raycast_arr: Array[RayCast3D] = [$R, $RB, $FR, $FL, $L, $LB]
@onready var hand_cast: RayCast3D = $HandCast
@onready var left_hik: CCDIK3D = $"../rig/Skeleton3D/LeftHIK"
@onready var right_hik: CCDIK3D = $"../rig/Skeleton3D/RightHIK"


func get_closest() -> Vector3:
	var closest_point: Vector3 = Vector3.ZERO
	var smallest_distance = INF
	for raycast in raycast_arr:
		if raycast.is_colliding():
			var coll_pt := raycast.get_collision_point()
			var distance := global_position.distance_squared_to(coll_pt)
			if distance < smallest_distance:
				smallest_distance = distance
				closest_point = coll_pt
	return closest_point
