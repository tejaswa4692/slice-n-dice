// Vefects - SH_Vefects_VFX_URP_Poo_Goo_Stream_01 (Unity URP Lit, specular setup, Amplify Shader Editor), Forward pass.
// Opaque lit goo stream (a falling column of goo). A panning noise (its UVs distorted by a second panning noise) drives everything:
//
// Color: green channel of the noise lerps color02 -> color01, its brightest values (> 0.9) push towards color03,
// the darker half is dimmed to 70 % (pow(g, 3) ramp), then a hue shift. The same ramp lerps the URP smoothness
// between smoothness_min and smoothness_max.
//
// Normal: the graph feeds the raw normal texture color (no UnpackNormal; the texture is imported as a regular sRGB
// color texture, so the sample is linearized like in Unity) faded in from the flat normal (0, 0, 1) by
// normal_intensity, as a tangent space normal. That vector is reproduced as is (T * n.x + B * n.y + N * n.z,
// normalized like URP) instead of going through NORMAL_MAP, which would rebuild z.
//
// Emission: fresnel rim (bias + scale * pow(1 - N.V, power), with the same unnormalized tangent space normal)
// tints color_fresnel, times emission.
//
// Vertex offset (object space): the vertex is pushed along its normal by the same distorted noise, remapped to
// [wpo_min, wpo_max] * wpo_intensity1. On top of that the stream bobs along object y with sin(TIME * wpo_sine_time)
// remapped from [-1, 1] to [-1, -0.1], * wpo_sine_intensity, faded out at both ends of the UV v range (mask
// saturate(3 * v * (1 - v)), eroded by wpo_band_erosion / wpo_band_erosion_smoothness).
// Collapse: the offset is lerped from object_pos * wpo_collapse_width (with the default -1 the vertex is pulled to the
// object origin) to the offset above by saturate((1 - v) + wpo_collapse_lerp * 2 - 1): 0 keeps the whole stream
// collapsed, 1 shows all of it, values in between grow it from the v = 0 end towards the v = 1 end.
//
// Lighting: Godot's lighting (not URP's BRDF). URP specular setup with a grey specular color: Godot's dielectric F0 is
// 0.16 * SPECULAR^2, so SPECULAR = sqrt(specular / 0.16); metallic 0, roughness from the URP smoothness.
// screen_space_reflections / screen_space_reflections_contribute_transparent are URP renderer toggles kept for
// material compatibility; Godot's SSR is an Environment setting.
//
// Vertex data: TEXCOORD0.xy = UV, object space normal (vertex offset). No scene depth / screen texture.
// Render state (opaque, back faces culled) is set by the variant .gdshader files that include this one.

uniform vec4 color01 : source_color = vec4(0.3960784, 0.4352941, 0.09019608, 1.0);
uniform vec4 color02 : source_color = vec4(0.3098039, 0.372549, 0.1294118, 1.0);
uniform vec4 color03 : source_color = vec4(0.9882354, 0.9843138, 0.2705882, 1.0);
uniform vec4 color_fresnel : source_color = vec4(0.08235294, 0.8901961, 0.8313726, 1.0);
uniform float hue_shift = 0.0;
uniform float emission = 0.1;
uniform float specular = 0.01;
uniform float smoothness_min = 0.5;
uniform float smoothness_max = 0.96;

group_uniforms Noise;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 noise_texture_sampling = ivec3(0, 0, 1);
uniform vec4 noise_texture_scale = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 noise_texture_pan = vec4(0.03, -0.1, 0.0, 0.0);
group_uniforms;

group_uniforms Normal;
uniform sampler2D noise_texture_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 noise_texture_normal_sampling = ivec3(0, 0, 1);
uniform float normal_intensity = 1.0;
group_uniforms;

group_uniforms Distortion;
uniform sampler2D noise_texture_distortion : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform ivec3 noise_texture_distortion_sampling = ivec3(0, 0, 1);
uniform vec4 noise_texture_distortion_scale = vec4(0.5, 0.5, 0.0, 0.0);
uniform vec4 noise_texture_distortion_pan = vec4(-0.05, -0.1, 0.0, 0.0);
uniform float noise_distortion_lerp = 0.03;
group_uniforms;

group_uniforms Fresnel;
uniform float fresnel_scale = 1.0;
uniform float fresnel_power = 3.0;
uniform float fresnel_bias = 0.0;
group_uniforms;

group_uniforms Vertex_Offset;
uniform float wpo_intensity1 = 0.1;
uniform float wpo_sine_time = 1.0;
uniform float wpo_sine_intensity = 0.333;
uniform float wpo_min = -0.3;
uniform float wpo_max = 0.3;
uniform float wpo_band_erosion = 0.0;
uniform float wpo_band_erosion_smoothness = 1.0;
uniform float wpo_collapse_width = -1.0;
uniform float wpo_collapse_lerp : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

group_uniforms Reflections;
/** URP toggles (Screen Space Reflections), not used by Godot. */
uniform float screen_space_reflections = 1.0;
uniform float screen_space_reflections_contribute_transparent = 1.0;
group_uniforms;

/** vfx_sample() at mip 0 (Amplify tex2Dlod), usable in vertex(). s.x / s.y: clamp U / V, s.z: sRGB. */
vec4 goo_sample_lod(sampler2D tex, vec2 uv_unity, ivec3 s) {
	vec2 uv = uv_unity;
	if (s.x != 0 || s.y != 0) {
		vec2 h = 0.5 / vec2(textureSize(tex, 0));
		if (s.x != 0) {
			uv.x = clamp(uv.x, h.x, 1.0 - h.x);
		}
		if (s.y != 0) {
			uv.y = clamp(uv.y, h.y, 1.0 - h.y);
		}
	}
	vec4 c = textureLod(tex, vec2(uv.x, 1.0 - uv.y), 0.0);
	if (s.z != 0) {
		c.rgb = mix(c.rgb / 12.92, pow((c.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c.rgb));
	}
	return c;
}

/** HLSL smoothstep: also defined when edge0 >= edge1 (equal edges give a hard step). */
float goo_smoothstep(float edge0, float edge1, float x) {
	if (edge0 == edge1) {
		return x > edge0 ? 1.0 : 0.0;
	}
	float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

/** Panned noise UV, distorted by the panned distortion noise (green channel remapped to [-1, 1]). */
vec2 goo_noise_uv(vec2 uv, float distortion_g) {
	vec2 noise_uv = TIME * noise_texture_pan.xy + uv * noise_texture_scale.xy;
	return noise_uv + mix(vec2(0.0), vec2(mix(-1.0, 1.0, distortion_g)), noise_distortion_lerp);
}

vec2 goo_distortion_uv(vec2 uv) {
	return TIME * noise_texture_distortion_pan.xy + uv * noise_texture_distortion_scale.xy;
}

/** Fades the vertex offset out at both ends of the UV v range. */
float goo_band_mask(float v) {
	float band = clamp(clamp(clamp(abs(1.0 - v), 0.0, 1.0) * clamp(abs(v), 0.0, 1.0), 0.0, 1.0) * 3.0, 0.0, 1.0);
	return clamp(goo_smoothstep(wpo_band_erosion, wpo_band_erosion + wpo_band_erosion_smoothness, band), 0.0, 1.0);
}

#define VFX_VERTEX_OFFSET
vec3 vfx_vertex_offset(vec3 object_pos, vec3 object_normal, vec4 tc0, vec4 tc1, vec4 tc2, vec4 color) {
	vec2 uv = tc0.xy;
	float distortion_g = goo_sample_lod(noise_texture_distortion, goo_distortion_uv(uv), noise_texture_distortion_sampling).g;
	float noise_g = goo_sample_lod(noise_texture, goo_noise_uv(uv, distortion_g), noise_texture_sampling).g;
	float band = goo_band_mask(uv.y);
	vec3 offset = object_normal * (mix(wpo_min, wpo_max, noise_g) * wpo_intensity1);
	float sine = -1.0 + (sin(TIME * wpo_sine_time) + 1.0) * 0.9 / 2.0;
	offset.y += sine * wpo_sine_intensity * band;
	float collapse = clamp((1.0 - uv.y) + (-1.0 + wpo_collapse_lerp * 2.0), 0.0, 1.0);
	return mix(object_pos * wpo_collapse_width, offset, collapse);
}

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

void fragment() {
	vec2 uv = vfx_tc0.xy;

	// Distorted, panning noise.
	float distortion_g = vfx_sample(noise_texture_distortion, goo_distortion_uv(uv), noise_texture_distortion_sampling).g;
	vec2 noise_uv = goo_noise_uv(uv, distortion_g);
	float noise_g = vfx_sample(noise_texture, noise_uv, noise_texture_sampling).g;

	// Color: three tones, darker half dimmed, hue shift.
	vec3 tone = mix(color02.rgb, color01.rgb, noise_g);
	tone = mix(tone, color03.rgb, clamp((noise_g - 0.9) / 2.0, 0.0, 1.0));
	float ramp = clamp((vfx_pow(noise_g, 3.0) - 0.5) * 2.0, 0.0, 1.0);
	vec3 hsv = rgb_to_hsv(mix(tone * 0.7, tone, ramp));
	vec3 base_color = hsv_to_rgb(vec3(hsv.x + hue_shift, hsv.y, hsv.z));

	// Tangent space normal: flat normal faded towards the raw normal texture color (view space basis).
	vec3 normal_ts = mix(vec3(0.0, 0.0, 1.0), vfx_sample(noise_texture_normal, noise_uv, noise_texture_normal_sampling).rgb, normal_intensity);
	vec3 normal_tbn = TANGENT * normal_ts.x + BINORMAL * normal_ts.y + NORMAL * normal_ts.z;

	// Fresnel rim emission (unnormalized normal, like the graph).
	float fresnel = fresnel_bias + fresnel_scale * pow(max(1.0 - dot(normal_tbn, VIEW), 0.0001), fresnel_power);
	vec3 rim = mix(vec3(0.0), color_fresnel.rgb, clamp(fresnel, 0.0, 1.0));

	float normal_len = length(normal_tbn);
	NORMAL = normal_len > 1e-6 ? normal_tbn / normal_len : NORMAL;
	ALBEDO = base_color;
	METALLIC = 0.0;
	SPECULAR = clamp(sqrt(max(specular, 0.0) / 0.16), 0.0, 1.0);
	ROUGHNESS = vfx_urp_roughness(mix(smoothness_min, smoothness_max, ramp));
	EMISSION = rim * emission;
}
