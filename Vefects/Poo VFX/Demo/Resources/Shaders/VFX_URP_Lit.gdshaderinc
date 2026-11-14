// Vefects - Unity URP 17 "Lit" lighting (UniversalFragmentPBR) for Godot spatial shaders of the demo environment.
// Direct light (light()): URP's LightingPhysicallyBased: radiance = light * attenuation * NdotL, brdf = diffuse +
// specular * DirectBRDFSpecular (URP's minimalist CookTorrance, no Fresnel). Godot's LIGHT_COLOR carries a PI factor
// for its own BRDFs: URP's light color is LIGHT_COLOR / PI.
// Indirect light: the flat ambient color * diffuse is Godot's own ambient light (Environment ambient color; ALBEDO is
// URP's brdf diffuse), so Godot's SSAO darkens it like URP's SSAO does; the reflection probe (the HDRI panorama,
// sampled at URP's mip for the roughness) * EnvironmentBRDFSpecular goes to EMISSION (Godot's own reflections are off
// in the Environment).
// Usage in fragment(): set NORMAL (view space, perturbed), then URP_LIT(brdf diffuse, specular color, smoothness,
// reflectivity); it sets ALBEDO, EMISSION and the values light() needs.

uniform sampler2D urp_reflection : filter_linear_mipmap, repeat_enable, hint_default_black;
/** Reflection probe intensity multiplier (* Environment reflections intensity). */
uniform float urp_reflection_intensity = 1.0;
/** log2(panorama width / (4 * probe cube resolution)): panorama mip of cube mip 0. */
uniform float urp_reflection_lod_offset = 2.0;

varying vec3 urp_specular;
varying float urp_roughness;
varying float urp_roughness2;

vec2 urp_pano_uv(vec3 d) {
	// Godot panorama convention (SKY_COORDS): u = atan(x, -z) / 2pi, v = acos(y) / pi.
	float u = atan(d.x, -d.z) / TAU;
	u = u < 0.0 ? u + 1.0 : u;
	return vec2(u, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

float urp_roughness_of(float smoothness) {
	float pr = 1.0 - smoothness;
	return max(pr * pr, 0.0078125);
}

vec3 urp_indirect(vec3 brdf_diffuse, vec3 brdf_specular, float smoothness, float reflectivity, vec3 n_view, vec3 v_view, mat4 inv_view) {
	float pr = 1.0 - smoothness;
	float r = urp_roughness_of(smoothness);
	float r2 = max(r * r, 6.103515625e-5);
	vec3 n = normalize((inv_view * vec4(n_view, 0.0)).xyz);
	vec3 v = normalize((inv_view * vec4(v_view, 0.0)).xyz);
	vec3 refl = reflect(-v, n);
	float no_v = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - no_v, 4.0);
	float grazing = clamp(smoothness + reflectivity, 0.0, 1.0);
	float mip = pr * (1.7 - 0.7 * pr) * 6.0;
	vec3 env = textureLod(urp_reflection, urp_pano_uv(refl), mip + urp_reflection_lod_offset).rgb * urp_reflection_intensity;
	vec3 env_brdf = (1.0 / (r2 + 1.0)) * mix(brdf_specular, vec3(grazing), fresnel);
	return env * env_brdf;
}

#define URP_LIT(diffuse, spec, smoothness, reflectivity) 	urp_specular = (spec); 	urp_roughness = urp_roughness_of(smoothness); 	urp_roughness2 = max(urp_roughness * urp_roughness, 6.103515625e-5); 	ALBEDO = (diffuse); 	EMISSION = urp_indirect((diffuse), (spec), (smoothness), (reflectivity), NORMAL, VIEW, INV_VIEW_MATRIX)

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 radiance = LIGHT_COLOR / PI * ATTENUATION * n_dot_l;
	DIFFUSE_LIGHT += radiance;
	vec3 h = normalize(LIGHT + VIEW);
	float no_h = clamp(dot(NORMAL, h), 0.0, 1.0);
	float lo_h = clamp(dot(LIGHT, h), 0.0, 1.0);
	float d = no_h * no_h * (urp_roughness2 - 1.0) + 1.00001;
	float spec_term = urp_roughness2 / ((d * d) * max(0.1, lo_h * lo_h) * (urp_roughness * 4.0 + 2.0));
	SPECULAR_LIGHT += urp_specular * spec_term * radiance;
}
