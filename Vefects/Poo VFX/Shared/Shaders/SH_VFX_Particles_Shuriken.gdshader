// Vefects - Unity Shuriken -> Godot 4 process shader (GPUParticles3D).
// Every effect scene sets these uniforms from the settings of its Unity prefab.
//
// The simulation runs in Unity space (left handed, +Z forward, metres) in the particle system's
// simulation space and converts to Godot (right handed: (x, y, z)_godot = (x, y, -z)_unity) when
// writing TRANSFORM. Motion is integrated step by step like Shuriken (gravity, velocity over lifetime,
// limit velocity, angular velocity), so it matches Unity at the same frame rate.
//
// Simulation space: the nodes use `local_coords = false`, so TRANSFORM is the world matrix and
// EMISSION_TRANSFORM is the node's global transform E, read every frame (particles follow the emitter,
// like Unity's Local simulation space). Unity uses the system transform with the scale of its scaling
// mode (Hierarchy: lossy scale, Local: the system's own local scale): D = E with that scale.
// Unity World simulation space (`world_space`): on its first simulated frame the particle is moved into world
// space with the emitter transform of that moment and from then on it no longer follows the emitter.
//
// Prewarm: Unity starts a prewarmed loop in its steady state, with the emission phase of a system that started at
// t = 0 (measured: rate particles at k / rate, bursts at k * duration). The scene node's `preprocess` simulates a
// whole number of emission periods before the first frame, which gives exactly that.
//
// Rate over time: Unity's emission accumulator is not reset when a loop wraps (measured: 7 /s with a 1.6 s duration
// emits at k / 7). The schedule therefore repeats every `duration` = the shortest whole number of Unity cycles in
// which rate * time is an integer (the emission period); `unity_duration` is the Unity Duration.
//
// Emission: Godot spawns slot i of a cycle at i * lifetime / amount. Every Unity particle of one
// Unity cycle (bursts first, then rate over time) gets one slot; the slot stays invisible until its
// real Unity spawn time, so each particle is born exactly when Unity emits it and starts its
// flipbook at frame 0. One-shot systems spawn every slot at t = 0 (explosiveness 1) and each slot waits
// for its Unity time. Looping systems spawn slot i at i * duration / slots_per_cycle; the slots form a
// grid fine enough (<= 1/2400 s) that every Unity particle gets the slot spawned at its Unity
// time; when several share one instant (bursts) the later ranks start up to a few ms late but with the
// age they would have, so their state is exact.
//
// Curves are Unity AnimationCurves (Hermite) packed as vec4(time, value, in_slope, out_slope) in
// `curve_keys`; a MinMaxCurve is vec4(mode, scalar, min_scalar, 0) + ivec4(offset_a, count_a, offset_b, count_b).
// Gradients are packed in `gradient_keys`: color keys vec4(r, g, b, time), alpha keys vec4(a, time, 0, 0).
//
// Data written for the render shaders (see VFX_Shuriken_Render.gdshaderinc). MODEL_MATRIX in the
// render shader is the world matrix W below:
//   W[3]          particle position (world).
//   view billboard / vertical billboard: W[0], W[1], W[2] = world axes * size x, y, z.
//   stretched:    W[0] = side * width, W[1] = velocity direction * length, W[2] = normal * size y.
//   oriented quad (local/world aligned billboard, horizontal billboard), mesh: W = rotation * size.
//   CUSTOM.x      rotation (radians, positive = clockwise, as in Unity) for camera facing modes; mesh mode:
//                 custom data lanes 4 and 5.
//   CUSTOM.y      flipbook frame + 1024 * flip U + 2048 * flip V + 4096 * flip Z + 8192 * mesh index
//                 + 32768 * custom data lane 6 (9 bits).
//   CUSTOM.z/w    custom data lanes 0, 1 / 2, 3 (12 bits each: lo + 4096 * hi, whole numbers, exact in a float).
//                 Each Custom1 / Custom2 component that changes per particle is quantized over its [min, max]
//                 (`custom_lanes`, `custom1_min` ...); the render shader decodes them (VFX_Shuriken_Render).
//   COLOR         start color * color over lifetime (gamma space, like Unity's vertex color).
shader_type particles;
render_mode disable_velocity, disable_force;

group_uniforms Main;
uniform bool looping = false;
/** Emission period: the emission schedule repeats every `duration` seconds (a whole number of Unity cycles). */
uniform float duration = 1.0;
/** Unity "Duration" (curves over the emitter time). */
uniform float unity_duration = 1.0;
/** Unity World simulation space. */
uniform bool world_space = false;
uniform float simulation_speed = 1.0;
/** Unity Inherit Velocity (Initial mode): new particles start with this multiplier * emitter_velocity. */
uniform float inherit_velocity = 0.0;
/** Velocity of the emitter node (Godot world space), set every frame by VFX_Inherit_Velocity.gd. */
uniform vec3 emitter_velocity = vec3(0.0);
/** Unity "Start Delay" (only the first cycle of a looping system waits). */
uniform float start_delay = 0.0;
uniform vec4 start_lifetime = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 start_lifetime_keys = ivec4(0);
uniform vec4 start_speed = vec4(0.0, 0.0, 0.0, 0.0);
uniform ivec4 start_speed_keys = ivec4(0);
uniform bool start_size_3d = false;
uniform vec4 start_size_x = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 start_size_x_keys = ivec4(0);
uniform vec4 start_size_y = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 start_size_y_keys = ivec4(0);
uniform vec4 start_size_z = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 start_size_z_keys = ivec4(0);
uniform bool start_rotation_3d = false;
/** Radians. Z: positive = clockwise (Unity). */
uniform vec4 start_rotation_x = vec4(0.0);
uniform ivec4 start_rotation_x_keys = ivec4(0);
uniform vec4 start_rotation_y = vec4(0.0);
uniform ivec4 start_rotation_y_keys = ivec4(0);
uniform vec4 start_rotation = vec4(0.0, 0.0, 0.0, 0.0);
uniform ivec4 start_rotation_keys = ivec4(0);
/** Unity "Flip Rotation": proportion of particles that rotate the other way. */
uniform float flip_rotation = 0.0;
/** 0 color, 1 gradient, 2 two colors, 3 two gradients, 4 random color (Unity MinMaxGradient). */
uniform int start_color_mode = 0;
uniform vec4 start_color_a = vec4(1.0);
uniform vec4 start_color_b = vec4(1.0);
uniform ivec4 start_color_gradient_a = ivec4(0);
uniform ivec4 start_color_gradient_b = ivec4(0);
/** Physics.gravity (Unity world axes). */
uniform vec3 gravity = vec3(0.0, -9.81, 0.0);
uniform vec4 gravity_modifier = vec4(0.0);
uniform ivec4 gravity_modifier_keys = ivec4(0);
/** 0 hierarchy, 1 local, 2 shape (Unity ParticleSystemScalingMode). */
uniform int scaling_mode = 0;
/** The system's own Transform local scale (Local scaling mode). */
uniform vec3 own_scale = vec3(1.0);

group_uniforms Emission;
/** Godot slots per Unity cycle. */
uniform int slots_per_cycle = 1;
/** Number of burst entries (one per particle a burst can emit). */
uniform int burst_slots = 0;
/** Rate over time (particles / s); rate particle j is emitted at (j + 1) / rate. */
uniform float rate_over_time = 0.0;
/** Rate particles per cycle; particle j uses slot min(rate_first + j * rate_step, slots_per_cycle - 1). */
uniform int rate_count = 0;
uniform int rate_first = 0;
uniform int rate_step = 1;
/** Godot `amount` (slots_per_cycle * cycle_groups). */
uniform int total_slots = 1;
uniform int cycle_groups = 1;
/** Burst entry: vec4(time, probability, count_min, count_max). */
uniform vec4 burst_slot[512];
/** Index of the particle inside its burst. */
uniform float burst_rank[512];
/** Slot used by each burst entry. */
uniform int burst_grid_slot[512];
uniform int burst_seed = 0;
/** Unity sub-emitter (parent side): particles emitted into the `sub_emitter` node (emit_subparticle()) when a
 *  particle is born (sub_emit_type 0), collides (1) or dies (2): sub_emit_count_min..sub_emit_count of them per event
 *  (the burst count of the Unity sub-emitter). */
uniform int sub_emit_type = 0;
uniform int sub_emit_count = 0;
uniform int sub_emit_count_min = 0;
/** Simulates without drawing: a Unity system whose renderer is off and only feeds sub-emitters, or a hidden copy of
 *  a parent system that feeds one more sub-emitter (Godot gives each node a single sub-emitter; the copy has the same
 *  fixed seed, so it simulates exactly the same particles). */
uniform bool draw_hidden = false;
/** Unity sub-emitter (child side): particles only come from the parent's emit_subparticle(). Godot 4.7 delivers
 *  sub-particles only to a target that is emitting, so the node emits and its own particles are discarded in start()
 *  (RESTART_POSITION is false for a particle placed by emit_subparticle()). Inherit flags in sub_inherit. */
uniform bool sub_emitter_child = false;
/** Rate over distance particle of a local system with a world-space trail (Unity): the trail runs from the particle
 *  back to the world point where it was born (USERDATA6.xyz). */
uniform bool distance_trail = false;
uniform int sub_inherit = 0;
/** Emulated Unity Birth sub-emitter (child side). Godot 4.7 does not deliver emit_subparticle() to a target whose
 *  process shader uses USERDATA, so the child emits on the parent's schedule by itself, born at the parent emitter
 *  (EMISSION_TRANSFORM * sub_parent_from_child) and, with inherit rotation, with a rotation drawn from the parent's
 *  start rotation. */
uniform bool sub_emulated = false;
/** Sub-emitter whose parent is a single particle with a fixed motion: the particles are born along the parent's
 *  path (displacement curves over the parent's lifetime `emitter_path_length`, Unity axes). */
uniform bool emitter_path = false;
uniform float emitter_path_length = 1.0;
uniform ivec4 emitter_path_x = ivec4(0);
uniform ivec4 emitter_path_y = ivec4(0);
uniform ivec4 emitter_path_z = ivec4(0);
uniform mat4 sub_parent_from_child = mat4(1.0);
uniform vec4 sub_parent_rotation = vec4(0.0);
uniform ivec4 sub_parent_rotation_keys = ivec4(0);

group_uniforms Shape;
/** -1 none (origin, +Z), Unity ParticleSystemShapeType otherwise (0 sphere, 2 hemisphere, 4 cone, 5 box, 10 circle, 12 edge). */
uniform int shape_type = -1;
uniform float shape_radius = 1.0;
uniform float shape_radius_thickness = 1.0;
uniform float shape_angle = 25.0;
uniform float shape_arc = 360.0;
/** 0 random, 3 burst spread (Unity ParticleSystemShapeMultiModeValue). */
uniform int shape_arc_mode = 0;
uniform float shape_arc_spread = 0.0;
uniform float shape_length = 5.0;
/** Donut shape: radius of the tube. */
uniform float shape_donut_radius = 0.2;
uniform vec3 shape_position = vec3(0.0);
/** Unity euler angles in degrees. */
uniform vec3 shape_rotation = vec3(0.0);
uniform vec3 shape_scale = vec3(1.0);
uniform float shape_random_direction = 0.0;
uniform float shape_spherical_direction = 0.0;
uniform float shape_random_position = 0.0;
uniform bool shape_align_to_direction = false;
/** Shape Mesh (type 6): points of the mesh surface (Unity mesh space) and their normals, baked from the shape mesh. */
uniform sampler2D shape_mesh_points : filter_nearest;
uniform sampler2D shape_mesh_normals : filter_nearest;
uniform int shape_mesh_count = 0;

group_uniforms VelocityOverLifetime;
uniform bool velocity_over_lifetime = false;
uniform bool velocity_world = false;
uniform vec4 velocity_x = vec4(0.0);
uniform ivec4 velocity_x_keys = ivec4(0);
uniform vec4 velocity_y = vec4(0.0);
uniform ivec4 velocity_y_keys = ivec4(0);
uniform vec4 velocity_z = vec4(0.0);
uniform ivec4 velocity_z_keys = ivec4(0);
uniform vec4 velocity_speed_modifier = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 velocity_speed_modifier_keys = ivec4(0);

/** Orbital velocity (radians / s around the system's X, Y, Z axes), its centre offset and radial velocity. */
uniform bool velocity_orbital = false;
uniform vec4 orbital_x = vec4(0.0);
uniform ivec4 orbital_x_keys = ivec4(0);
uniform vec4 orbital_y = vec4(0.0);
uniform ivec4 orbital_y_keys = ivec4(0);
uniform vec4 orbital_z = vec4(0.0);
uniform ivec4 orbital_z_keys = ivec4(0);
uniform vec4 orbital_offset_x = vec4(0.0);
uniform ivec4 orbital_offset_x_keys = ivec4(0);
uniform vec4 orbital_offset_y = vec4(0.0);
uniform ivec4 orbital_offset_y_keys = ivec4(0);
uniform vec4 orbital_offset_z = vec4(0.0);
uniform ivec4 orbital_offset_z_keys = ivec4(0);
uniform vec4 radial = vec4(0.0);
uniform ivec4 radial_keys = ivec4(0);

group_uniforms Noise;
/** Noise module: a smooth vector field sampled at the particle position * frequency (+ scroll), applied to the
 *  position as a velocity of `strength` * `position_amount` * `noise_velocity_scale` units / s. */
uniform bool noise = false;
uniform bool noise_separate_axes = false;
uniform vec4 noise_strength_x = vec4(0.0);
uniform ivec4 noise_strength_x_keys = ivec4(0);
uniform vec4 noise_strength_y = vec4(0.0);
uniform ivec4 noise_strength_y_keys = ivec4(0);
uniform vec4 noise_strength_z = vec4(0.0);
uniform ivec4 noise_strength_z_keys = ivec4(0);
uniform float noise_frequency = 0.5;
uniform vec4 noise_scroll_speed = vec4(0.0);
uniform ivec4 noise_scroll_speed_keys = ivec4(0);
uniform vec4 noise_position_amount = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 noise_position_amount_keys = ivec4(0);
uniform int noise_octaves = 1;
uniform float noise_octave_multiplier = 0.5;
uniform float noise_octave_scale = 2.0;
uniform float noise_velocity_scale = 1.0;
uniform int noise_seed = 0;

group_uniforms Collision;
/** World collision (Unity Collision module, type World): reacts to Godot's particle colliders
 *  (GPUParticlesCollision* nodes) with Unity's bounce / dampen. */
uniform bool collision = false;
uniform vec4 collision_bounce = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 collision_bounce_keys = ivec4(0);
uniform vec4 collision_dampen = vec4(0.0);
uniform ivec4 collision_dampen_keys = ivec4(0);
uniform vec4 collision_lifetime_loss = vec4(0.0);
uniform ivec4 collision_lifetime_loss_keys = ivec4(0);

group_uniforms ForceOverLifetime;
uniform bool force_over_lifetime = false;
uniform bool force_world = false;
uniform vec4 force_x = vec4(0.0);
uniform ivec4 force_x_keys = ivec4(0);
uniform vec4 force_y = vec4(0.0);
uniform ivec4 force_y_keys = ivec4(0);
uniform vec4 force_z = vec4(0.0);
uniform ivec4 force_z_keys = ivec4(0);

group_uniforms LimitVelocity;
uniform bool limit_velocity = false;
uniform vec4 limit_magnitude = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 limit_magnitude_keys = ivec4(0);
uniform float limit_dampen = 0.0;
/** Limit velocity drag (units / s per unit of speed), optionally scaled by the particle size and by the speed. */
uniform vec4 limit_drag = vec4(0.0);
uniform ivec4 limit_drag_keys = ivec4(0);
uniform bool limit_drag_by_size = false;
uniform bool limit_drag_by_speed = false;

group_uniforms RotationOverLifetime;
/** Angular velocity (rad/s, Unity axes; z positive = clockwise) from Rotation over Lifetime / by Speed. */
uniform bool rotation_over_lifetime = false;
uniform bool rotation_separate_axes = false;
uniform vec4 rotation_x = vec4(0.0);
uniform ivec4 rotation_x_keys = ivec4(0);
uniform vec4 rotation_y = vec4(0.0);
uniform ivec4 rotation_y_keys = ivec4(0);
uniform vec4 rotation_z = vec4(0.0);
uniform ivec4 rotation_z_keys = ivec4(0);
uniform bool rotation_by_speed = false;
uniform vec4 rotation_by_speed_z = vec4(0.0);
uniform ivec4 rotation_by_speed_z_keys = ivec4(0);
uniform vec2 rotation_by_speed_range = vec2(0.0, 1.0);

group_uniforms TextureSheet;
uniform bool texture_sheet = false;
uniform ivec2 flipbook_tiles = ivec2(1, 1);
/** 0 whole sheet, 1 single row. */
uniform int sheet_animation = 0;
/** Single row: fixed row index, or -1 for a random row per particle. */
uniform int sheet_row = 0;
uniform vec4 frame_over_time = vec4(1.0, 1.0, 1.0, 0.0);
uniform ivec4 frame_over_time_keys = ivec4(0);
uniform vec4 start_frame = vec4(0.0);
uniform ivec4 start_frame_keys = ivec4(0);
uniform float sheet_cycles = 1.0;

group_uniforms Renderer;
/** 0 billboard, 1 stretched, 2 horizontal, 3 vertical, 4 mesh (Unity ParticleSystemRenderMode). */
uniform int renderer_mode = 0;
/** 0 view, 1 world, 2 local, 3 facing, 4 velocity (Unity ParticleSystemRenderSpace). */
uniform int render_alignment = 0;
uniform float length_scale = 2.0;
uniform float velocity_scale = 0.0;
/** Proportion of particles flipped on each axis. */
uniform vec3 flip = vec3(0.0);
/** Mesh render mode with several meshes: number of meshes (uniform distribution). */
uniform int mesh_count = 1;

group_uniforms Trails;
/** Trails module (Particles mode): the trail of a camera facing billboard is passed to the draw passes in W[2]
 *  (world vector from the particle to the tail end). Its length is the distance the particle covered during the
 *  trail lifetime, estimated from the distance travelled and a running mean of the speed (Unity keeps the
 *  positions themselves). */
uniform bool trail = false;
uniform vec4 trail_lifetime = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 trail_lifetime_keys = ivec4(0);

group_uniforms ColorOverLifetime;
uniform bool color_over_lifetime = false;
/** 1 gradient, 3 two gradients (Unity MinMaxGradient). */
uniform int color_mode = 1;
uniform ivec4 color_gradient_a = ivec4(0);
uniform ivec4 color_gradient_b = ivec4(0);

group_uniforms SizeOverLifetime;
uniform bool size_over_lifetime = false;
uniform bool size_separate_axes = false;
uniform vec4 size_x = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 size_x_keys = ivec4(0);
uniform vec4 size_y = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 size_y_keys = ivec4(0);
uniform vec4 size_z = vec4(0.0, 1.0, 1.0, 0.0);
uniform ivec4 size_z_keys = ivec4(0);

group_uniforms CustomData;
/** Unity Custom1 / Custom2 vector components (MinMaxCurve each). */
uniform vec4 custom1[4];
uniform ivec4 custom1_keys[4];
uniform vec4 custom2[4];
uniform ivec4 custom2_keys[4];
/** Custom data in Color mode (MinMaxGradient, gradient keys) for slot 1 / 2. */
uniform int custom1_color_mode = -1;
uniform vec4 custom1_color_a = vec4(1.0);
uniform vec4 custom1_color_b = vec4(1.0);
uniform ivec4 custom1_gradient_a = ivec4(0);
uniform ivec4 custom1_gradient_b = ivec4(0);
/** Lane of each custom data component in CUSTOM (3 bits each, Custom1.xyzw then Custom2.xyzw; 7 = not packed). */
uniform int custom_lanes = 16777215;
/** Quantization range of each packed component (the same values are set on the draw pass). */
uniform vec4 custom1_min = vec4(0.0);
uniform vec4 custom1_max = vec4(0.0);
uniform vec4 custom2_min = vec4(0.0);
uniform vec4 custom2_max = vec4(0.0);

group_uniforms Data;
uniform vec4 curve_keys[512];
uniform vec4 gradient_keys[96];
uniform int gradient_fixed_mask = 0;

group_uniforms;

// ----------------------------------------------------------------------------- random
uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

/** Random value k of a particle (regenerated from its seed whenever it is needed). */
float rnd(uint seed, uint k) {
	return float(hash(seed * uint(747796405) + k * 2891336453u + uint(1)) & uint(16777215)) / 16777215.0;
}

// ----------------------------------------------------------------------------- curves
float eval_keys(int off, int count, float t) {
	if (count <= 0) {
		return 0.0;
	}
	vec4 k0 = curve_keys[off];
	if (count == 1 || t <= k0.x) {
		return k0.y;
	}
	vec4 kl = curve_keys[off + count - 1];
	if (t >= kl.x) {
		return kl.y;
	}
	for (int i = 0; i < count - 1; i++) {
		vec4 a = curve_keys[off + i];
		vec4 b = curve_keys[off + i + 1];
		if (t <= b.x) {
			float dt = b.x - a.x;
			if (dt <= 0.0) {
				return b.y;
			}
			// Infinite tangents are stored as +-1e30: Unity holds the value (step).
			if (abs(a.w) > 1e29 || abs(b.z) > 1e29) {
				return a.y;
			}
			float u = (t - a.x) / dt;
			float u2 = u * u;
			float u3 = u2 * u;
			return (2.0 * u3 - 3.0 * u2 + 1.0) * a.y + (u3 - 2.0 * u2 + u) * dt * a.w + (-2.0 * u3 + 3.0 * u2) * b.y + (u3 - u2) * dt * b.z;
		}
	}
	return kl.y;
}

/** Unity MinMaxCurve: m = (mode, scalar, min_scalar, 0); mode 0 constant, 1 curve, 2 two curves, 3 two constants. */
float minmax(vec4 m, ivec4 k, float t, float r) {
	int mode = int(m.x);
	if (mode == 0) {
		return m.y;
	} else if (mode == 1) {
		return eval_keys(k.x, k.y, t) * m.y;
	} else if (mode == 2) {
		return mix(eval_keys(k.z, k.w, t), eval_keys(k.x, k.y, t), r) * m.y;
	}
	return mix(m.z, m.y, r);
}

// ----------------------------------------------------------------------------- gradients
vec4 eval_gradient(ivec4 g, int fixed_bit, float t) {
	bool fixed_mode = ((gradient_fixed_mask >> fixed_bit) & 1) == 1;
	vec3 rgb = vec3(1.0);
	float a = 1.0;
	if (g.y > 0) {
		vec4 k0 = gradient_keys[g.x];
		rgb = k0.rgb;
		if (fixed_mode) {
			// Unity "Fixed": the first key whose time is >= t.
			rgb = gradient_keys[g.x + g.y - 1].rgb;
			for (int i = g.y - 1; i >= 0; i--) {
				vec4 k = gradient_keys[g.x + i];
				if (k.w >= t) {
					rgb = k.rgb;
				}
			}
		} else if (t > k0.w) {
			rgb = gradient_keys[g.x + g.y - 1].rgb;
			for (int i = 0; i < g.y - 1; i++) {
				vec4 ka = gradient_keys[g.x + i];
				vec4 kb = gradient_keys[g.x + i + 1];
				if (t >= ka.w && t <= kb.w) {
					rgb = mix(ka.rgb, kb.rgb, kb.w > ka.w ? (t - ka.w) / (kb.w - ka.w) : 1.0);
					break;
				}
			}
		}
	}
	if (g.w > 0) {
		vec4 k0 = gradient_keys[g.z];
		a = k0.x;
		if (fixed_mode) {
			a = gradient_keys[g.z + g.w - 1].x;
			for (int i = g.w - 1; i >= 0; i--) {
				vec4 k = gradient_keys[g.z + i];
				if (k.y >= t) {
					a = k.x;
				}
			}
		} else if (t > k0.y) {
			a = gradient_keys[g.z + g.w - 1].x;
			for (int i = 0; i < g.w - 1; i++) {
				vec4 ka = gradient_keys[g.z + i];
				vec4 kb = gradient_keys[g.z + i + 1];
				if (t >= ka.y && t <= kb.y) {
					a = mix(ka.x, kb.x, kb.y > ka.y ? (t - ka.y) / (kb.y - ka.y) : 1.0);
					break;
				}
			}
		}
	}
	return vec4(rgb, a);
}

vec4 minmax_gradient(int mode, vec4 ca, vec4 cb, ivec4 ga, ivec4 gb, int bit_a, int bit_b, float t, float r) {
	if (mode == 1) {
		return eval_gradient(ga, bit_a, t);
	} else if (mode == 2) {
		return mix(cb, ca, r);
	} else if (mode == 3) {
		return mix(eval_gradient(gb, bit_b, t), eval_gradient(ga, bit_a, t), r);
	} else if (mode == 4) {
		return eval_gradient(ga, bit_a, r);
	}
	return ca;
}

// ----------------------------------------------------------------------------- geometry
mat3 rot_x(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_y(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 rot_z(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

/** Unity Quaternion.Euler (degrees): Z, then X, then Y. */
mat3 unity_euler(vec3 deg) {
	vec3 r = radians(deg);
	return rot_y(r.y) * rot_x(r.x) * rot_z(r.z);
}

const mat3 FLIP_Z = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, -1.0));

vec3 to_godot(vec3 p) {
	return vec3(p.x, p.y, -p.z);
}

vec3 random_unit(uint seed, uint k) {
	float u = rnd(seed, k) * 2.0 - 1.0;
	float a = rnd(seed, k + uint(1)) * TAU;
	float s = sqrt(max(0.0, 1.0 - u * u));
	return vec3(s * cos(a), s * sin(a), u);
}

void emit_shape(uint seed, float rank, float count, out vec3 pos, out vec3 dir) {
	pos = vec3(0.0);
	dir = vec3(0.0, 0.0, 1.0);
	float inner = 1.0 - clamp(shape_radius_thickness, 0.0, 1.0);
	if (shape_type == 0 || shape_type == 2) {
		// Sphere / hemisphere (+Z half).
		dir = random_unit(seed, uint(40));
		if (shape_type == 2) {
			dir.z = abs(dir.z);
		}
		float rr = pow(mix(inner * inner * inner, 1.0, rnd(seed, uint(42))), 1.0 / 3.0);
		pos = dir * rr * shape_radius;
	} else if (shape_type == 4 || shape_type == 8 || shape_type == 10) {
		// Cone (base on the XY plane, opening along +Z) / cone volume (anywhere inside the cone up to its length) /
		// circle (XY plane, radial direction).
		float f = rnd(seed, uint(43));
		if (shape_arc_mode == 3) {
			// Burst spread: the particles of one burst are spread evenly over the arc.
			f = count > 0.0 ? rank / count : 0.0;
		}
		float a = radians(shape_arc) * f;
		float rr = sqrt(mix(inner * inner, 1.0, rnd(seed, uint(44))));
		vec2 d = vec2(cos(a), sin(a));
		pos = vec3(d * rr * shape_radius, 0.0);
		if (shape_type == 4 || shape_type == 8) {
			float ang = radians(shape_angle) * rr;
			dir = vec3(d * sin(ang), cos(ang));
			if (shape_type == 8) {
				// Along the emission line, so the cone widens with the angle like Unity's volume.
				pos += dir / max(dir.z, 1e-4) * shape_length * rnd(seed, uint(53));
			}
		} else {
			dir = vec3(d, 0.0);
		}
	} else if (shape_type == 17) {
		// Donut: ring of radius shape_radius on the XY plane, tube of radius shape_donut_radius; emits away from
		// the tube centre line.
		float f = rnd(seed, uint(43));
		if (shape_arc_mode == 3) {
			f = count > 0.0 ? rank / count : 0.0;
		}
		float a = radians(shape_arc) * f;
		vec3 ring = vec3(cos(a), sin(a), 0.0);
		float phi = rnd(seed, uint(44)) * TAU;
		vec3 tube = ring * cos(phi) + vec3(0.0, 0.0, 1.0) * sin(phi);
		float rr = sqrt(mix(inner * inner, 1.0, rnd(seed, uint(45))));
		pos = ring * shape_radius + tube * rr * shape_donut_radius;
		dir = tube;
	} else if (shape_type == 5) {
		// Box (volume), emits along +Z.
		pos = vec3(rnd(seed, uint(45)), rnd(seed, uint(46)), rnd(seed, uint(47))) - 0.5;
	} else if (shape_type == 6 && shape_mesh_count > 0) {
		// Mesh: one of the baked surface points, emitting along its normal.
		int i = min(int(rnd(seed, uint(45)) * float(shape_mesh_count)), shape_mesh_count - 1);
		int side = textureSize(shape_mesh_points, 0).x;
		ivec2 c = ivec2(i % side, i / side);
		pos = texelFetch(shape_mesh_points, c, 0).xyz;
		vec3 n = texelFetch(shape_mesh_normals, c, 0).xyz;
		dir = length(n) > 0.0 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	} else if (shape_type == 16) {
		// Rectangle: XY plane, unit size (times the shape scale), emits along +Z.
		pos = vec3(rnd(seed, uint(45)) - 0.5, rnd(seed, uint(46)) - 0.5, 0.0);
	} else if (shape_type == 12) {
		// Single sided edge along X, emits along +Y.
		pos = vec3((rnd(seed, uint(45)) * 2.0 - 1.0) * shape_radius, 0.0, 0.0);
		dir = vec3(0.0, 1.0, 0.0);
	}
	if (shape_type >= 0) {
		if (shape_random_direction > 0.0) {
			dir = normalize(mix(dir, random_unit(seed, uint(48)), shape_random_direction));
		}
		if (shape_spherical_direction > 0.0) {
			dir = normalize(mix(dir, length(pos) > 0.0 ? normalize(pos) : dir, shape_spherical_direction));
		}
		if (shape_random_position > 0.0) {
			pos += random_unit(seed, uint(50)) * rnd(seed, uint(52)) * shape_random_position;
		}
		mat3 srot = unity_euler(shape_rotation);
		pos = srot * (pos * shape_scale) + shape_position;
		// The shape scale also scales the directions (a cone or sphere flattened to 0 on an axis emits a flat fan).
		vec3 sdir = dir * shape_scale;
		dir = normalize(srot * (dot(sdir, sdir) > 1e-12 ? sdir : dir));
	}
}

/** Rotation of a transform basis. Axes scaled to 0 somewhere in the hierarchy (Unity allows it: Local scaling only
 *  takes the rotation of the parents) are rebuilt from the other two, so the rotation stays defined. */
mat3 basis_rotation(mat4 e) {
	vec3 x = e[0].xyz;
	vec3 y = e[1].xyz;
	vec3 z = e[2].xyz;
	if (length(y) < 1e-6) {
		y = cross(z, x);
	}
	if (length(x) < 1e-6) {
		x = cross(y, z);
	}
	if (length(z) < 1e-6) {
		z = cross(x, y);
	}
	x = length(x) < 1e-6 ? vec3(1.0, 0.0, 0.0) : normalize(x);
	y = length(y) < 1e-6 ? vec3(0.0, 1.0, 0.0) : normalize(y);
	z = length(z) < 1e-6 ? vec3(0.0, 0.0, 1.0) : normalize(z);
	return mat3(x, y, z);
}

/** Inverse of a basis; a singular one (zero scale) falls back to the inverse of its rotation. */
mat3 safe_inverse(mat3 m, mat3 rot) {
	return abs(determinant(m)) > 1e-12 ? inverse(m) : transpose(rot);
}

/** Simulation space of the system in Godot axes (see header). */
mat4 sim_space(mat4 e) {
	if (scaling_mode == 0) {
		return e;
	}
	vec3 s = scaling_mode == 1 ? own_scale : vec3(1.0);
	mat3 r = basis_rotation(e);
	return mat4(vec4(r[0] * s.x, 0.0), vec4(r[1] * s.y, 0.0), vec4(r[2] * s.z, 0.0), e[3]);
}

// ----------------------------------------------------------------------------- noise
vec3 noise_hash3(vec3 p, int axis) {
	uvec3 q = uvec3(ivec3(floor(p)) + ivec3(4096));
	uint h = hash(q.x * 73856093u ^ q.y * 19349663u ^ q.z * 83492791u ^ uint(axis * 2654435 + noise_seed));
	vec3 g = vec3(float(h & 1023u), float((h >> 10u) & 1023u), float((h >> 20u) & 1023u)) / 511.5 - 1.0;
	return g;
}

/** Gradient noise in [-1, 1] (quintic interpolation), one decorrelated field per axis. */
float gradient_noise(vec3 p, int axis) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(noise_hash3(i + vec3(0.0, 0.0, 0.0), axis), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(noise_hash3(i + vec3(1.0, 0.0, 0.0), axis), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(noise_hash3(i + vec3(0.0, 1.0, 0.0), axis), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(noise_hash3(i + vec3(1.0, 1.0, 0.0), axis), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(noise_hash3(i + vec3(0.0, 0.0, 1.0), axis), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(noise_hash3(i + vec3(1.0, 0.0, 1.0), axis), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(noise_hash3(i + vec3(0.0, 1.0, 1.0), axis), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(noise_hash3(i + vec3(1.0, 1.0, 1.0), axis), f - vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return clamp(mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z) * 1.6, -1.0, 1.0);
}

vec3 noise_field(vec3 p) {
	vec3 n = vec3(0.0);
	float amp = 1.0;
	float freq = 1.0;
	float total = 0.0;
	for (int o = 0; o < max(noise_octaves, 1); o++) {
		n += amp * vec3(gradient_noise(p * freq, 0), gradient_noise(p * freq + vec3(31.4, 0.0, 0.0), 1), gradient_noise(p * freq + vec3(0.0, 0.0, 47.7), 2));
		total += amp;
		amp *= noise_octave_multiplier;
		freq *= noise_octave_scale;
	}
	return n / max(total, 1e-4);
}

/** Packs the custom data components the materials read into CUSTOM (see the header). */
vec4 pack_custom(vec4 c1, vec4 c2, float rot_out, float code) {
	float lanes[7] = float[7](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	bool mesh_lanes = false;
	for (int i = 0; i < 8; i++) {
		int lane = (custom_lanes >> (3 * i)) & 7;
		if (lane == 7) {
			continue;
		}
		float lo = i < 4 ? custom1_min[i] : custom2_min[i - 4];
		float hi = i < 4 ? custom1_max[i] : custom2_max[i - 4];
		float v = i < 4 ? c1[i] : c2[i - 4];
		// [min, max] maps to steps [margin, top - margin]: min and max decode exactly, the margin takes overshoots.
		float top = lane == 6 ? 511.0 : 4095.0;
		float margin = lane == 6 ? 5.0 : 40.0;
		float t = hi > lo ? (v - lo) / (hi - lo) : 0.0;
		lanes[lane] = clamp(round(t * (top - 2.0 * margin)) + margin, 0.0, top);
		mesh_lanes = mesh_lanes || lane == 4 || lane == 5;
	}
	float x = mesh_lanes ? lanes[4] + 4096.0 * lanes[5] : rot_out;
	return vec4(x, code + 32768.0 * lanes[6], lanes[0] + 4096.0 * lanes[1], lanes[2] + 4096.0 * lanes[3]);
}

// USERDATA layout
//   USERDATA1 = (pos.xyz unity simulation space, spawn delay)
//   USERDATA2 = (velocity.xyz unity, lifetime)
//   USERDATA3 = (packed start color, rotation.xyz radians)
//   USERDATA4 = (start size x, y, z, visible)
//   USERDATA5 = (seed bits, flags, simulated age, godot age)
//   USERDATA6 = (spawn time inside the cycle, burst rank, then in process(): trail distance travelled, trail mean speed)
void start() {
	// Sub-emitted particles: position and rotation of the parent particle (emit_subparticle()).
	vec3 parent_world = TRANSFORM[3].xyz;
	float parent_rot = CUSTOM.x;
	uint pseed = hash(NUMBER * 2654435761u + RANDOM_SEED + uint(17));
	int n = max(slots_per_cycle, 1);
	int idx = int(INDEX);
	int m = idx % n;
	int g = idx / n;

	// Unity particle of this slot and its spawn time inside the cycle.
	float spawn = 0.0;
	float prob = 1.0;
	float cmin = 1.0;
	float cmax = 1.0;
	float rank = 0.0;
	int burst_id = -1;
	bool used = false;
	for (int e = 0; e < burst_slots; e++) {
		if (burst_grid_slot[e] == m) {
			vec4 b = burst_slot[e];
			spawn = b.x;
			prob = b.y;
			cmin = b.z;
			cmax = b.w;
			rank = burst_rank[e];
			burst_id = e - int(rank);
			used = true;
			break;
		}
	}
	if (!used && rate_count > 0 && m >= rate_first) {
		int j = -1;
		if ((m - rate_first) % max(rate_step, 1) == 0) {
			j = (m - rate_first) / max(rate_step, 1);
		}
		if (m == n - 1 && rate_first + (rate_count - 1) * rate_step >= n - 1) {
			j = rate_count - 1;
		}
		if (j >= 0 && j < rate_count) {
			spawn = float(j + 1) / max(rate_over_time, 0.0001);
			used = true;
		}
	}

	// Unity cycle of the particle (start delay shifts the whole schedule; nothing exists before it).
	uint godot_cycle = (NUMBER - INDEX) / uint(max(total_slots, 1));
	int unity_cycle = looping ? int(godot_cycle) * cycle_groups + g : 0;
	float base = looping ? float(m) * duration / float(n) : 0.0;
	float delay = spawn - base;
	if (!looping) {
		delay += start_delay;
	} else if (start_delay > 0.0) {
		// Looping with a start delay: Unity time = Godot time - start_delay.
		float shifted = delay + start_delay;
		float wraps = floor((shifted + base) / duration);
		delay = shifted - wraps * duration;
		unity_cycle -= int(wraps);
		if (unity_cycle < 0) {
			used = false;
		}
	}
	delay /= max(simulation_speed, 0.0001);
	// A slot spawned after its Unity time starts with the age it is late by.
	float age0 = max(-delay, 0.0);
	delay = max(delay, 0.0);

	if (sub_emitter_child) {
		used = !RESTART_POSITION;
		spawn = 0.0;
		delay = 0.0;
		age0 = 0.0;
		prob = 1.0;
		cmin = cmax;
	}

	// Burst probability / random burst count (shared by every slot of the same Unity cycle).
	bool visible = used;
	if (used && (prob < 1.0 || cmax > cmin)) {
		// One-shot: every slot is emitted on the same frame (explosiveness 1), so the frame's RANDOM_SEED
		// gives a new burst count / probability roll on every play, like Unity's auto random seed.
		uint cyc = looping ? uint(max(unity_cycle, 0)) : RANDOM_SEED;
		uint bseed = hash(cyc * uint(7919) + uint(burst_seed) + uint(1) + uint(burst_id + 1) * uint(104729));
		float p = rnd(bseed, uint(1));
		float c = floor(mix(cmin, cmax + 0.999, rnd(bseed, uint(2))));
		visible = p < prob && rank < c;
	}

	// Emitter normalized time inside its Unity cycle, for curves evaluated over the system duration (the emission
	// period can span several cycles).
	float et = spawn / max(unity_duration, 0.0001);
	et = et > 1.0 + 1e-5 ? et - floor(et) : clamp(et, 0.0, 1.0);
	float life = minmax(start_lifetime, start_lifetime_keys, et, rnd(pseed, uint(1)));
	float speed = minmax(start_speed, start_speed_keys, et, rnd(pseed, uint(2)));
	vec3 sz;
	sz.x = minmax(start_size_x, start_size_x_keys, et, rnd(pseed, uint(3)));
	sz.y = start_size_3d ? minmax(start_size_y, start_size_y_keys, et, rnd(pseed, uint(4))) : sz.x;
	sz.z = start_size_3d ? minmax(start_size_z, start_size_z_keys, et, rnd(pseed, uint(5))) : sz.x;
	vec3 rot = vec3(0.0, 0.0, minmax(start_rotation, start_rotation_keys, et, rnd(pseed, uint(6))));
	if (start_rotation_3d) {
		rot.x = minmax(start_rotation_x, start_rotation_x_keys, et, rnd(pseed, uint(7)));
		rot.y = minmax(start_rotation_y, start_rotation_y_keys, et, rnd(pseed, uint(8)));
	}
	float flags = 0.0;
	if (rnd(pseed, uint(9)) < flip_rotation) {
		rot = -rot;
		flags += 16384.0;
	}
	vec4 col = minmax_gradient(start_color_mode, start_color_a, start_color_b, start_color_gradient_a, start_color_gradient_b, 0, 1, et, rnd(pseed, uint(10)));
	if (rnd(pseed, uint(11)) < flip.x) {
		flags += 1024.0;
	}
	if (rnd(pseed, uint(12)) < flip.y) {
		flags += 2048.0;
	}
	if (rnd(pseed, uint(13)) < flip.z) {
		flags += 4096.0;
	}
	if (mesh_count > 1) {
		flags += 8192.0 * floor(min(rnd(pseed, uint(14)) * float(mesh_count), float(mesh_count - 1)));
	}

	vec3 pos;
	vec3 dir;
	emit_shape(pseed, rank, cmax, pos, dir);
	if (sub_emitter_child) {
		// Unity: the sub-emitter's shape is placed at the parent particle (child simulation space).
		mat4 dsp0 = sim_space(EMISSION_TRANSFORM);
		pos += FLIP_Z * (safe_inverse(mat3(dsp0), basis_rotation(dsp0)) * (parent_world - dsp0[3].xyz));
		if ((sub_inherit & 4) != 0) {
			rot.z += parent_rot;
		}
	}
	if (sub_emulated) {
		mat4 dsp0 = sim_space(EMISSION_TRANSFORM);
		vec3 parent_at = (EMISSION_TRANSFORM * sub_parent_from_child)[3].xyz;
		pos += FLIP_Z * (safe_inverse(mat3(dsp0), basis_rotation(dsp0)) * (parent_at - dsp0[3].xyz));
		if ((sub_inherit & 4) != 0) {
			rot.z += minmax(sub_parent_rotation, sub_parent_rotation_keys, 0.0, rnd(pseed, uint(61)));
		}
	}
	if (emitter_path) {
		float pt = clamp(spawn / max(emitter_path_length, 0.0001), 0.0, 1.0);
		pos += vec3(eval_keys(emitter_path_x.x, emitter_path_x.y, pt), eval_keys(emitter_path_y.x, emitter_path_y.y, pt),
				eval_keys(emitter_path_z.x, emitter_path_z.y, pt));
	}
	if (shape_align_to_direction) {
		if (renderer_mode == 4 || (renderer_mode == 0 && (render_alignment == 1 || render_alignment == 2))) {
			// Oriented geometry: the particle's local +Z points along the emission direction (Unity
			// Quaternion.LookRotation(direction, up)), then the start rotation; written back as Unity Euler angles
			// (R = Ry * Rx * Rz) so the rest of the simulation keeps working with rot.
			vec3 fz = length(dir) > 0.0 ? normalize(dir) : vec3(0.0, 0.0, 1.0);
			vec3 up = abs(fz.y) > 0.9999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
			vec3 fx = normalize(cross(up, fz));
			mat3 look = mat3(fx, cross(fz, fx), fz);
			float zs = renderer_mode == 4 ? 1.0 : -1.0;
			mat3 m = look * rot_y(rot.y) * rot_x(rot.x) * rot_z(zs * rot.z);
			float ax = asin(clamp(-m[2][1], -1.0, 1.0));
			float ay = atan(m[2][0], m[2][2]);
			float az = atan(m[0][1], m[1][1]);
			rot = vec3(ax, ay, zs * az);
		} else {
			// Camera facing billboards: the Z rotation follows the emission direction (XY plane).
			rot.z += atan(dir.x, dir.y);
		}
	}

	USERDATA1 = vec4(pos, delay);
	USERDATA2 = vec4(dir * speed, life);
	USERDATA3 = vec4(uintBitsToFloat(packUnorm4x8(col)), rot);
	USERDATA4 = vec4(sz, visible ? 1.0 : 0.0);
	USERDATA5 = vec4(uintBitsToFloat(pseed), flags, 0.0, age0);
	USERDATA6 = vec4(spawn, rank, cmax, 0.0);
	if (distance_trail) {
		USERDATA6.xyz = parent_world;
	}

	TRANSFORM = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0));
	COLOR = vec4(0.0);
	CUSTOM = vec4(0.0);
	VELOCITY = vec3(0.0);
}

void process() {
	if (USERDATA4.w < 0.5) {
		ACTIVE = false;
	}
	float age_g = USERDATA5.w + DELTA;
	USERDATA5.w = age_g;
	// Unity simulation time of the particle.
	float a = (age_g - USERDATA1.w) * simulation_speed;
	float life = USERDATA2.w;
	// Unity (measured): a particle that reaches its lifetime exactly on a frame is still drawn that frame, and one
	// emitted on the frame its time is reached is drawn with age 0. Both clocks add the frame time in float32, so a
	// particle "exactly on a frame boundary" shows on the same frame as in Unity when the delays are compared exactly.
	if (a > life + 1e-4) {
		// Death sub-emitter: once, where the particle was on its last simulated frame.
		if (sub_emit_type == 2 && sub_emit_count > 0 && ACTIVE && USERDATA5.z > 0.0) {
			mat4 dsp_d = sim_space(EMISSION_TRANSFORM);
			vec3 wp = world_space ? to_godot(USERDATA1.xyz) : (dsp_d * vec4(to_godot(USERDATA1.xyz), 1.0)).xyz;
			mat4 xf = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(wp, 1.0));
			uint es = hash(floatBitsToUint(USERDATA5.x) + uint(977));
			int n_sub = sub_emit_count_min + int(floor(rnd(es, uint(70)) * float(sub_emit_count - sub_emit_count_min + 1)));
			for (int i = 0; i < min(n_sub, sub_emit_count); i++) {
				emit_subparticle(xf, vec3(0.0), vec4(1.0), vec4(USERDATA3.w, 0.0, 0.0, 0.0), FLAG_EMIT_POSITION | FLAG_EMIT_CUSTOM);
			}
		}
		ACTIVE = false;
	}

	if (a < 0.0 || !ACTIVE) {
		// Waiting for its spawn time (or dead): invisible.
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
		TRANSFORM[2] = vec4(0.0);
		COLOR.a = 0.0;
	} else {
		uint pseed = floatBitsToUint(USERDATA5.x);
		float flags = USERDATA5.y;
		float t = clamp(a / max(life, 0.0001), 0.0, 1.0);
		float a_prev = USERDATA5.z;
		float dt = max(a - a_prev, 0.0);
		// Unity integrates the motion modules with the age the particle had at the start of the step (measured with
		// a short velocity pulse: evaluating them at the end of the step loses most of it).
		float t0 = clamp(a_prev / max(life, 0.0001), 0.0, 1.0);
		USERDATA5.z = a;

		// Simulation space (Godot axes) and its Unity-axes linear part.
		mat4 e = EMISSION_TRANSFORM;
		mat4 dsp = sim_space(e);
		mat3 d3u = FLIP_Z * mat3(dsp) * FLIP_Z;
		mat3 d3u_inv = safe_inverse(d3u, FLIP_Z * basis_rotation(e) * FLIP_Z);
		// Unity-axes maps into the simulation space: from the system's local axes and from world axes.
		mat3 local_to_sim = world_space ? d3u : mat3(1.0);
		mat3 world_to_sim = world_space ? mat3(1.0) : d3u_inv;
		if (world_space && a_prev == 0.0) {
			// World simulation space: born where the emitter is now, then independent of it.
			USERDATA1.xyz = FLIP_Z * (dsp * vec4(to_godot(USERDATA1.xyz), 1.0)).xyz;
			USERDATA2.xyz = d3u * USERDATA2.xyz + inherit_velocity * (FLIP_Z * emitter_velocity);
		}

		// Integrate like Shuriken: forces into the velocity, then position += (velocity + animated velocity) * dt.
		vec3 v = USERDATA2.xyz;
		float gmod = minmax(gravity_modifier, gravity_modifier_keys, t0, rnd(pseed, uint(20)));
		v += world_to_sim * (gravity * gmod) * dt;
		if (force_over_lifetime) {
			vec3 fo = vec3(minmax(force_x, force_x_keys, t0, rnd(pseed, uint(55))),
					minmax(force_y, force_y_keys, t0, rnd(pseed, uint(56))),
					minmax(force_z, force_z_keys, t0, rnd(pseed, uint(57))));
			v += (force_world ? world_to_sim : local_to_sim) * fo * dt;
		}
		vec3 v_anim = vec3(0.0);
		float speed_mod = 1.0;
		if (velocity_over_lifetime) {
			v_anim = vec3(minmax(velocity_x, velocity_x_keys, t0, rnd(pseed, uint(21))),
					minmax(velocity_y, velocity_y_keys, t0, rnd(pseed, uint(22))),
					minmax(velocity_z, velocity_z_keys, t0, rnd(pseed, uint(23))));
			v_anim = (velocity_world ? world_to_sim : local_to_sim) * v_anim;
			speed_mod = minmax(velocity_speed_modifier, velocity_speed_modifier_keys, t0, rnd(pseed, uint(24)));
		}
		if (limit_velocity) {
			float drag = minmax(limit_drag, limit_drag_keys, t0, rnd(pseed, uint(77)));
			if (drag > 0.0) {
				float sp0 = length(v + v_anim);
				if (limit_drag_by_size) {
					drag *= max(USERDATA4.x, USERDATA4.y);
				}
				if (limit_drag_by_speed) {
					drag *= sp0;
				}
				float k = clamp(drag * dt, 0.0, 1.0);
				v *= 1.0 - k;
				v_anim *= 1.0 - k;
			}
			float lim = minmax(limit_magnitude, limit_magnitude_keys, t0, rnd(pseed, uint(25)));
			vec3 total = v + v_anim;
			float sp = length(total);
			if (sp > lim && sp > 0.0) {
				// Unity removes `dampen` of the excess speed per 1/30 s.
				float k = 1.0 - pow(1.0 - clamp(limit_dampen, 0.0, 1.0), dt * 30.0);
				float new_sp = mix(sp, lim, k);
				v *= new_sp / sp;
				v_anim *= new_sp / sp;
			}
		}
		vec3 pos = USERDATA1.xyz;
		vec3 pos_start = pos;
		// Not on the first simulated frame: Godot tested the collision at the slot's previous transform (the hidden
		// waiting particle, at the origin), not where the particle is born.
		if (collision && COLLIDED && a_prev > 0.0) {
			// Godot's collider pushed the particle (previous frame position): move it out along the normal and
			// reflect the velocity like Shuriken (bounce on the normal component, dampen on the speed).
			vec3 n = COLLISION_NORMAL;
			vec3 nu = world_space ? to_godot(n) : FLIP_Z * (inverse(mat3(dsp)) * n);
			nu = length(nu) > 0.0 ? normalize(nu) : vec3(0.0, 1.0, 0.0);
			vec3 push = world_space ? to_godot(n * COLLISION_DEPTH) : FLIP_Z * (inverse(mat3(dsp)) * (n * COLLISION_DEPTH));
			pos += push;
			float vn = dot(v, nu);
			if (vn < 0.0) {
				float bounce = minmax(collision_bounce, collision_bounce_keys, t, rnd(pseed, uint(62)));
				float dampen = minmax(collision_dampen, collision_dampen_keys, t, rnd(pseed, uint(63)));
				v = (v - (1.0 + bounce) * vn * nu) * (1.0 - clamp(dampen, 0.0, 1.0));
				float loss = minmax(collision_lifetime_loss, collision_lifetime_loss_keys, t, rnd(pseed, uint(64)));
				USERDATA2.w = max(life * (1.0 - loss), 0.0);
				// Collision sub-emitter: at the contact point, on every collision.
				if (sub_emit_type == 1 && sub_emit_count > 0) {
					vec3 wp = world_space ? to_godot(pos) : (dsp * vec4(to_godot(pos), 1.0)).xyz;
					mat4 xf = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(wp, 1.0));
					uint es = hash(pseed + floatBitsToUint(a));
					int n_sub = sub_emit_count_min + int(floor(rnd(es, uint(70)) * float(sub_emit_count - sub_emit_count_min + 1)));
					for (int i = 0; i < min(n_sub, sub_emit_count); i++) {
						emit_subparticle(xf, vec3(0.0), vec4(1.0), vec4(USERDATA3.w, 0.0, 0.0, 0.0), FLAG_EMIT_POSITION | FLAG_EMIT_CUSTOM);
					}
				}
			}
		}
		USERDATA2.xyz = v;
		vec3 vel = (v + v_anim) * speed_mod;
		pos += vel * dt;
		if (velocity_orbital) {
			// Orbit around the system's axes (centre = system origin + offset), then radial push.
			vec3 centre = vec3(minmax(orbital_offset_x, orbital_offset_x_keys, t0, rnd(pseed, uint(65))),
					minmax(orbital_offset_y, orbital_offset_y_keys, t0, rnd(pseed, uint(66))),
					minmax(orbital_offset_z, orbital_offset_z_keys, t0, rnd(pseed, uint(67))));
			vec3 origin = vec3(0.0);
			if (world_space) {
				origin = FLIP_Z * e[3].xyz;
				centre = d3u * centre;
			}
			vec3 rel = pos - origin - centre;
			vec3 w = vec3(minmax(orbital_x, orbital_x_keys, t0, rnd(pseed, uint(68))),
					minmax(orbital_y, orbital_y_keys, t0, rnd(pseed, uint(69))),
					minmax(orbital_z, orbital_z_keys, t0, rnd(pseed, uint(70)))) * speed_mod;
			mat3 to_local = world_space ? d3u_inv : mat3(1.0);
			mat3 from_local = world_space ? d3u : mat3(1.0);
			vec3 rl = to_local * rel;
			// Unity's left handed rotation (positive = clockwise looking down the axis).
			rl = rot_z(-w.z * dt) * (rot_y(-w.y * dt) * (rot_x(-w.x * dt) * rl));
			float rad = minmax(radial, radial_keys, t0, rnd(pseed, uint(71))) * speed_mod;
			if (rad != 0.0 && length(rl) > 1e-6) {
				rl += normalize(rl) * rad * dt;
			}
			pos = origin + centre + from_local * rl;
		}
		if (noise) {
			float scroll = minmax(noise_scroll_speed, noise_scroll_speed_keys, t0, rnd(pseed, uint(72)));
			float amount = minmax(noise_position_amount, noise_position_amount_keys, t0, rnd(pseed, uint(73)));
			vec3 sp = pos * noise_frequency + vec3(0.0, 0.0, scroll * (age_g - USERDATA1.w));
			vec3 nv = noise_field(sp);
			vec3 st = vec3(minmax(noise_strength_x, noise_strength_x_keys, t0, rnd(pseed, uint(74))));
			if (noise_separate_axes) {
				st.y = minmax(noise_strength_y, noise_strength_y_keys, t0, rnd(pseed, uint(75)));
				st.z = minmax(noise_strength_z, noise_strength_z_keys, t0, rnd(pseed, uint(76)));
			}
			pos += nv * st * amount * noise_velocity_scale * dt;
		}
		USERDATA1.xyz = pos;

		// Rotation (angular velocity, radians, Unity axes; z positive = clockwise).
		vec3 rot = USERDATA3.yzw;
		float rsign = mod(floor(flags / 16384.0), 2.0) > 0.5 ? -1.0 : 1.0;
		if (rotation_over_lifetime) {
			vec3 w = vec3(0.0, 0.0, minmax(rotation_z, rotation_z_keys, t, rnd(pseed, uint(26))));
			if (rotation_separate_axes) {
				w.x = minmax(rotation_x, rotation_x_keys, t, rnd(pseed, uint(27)));
				w.y = minmax(rotation_y, rotation_y_keys, t, rnd(pseed, uint(28)));
			}
			rot += w * rsign * dt;
		}
		if (rotation_by_speed) {
			float sn = clamp((length(vel) - rotation_by_speed_range.x) / max(rotation_by_speed_range.y - rotation_by_speed_range.x, 1e-6), 0.0, 1.0);
			rot.z += minmax(rotation_by_speed_z, rotation_by_speed_z_keys, sn, rnd(pseed, uint(29))) * rsign * dt;
		}
		USERDATA3.yzw = rot;

		// Birth sub-emitter: on the particle's first simulated frame.
		if (sub_emit_type == 0 && sub_emit_count > 0 && a_prev == 0.0) {
			vec3 wp = world_space ? to_godot(pos) : (dsp * vec4(to_godot(pos), 1.0)).xyz;
			mat4 xf = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(wp, 1.0));
			uint es = hash(pseed + uint(977));
			int n_sub = sub_emit_count_min + int(floor(rnd(es, uint(70)) * float(sub_emit_count - sub_emit_count_min + 1)));
			for (int i = 0; i < min(n_sub, sub_emit_count); i++) {
				emit_subparticle(xf, vec3(0.0), vec4(1.0), vec4(rot.z, 0.0, 0.0, 0.0), FLAG_EMIT_POSITION | FLAG_EMIT_CUSTOM);
			}
		}

		// Size.
		vec3 sz = USERDATA4.xyz;
		if (size_over_lifetime) {
			float r = rnd(pseed, uint(30));
			float kx = minmax(size_x, size_x_keys, t, r);
			if (size_separate_axes) {
				sz *= vec3(kx, minmax(size_y, size_y_keys, t, r), minmax(size_z, size_z_keys, t, r));
			} else {
				sz *= kx;
			}
		}

		// World matrix W of the particle (Godot axes).
		vec3 axis_len = vec3(length(dsp[0].xyz), length(dsp[1].xyz), length(dsp[2].xyz));
		vec3 wpos = world_space ? to_godot(pos) : (dsp * vec4(to_godot(pos), 1.0)).xyz;
		mat3 w3;
		float rot_out = rot.z;
		if (renderer_mode == 1) {
			// Stretched billboard: length along the velocity, width = size x.
			vec3 vw = world_space ? to_godot(vel) : mat3(dsp) * to_godot(vel);
			float speed = length(vw);
			vec3 d = speed > 0.0 ? vw / speed : vec3(0.0, 1.0, 0.0);
			float sx = sz.x * axis_len.x;
			float sy = sz.y * axis_len.y;
			float len = sy * length_scale + speed * velocity_scale;
			vec3 side = abs(d.y) < 0.99 ? normalize(cross(d, vec3(0.0, 1.0, 0.0))) : vec3(1.0, 0.0, 0.0);
			w3 = mat3(side * sx, d * len, normalize(cross(side, d)) * sy);
		} else if (renderer_mode == 4 || (renderer_mode == 0 && (render_alignment == 1 || render_alignment == 2)) || renderer_mode == 2) {
			// Oriented geometry: rotation * size.
			// Meshes: Unity Quaternion.Euler(x, y, z). Oriented billboards turn the other way on every axis (the
			// clockwise z of the camera facing ones, and x / y too: a billboard with start rotation x = 270 and local
			// alignment lies on the floor facing up in Unity, so it is visible from above with Cull Back).
			float rot_sign = renderer_mode == 4 ? 1.0 : -1.0;
			float rot_sign_z = rot_sign;
			mat3 ru = rot_y(rot_sign * rot.y) * rot_x(rot_sign * rot.x) * rot_z(rot_sign_z * rot.z);
			mat3 rg = FLIP_Z * ru * FLIP_Z;
			mat3 base = mat3(1.0);
			vec3 s = sz * axis_len;
			if (renderer_mode == 2) {
				// Horizontal billboard: lies on the world XZ plane, facing +Y; the render shader builds the
				// rotated corners (rotation in CUSTOM.x) and scales them along world X / Z.
				base = mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, s.y)) * rot_x(-PI * 0.5);
				rg = mat3(1.0);
				s = vec3(1.0);
			} else if (render_alignment == 2) {
				base = mat3(normalize(dsp[0].xyz), normalize(dsp[1].xyz), normalize(dsp[2].xyz));
			}
			w3 = base * rg * mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, s.z));
		} else {
			// Camera facing billboards: world axes scaled by the size (rotation in CUSTOM.x).
			vec3 s = sz * axis_len;
			w3 = mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, s.z));
			if (trail) {
				if (a_prev == 0.0 && !distance_trail) {
					USERDATA6.zw = vec2(0.0);
				}
				float step_len = length(pos - pos_start);
				float speed_now = dt > 0.0 ? step_len / dt : 0.0;
				float tl = max(minmax(trail_lifetime, trail_lifetime_keys, t0, rnd(pseed, uint(78))), 0.0001);
				if (!distance_trail) {
					USERDATA6.z += step_len;
					USERDATA6.w = a_prev == 0.0 ? speed_now : mix(USERDATA6.w, speed_now, clamp(dt / tl, 0.0, 1.0));
				}
				float len = min(USERDATA6.z, USERDATA6.w * tl);
				vec3 vw = world_space ? to_godot(vel) : mat3(dsp) * to_godot(vel);
				w3[2] = length(vw) > 1e-6 ? -normalize(vw) * len : vec3(0.0);
				if (distance_trail) {
					w3[2] = USERDATA6.xyz - wpos;
				}
			}
		}
		TRANSFORM = mat4(vec4(w3[0], 0.0), vec4(w3[1], 0.0), vec4(w3[2], 0.0), vec4(wpos, 1.0));
		if (draw_hidden) {
			TRANSFORM[0] = vec4(0.0);
			TRANSFORM[1] = vec4(0.0);
			TRANSFORM[2] = vec4(0.0);
		}

		// Color.
		vec4 col = unpackUnorm4x8(floatBitsToUint(USERDATA3.x));
		if (color_over_lifetime) {
			vec4 ga = eval_gradient(color_gradient_a, 2, t);
			if (color_mode == 3) {
				ga = mix(eval_gradient(color_gradient_b, 3, t), ga, rnd(pseed, uint(31)));
			}
			col *= ga;
		}
		COLOR = col;

		// Texture sheet animation: frame 0 is the first frame the particle shows.
		float frame = 0.0;
		if (texture_sheet) {
			int tiles = max(flipbook_tiles.x * flipbook_tiles.y, 1);
			int frames = sheet_animation == 1 ? max(flipbook_tiles.x, 1) : tiles;
			float tc = t * sheet_cycles;
			tc = tc - floor(tc);
			if (sheet_cycles <= 1.0) {
				tc = t;
			}
			float fr = rnd(pseed, uint(32));
			// Start frame is normalized (0..1) like the serialized Unity value; Unity wraps past the last frame.
			float sf = minmax(start_frame, start_frame_keys, 0.0, rnd(pseed, uint(33)));
			float fv = sf + minmax(frame_over_time, frame_over_time_keys, tc, fr);
			fv = fv - floor(fv);
			float f = min(floor(fv * float(frames)), float(frames - 1));
			if (sheet_animation == 1) {
				int row = sheet_row >= 0 ? sheet_row : int(floor(rnd(pseed, uint(34)) * float(max(flipbook_tiles.y, 1))));
				f += float(min(row, flipbook_tiles.y - 1) * flipbook_tiles.x);
			}
			frame = min(f, float(tiles - 1));
		}

		// Custom data streams. Unity evaluates the Custom Data module with the age the particle had at the
		// start of the frame (measured: one simulation step behind size/color), so it is reproduced here.
		float t_prev = clamp((a - DELTA * simulation_speed) / max(life, 0.0001), 0.0, 1.0);
		vec4 c1 = vec4(0.0);
		vec4 c2 = vec4(0.0);
		for (int i = 0; i < 4; i++) {
			c1[i] = minmax(custom1[i], custom1_keys[i], t_prev, rnd(pseed, uint(35 + i)));
			c2[i] = minmax(custom2[i], custom2_keys[i], t_prev, rnd(pseed, uint(39 + i)));
		}
		if (custom1_color_mode >= 0) {
			c1 = minmax_gradient(custom1_color_mode, custom1_color_a, custom1_color_b, custom1_gradient_a, custom1_gradient_b, 4, 5, t_prev, rnd(pseed, uint(35)));
		}
		CUSTOM = pack_custom(c1, c2, rot_out, frame + mod(flags, 16384.0));
	}
}
