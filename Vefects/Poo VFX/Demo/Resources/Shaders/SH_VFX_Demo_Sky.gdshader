// Vefects - sky of the demo scenes: the skybox material of the Unity scene (sun = the scene's
// Directional Light), exported from Unity as a panorama. The URP Lit materials of the demo read that panorama for
// their reflections (VFX_URP_Lit.gdshaderinc); the ambient light is the scene's flat color, set in the Environment.
shader_type sky;

uniform sampler2D panorama : filter_linear, repeat_enable, hint_default_black;

void sky() {
	COLOR = texture(panorama, SKY_COORDS).rgb;
}
