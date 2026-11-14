// Vefects - Unity URP "Lit" material without textures (metallic workflow, opaque): the metal props and the Vexa model of the demo
// environment (its FBX embedded materials). Lighting: VFX_URP_Lit.gdshaderinc.
shader_type spatial;
render_mode cull_back;

#include "res://Vefects/Poo VFX/Demo/Resources/Shaders/VFX_URP_Lit.gdshaderinc"

/** _BaseColor, linear. */
uniform vec3 base_color = vec3(1.0);
uniform float metallic = 0.0;
uniform float smoothness = 0.5;

void fragment() {
	// URP metallic workflow: kDielectricSpec = 0.04; one minus reflectivity = 0.96 * (1 - metallic).
	float one_minus_reflectivity = 0.96 * (1.0 - metallic);
	vec3 diffuse = base_color * one_minus_reflectivity;
	vec3 spec = mix(vec3(0.04), base_color, metallic);
	URP_LIT(diffuse, spec, smoothness, 1.0 - one_minus_reflectivity);
}
