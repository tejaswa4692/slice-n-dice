// Vefects - Unity URP "Lit" material with a base map and a normal map (metallic workflow, opaque): the grid floor of
// the demo environment. Lighting: VFX_URP_Lit.gdshaderinc.
shader_type spatial;
render_mode cull_back;

#include "res://Vefects/Poo VFX/Demo/Resources/Shaders/VFX_URP_Lit.gdshaderinc"

/** _BaseColor, linear. */
uniform vec3 base_color = vec3(1.0);
/** _BaseMap (sRGB) and its tiling / offset (_BaseMap_ST, shared by every map like URP). */
uniform sampler2D base_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_map_st = vec4(1.0, 1.0, 0.0, 0.0);
/** _BumpMap (Unity normal map: tangent space, 0..1 encoded) and _BumpScale. */
uniform sampler2D bump_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_bump_map = false;
uniform float bump_scale = 1.0;
uniform float metallic = 0.0;
uniform float smoothness = 0.5;

void fragment() {
	// The meshes store Godot UVs (u, 1 - v): tile / offset in Unity's UV space, then back to Godot's.
	vec2 uv = vec2(UV.x, 1.0 - UV.y) * base_map_st.xy + base_map_st.zw;
	uv = vec2(uv.x, 1.0 - uv.y);
	vec3 base = base_color * texture(base_map, uv).rgb;
	if (use_bump_map) {
		vec3 n = texture(bump_map, uv).rgb * 2.0 - 1.0;
		n.xy *= bump_scale;
		n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
		NORMAL = normalize(TANGENT * n.x + BINORMAL * n.y + NORMAL * n.z);
	}
	// URP metallic workflow: kDielectricSpec = 0.04; one minus reflectivity = 0.96 * (1 - metallic).
	float one_minus_reflectivity = 0.96 * (1.0 - metallic);
	vec3 diffuse = base * one_minus_reflectivity;
	vec3 spec = mix(vec3(0.04), base, metallic);
	URP_LIT(diffuse, spec, smoothness, 1.0 - one_minus_reflectivity);
}
