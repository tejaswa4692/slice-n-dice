// Vefects - SH_Vefects_VFX_URP_Poo_Debris_01_Lit (Unity URP Lit, specular setup, Amplify Shader Editor), Forward pass.
// Lit poo debris and drips (billboard and mesh particles): the particle color is tinted by a LUT read with the
// (distorted, panning) erosion texture, the erosion texture and the opacity mask shape the blob, and a normal texture
// gives it the wet, glossy relief.
//
// Distortion: distortion texture (uv * noise_distortion_uvs + pan), rg remapped to -1..1 * distortion_intensity / 100, displaces the
// erosion and normal UVs.
//
// Color: erosion texture green channel (optionally eroded / multiplied by the eroded opacity mask / inverted, by the
// LUT toggles) * lut_amplitude + lut_offset, panned by lut_speed, picks the LUT color. That color goes through a hue
// shift (constant + animated), a value multiplier and a desaturation (lut_desaturate), is multiplied by the
// particle color, and flat_color blends the result back to the plain particle color.
//
// Opacity: eroded erosion texture (erosion_intensity + TEXCOORD0.z, smoothness erosion_smoothness - TEXCOORD0.w)
// * eroded opacity mask * depth fade * opacity_multiply * particle alpha.
//
// Normal: the graph feeds the raw normal texture color (no UnpackNormal; the textures are imported as regular sRGB
// color textures, so the sample is linearized like in Unity) faded in from the flat normal (0, 0, 1) by
// normal_intensity * opacity, as a tangent space normal. That vector is reproduced as is
// (T * n.x + B * n.y + N * n.z, normalized like URP) instead of going through NORMAL_MAP, which would rebuild z.
//
// Lighting: Godot's lighting (not URP's BRDF). URP specular setup with a grey specular color = specular and
// Metallic 0: the reflectance at normal incidence (F0) is `specular` and the diffuse color is
// base color * (1 - specular). Godot's dielectric F0 is 0.16 * SPECULAR^2, so SPECULAR = sqrt(specular / 0.16)
// and ALBEDO = base color * (1 - specular) give the same split (the materials of the pack use specular 0.001:
// almost no reflections, the gloss comes from the light highlights). Roughness from the URP smoothness
// (smoothness) through vfx_urp_roughness. Emission = base color * emission_multiply.
//
// screen_space_reflections / screen_space_reflections_contribute_transparent are URP material toggles without
// any effect on the graph; in Godot screen space reflections are an Environment setting.
//
// Vertex streams: TEXCOORD0.xy = particle UV, TEXCOORD0.z = erosion offset, TEXCOORD0.w = erosion smoothness offset
// (the effects of the pack use the default streams: z = 0, w = 1), COLOR = particle color.
// Render state (blend / cull) is set by the variant .gdshader files that include this one.

uniform float flat_color = 0.0;
/** URP specular color (grey): reflectance at normal incidence, also removed from the diffuse color. */
uniform float specular = 1.0;
uniform float smoothness = 1.0;
uniform float emission_multiply = 0.0;
uniform float opacity_multiply = 1.0;
uniform float depth_fade = 0.0;

group_uniforms LUT;
uniform sampler2D lut : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 lut_sampling = ivec3(0, 0, 1);
uniform float lut_amplitude = 1.0;
uniform float lut_offset = 0.0;
uniform float lut_speed = 0.0;
uniform float lut_hue_shift = 0.0;
uniform float lut_hue_shift_speed = 0.0;
uniform float lut_desaturate = 0.0;
uniform float lut_value_intensity = 1.0;
/** Toggles (Unity shader keywords _LUTERODES_ON, _LUTERODESMASKS_ON, _LUTINVERT_ON): on when > 0.5. */
uniform float lut_erodes = 0.0;
uniform float lut_erodes_masks = 0.0;
uniform float lut_invert = 0.0;
group_uniforms;

group_uniforms Normal;
uniform sampler2D normal_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 normal_texture_sampling = ivec3(0, 0, 1);
uniform float normal_intensity = 1.0;
group_uniforms;

group_uniforms Distortion;
uniform sampler2D distortion_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 distortion_texture_sampling = ivec3(0, 0, 1);
uniform vec4 noise_distortion_uvs = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 noise_distortion_uv_pan = vec4(0.0, 0.0, 0.0, 0.0);
uniform float distortion_intensity = 0.1;
group_uniforms;

group_uniforms Erosion;
uniform sampler2D erosion_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 erosion_texture_sampling = ivec3(0, 0, 1);
uniform vec4 erosion_uvs = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 erosion_uv_pan = vec4(0.0, 0.0, 0.0, 0.0);
uniform float erosion_intensity = 0.0;
uniform float erosion_smoothness = 1.0;
group_uniforms;

group_uniforms Opacity_Mask;
uniform sampler2D opacity_mask : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 opacity_mask_sampling = ivec3(0, 0, 1);
uniform vec4 opacity_mask_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform float opacity_mask_erosion = 0.0;
uniform float opacity_mask_erosion_smoothness = 1.0;
group_uniforms;

group_uniforms Screen_Space_Reflections;
/** URP material toggles, no effect on the shader (Godot: Environment > SSR). */
uniform float screen_space_reflections = 1.0;
uniform float screen_space_reflections_contribute_transparent = 1.0;
group_uniforms;

#include "res://Vefects/Poo VFX/Shared/Shaders/VFX_Unity_Common.gdshaderinc"

/** Amplify HSVToRGB. */
vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

/** Amplify RGBToHSV. */
vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

/** HLSL smoothstep: also defined when edge0 >= edge1 (GLSL leaves that undefined). Equal edges give a hard step
 *  (0 at the edge itself, as saturate(NaN) on the GPU). With the default particle vertex streams TEXCOORD0.w is 1,
 *  so the erosion edges are equal with the default erosion_smoothness of 1. */
float hlsl_smoothstep(float edge0, float edge1, float x) {
	if (edge0 == edge1) {
		return x > edge0 ? 1.0 : 0.0;
	}
	float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

/** normalize() that keeps a fallback direction for a zero vector. */
vec3 poo_safe_normalize(vec3 v, vec3 fallback) {
	float len = length(v);
	return len > 1e-6 ? v / len : fallback;
}

void fragment() {
	vec2 uv = vfx_tc0.xy;

	// Distortion of the erosion / normal UVs: (rg - 0.5) * 2 * intensity / 100.
	vec2 distortion_uv = TIME * noise_distortion_uv_pan.xy + uv * noise_distortion_uvs.xy;
	vec2 distortion = (vfx_sample(distortion_texture, distortion_uv, distortion_texture_sampling).rg - 0.5) * 2.0 * (distortion_intensity * 0.01);
	vec2 erosion_uv = TIME * erosion_uv_pan.xy + uv * erosion_uvs.xy + distortion;

	// Erosion.
	float erosion_value = clamp(vfx_sample(erosion_texture, erosion_uv, erosion_texture_sampling).g, 0.0, 1.0);
	float erosion = erosion_intensity + vfx_tc0.z;
	float eroded = clamp(hlsl_smoothstep(erosion, erosion + (erosion_smoothness - vfx_tc0.w), erosion_value), 0.0, 1.0);

	// Opacity mask, eroded.
	float mask_value = clamp(vfx_sample(opacity_mask, uv * opacity_mask_st.xy + opacity_mask_st.zw, opacity_mask_sampling).g, 0.0, 1.0);
	float mask = clamp(hlsl_smoothstep(opacity_mask_erosion, opacity_mask_erosion + opacity_mask_erosion_smoothness, mask_value), 0.0, 1.0);
	float shape = clamp(eroded * mask, 0.0, 1.0);

	// LUT coordinate.
	float lut_coord = lut_erodes > 0.5 ? eroded : erosion_value;
	if (lut_erodes_masks > 0.5) {
		lut_coord = shape;
	}
	if (lut_invert > 0.5) {
		lut_coord = 1.0 - lut_coord;
	}
	vec2 lut_uv = TIME * vec2(lut_speed) + vec2(lut_coord * lut_amplitude + lut_offset);

	// LUT color: hue shift, value multiplier, desaturation, particle color.
	vec3 hsv = rgb_to_hsv(vfx_sample(lut, lut_uv, lut_sampling).rgb);
	vec3 lut_color = hsv_to_rgb(vec3(hsv.x + lut_hue_shift + TIME * lut_hue_shift_speed, hsv.y, hsv.z * lut_value_intensity));
	lut_color = mix(lut_color, vec3(dot(lut_color, vec3(0.299, 0.587, 0.114))), lut_desaturate);
	vec3 particle_color = vfx_color.rgb;
	vec3 base_color = mix(lut_color * particle_color, particle_color, flat_color);

	// Opacity.
	float depth = vfx_depth_fade(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, depth_fade);
	float opacity = clamp(clamp(clamp(shape * depth, 0.0, 1.0) * opacity_multiply, 0.0, 1.0) * vfx_color.a, 0.0, 1.0);

	// Tangent space normal: flat normal faded towards the raw normal texture color.
	vec3 normal_raw = vfx_sample(normal_texture, erosion_uv, normal_texture_sampling).rgb;
	vec3 normal_ts = mix(vec3(0.0, 0.0, 1.0), normal_raw, clamp(normal_intensity * opacity, 0.0, 1.0));
	NORMAL = poo_safe_normalize(TANGENT * normal_ts.x + BINORMAL * normal_ts.y + NORMAL * normal_ts.z, NORMAL);

	// URP specular setup: F0 = specular, diffuse = base color * (1 - specular).
	float reflectance = clamp(specular, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = sqrt(reflectance / 0.16);
	ROUGHNESS = vfx_urp_roughness(smoothness);
	EMISSION = base_color * emission_multiply;
	VFX_OUTPUT(base_color * (1.0 - reflectance), opacity);
}
