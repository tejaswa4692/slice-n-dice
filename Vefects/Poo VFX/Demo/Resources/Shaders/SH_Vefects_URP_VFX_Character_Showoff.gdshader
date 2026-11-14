// Vefects - port of the Amplify shader "Vefects/SH_Vefects_URP_VFX_Character_Showoff" (URP Lit, specular setup) of the
// demo character (Vexa). Opaque, cull back, no alpha test.
// A fresnel term (1 - N.V, shaped by power / multiply / bias) picks the silhouette edges. The edges are broken up by a
// noise texture projected on the object's XY plane (world position relative to the object pivot, so the pattern
// follows the character), offset by the edge mask * noise_depth and scrolled over time. The masked noise blends the
// base color towards the edges color and also lights the edges through emission.
// Smoothness = smoothness, Specular = specular (gray), flat normal. Lighting: VFX_URP_Lit.gdshaderinc.
// Godot world = Unity world with z negated: positions are converted to Unity axes before building the noise uv.
shader_type spatial;
render_mode cull_back;

#include "res://Vefects/Poo VFX/Demo/Resources/Shaders/VFX_URP_Lit.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 edges_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float emission_intensity = 1.0;
uniform float smoothness = 0.0;
uniform float specular = 0.0;
uniform float edges_power = 1.0;
uniform float edges_multiply = 1.0;
uniform float edges_bias = 0.0;
/** 0 = plain base color, 1 = base color blended towards the edges color by the noisy edge mask. */
uniform float base_color_edges_lerp = 0.0;
/** xy: tiling of the object-space XY noise projection. */
uniform vec4 world_noise_tiling = vec4(1.0, 1.0, 0.0, 0.0);
/** xy: noise scroll speed (uv per second). */
uniform vec4 world_noise_speed = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D noise_edges_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
/** How much the edge mask pushes the noise uv (fakes depth on the silhouette). */
uniform float noise_depth = 0.0;

// pow() with a base that can reach 0 (HLSL returns 0 there, GLSL leaves it undefined).
float safe_pow(float base, float exponent) {
	return base <= 0.0 ? 0.0 : pow(base, exponent);
}

void fragment() {
	// Fresnel edge mask. N.V is the same in any space, so the view-space vectors are used directly.
	float n_dot_v = dot(NORMAL, VIEW);
	float fresnel = clamp(safe_pow(1.0 - clamp(n_dot_v, 0.0, 1.0), edges_power), 0.0, 1.0);
	float edges = clamp(clamp(clamp(fresnel * edges_multiply, 0.0, 1.0) + edges_bias, 0.0, 1.0), 0.0, 1.0);

	// World position relative to the object pivot, in Unity axes (x, y, -z).
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local_offset = world_pos - MODEL_MATRIX[3].xyz;
	local_offset.z = -local_offset.z;

	// Noise uv on the XY plane, pushed by the edge mask, scrolled over time.
	vec2 noise_uv = TIME * world_noise_speed.xy + (local_offset.xy + edges * noise_depth) * world_noise_tiling.xy;
	float noise = texture(noise_edges_texture, vec2(noise_uv.x, 1.0 - noise_uv.y)).r;
	float edges_noise = edges * noise;

	vec4 edges_tint = mix(base_color, edges_color, edges_noise);
	vec3 base = mix(base_color, edges_tint, base_color_edges_lerp).rgb;
	vec3 edges_emission = (edges_color * edges_noise * emission_intensity).rgb;

	// URP specular setup: diffuse = albedo * (1 - max(specular)).
	float reflectivity = specular;
	vec3 diffuse = base * (1.0 - reflectivity);
	URP_LIT(diffuse, vec3(specular), clamp(smoothness, 0.0, 1.0), reflectivity);
	EMISSION += edges_emission;
}
