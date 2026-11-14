// Vefects - port of the Amplify shader "/_Vefects_/SH_Vefects_Grid_01" (URP Lit, specular setup) of the demo floor.
// Smoothness = lerp(_RoughnessMin, _RoughnessMax, texture.g) (the Amplify graph names them roughness, URP reads them
// as smoothness), Specular = _Specular (gray), normal = lerp((0, 0, 1), unpacked normal, _NormalIntensity) in tangent
// space. The parallax node of the graph has a zero offset (no effect). Lighting: VFX_URP_Lit.gdshaderinc.
// The meshes store Godot UVs (u, 1 - v): textures are sampled at the same texels as Unity.
shader_type spatial;
render_mode cull_back;

#include "res://Vefects/Poo VFX/Demo/Resources/Shaders/VFX_URP_Lit.gdshaderinc"

uniform sampler2D masks : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_overall = 200.0;
uniform float tile_x = 1.0;
uniform float tile_y = 1.0;
uniform float texture_tile_overall = 1.0;
uniform float masks_tile_overall = 1.0;
uniform float normal_intensity = 1.0;
/** Smoothness at texture.g = 0 / 1 (Unity "Roughness Min / Max"). */
uniform float roughness_min = 0.0;
uniform float roughness_max = 1.0;
uniform float specular = 0.01;
/** Linear (Unity converts the sRGB material colors when it uploads them). */
uniform vec3 color_overall = vec3(1.0);
uniform vec3 color_01 = vec3(1.0);
uniform vec3 color_02 = vec3(1.0);
uniform float random_tile_colors_max = 1.0;

void fragment() {
	vec2 uv = UV * tile_overall * vec2(tile_x, tile_y);
	vec4 t = texture(texture_map, uv * texture_tile_overall);
	vec4 m = texture(masks, uv * masks_tile_overall);
	float l65 = mix(0.0, random_tile_colors_max, clamp(m.b, 0.0, 1.0));
	vec3 c57 = mix(color_01, color_02, clamp(m.r, 0.0, 1.0) * l65);
	vec3 base = t.r * c57 * color_overall;
	vec2 nxy = texture(normal_map, uv).rg * 2.0 - 1.0;
	vec3 nt = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
	nt = mix(vec3(0.0, 0.0, 1.0), nt, normal_intensity);
	NORMAL = normalize(TANGENT * nt.x + BINORMAL * nt.y + NORMAL * nt.z);
	// URP specular setup: diffuse = albedo * (1 - max(specular)).
	float reflectivity = specular;
	vec3 diffuse = base * (1.0 - reflectivity);
	URP_LIT(diffuse, vec3(specular), mix(roughness_min, roughness_max, t.g), reflectivity);
}
