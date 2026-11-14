// Vefects - SH_Vefects_VFX_URP_Poo_Goo_Splash_01 (Unity URP Lit, specular setup, Amplify Shader Editor), Forward pass.
// Lit goo splash: a noise texture (its UV wobbled by a panning distortion noise) gives the color ramp, the gloss and
// the eroded shape of the splash, a normal texture read at the same UV gives the wet relief, and a fresnel rim adds
// a little emissive glow.
//
// Color: the green channel of the noise picks between color02 and color01, the brightest values (> 0.9) blend
// towards color03, and the lower part of the noise (pow(g, 3) < 0.5) is darkened to 70%. A hue shift is applied last.
// Smoothness goes from smoothness_min to smoothness_max with the same "bright noise" factor.
//
// Opacity: the noise is eroded by a radial gradient (distance from the UV center, 0.3 per unit of the [-1, 1]
// remapped UV) plus the particle erosion TEXCOORD0.z, with a smoothstep of width erosion_smoothness. The particle
// color is not used by the graph (neither color nor alpha).
//
// Normal: the graph feeds the raw normal texture color (no UnpackNormal; the texture is imported as a regular sRGB
// color texture, so the sample is linearized like in Unity) faded in from the flat normal (0, 0, 1) by
// normal_intensity, as a tangent space normal. That vector is reproduced as is (T * n.x + B * n.y + N * n.z,
// normalized like URP) instead of going through NORMAL_MAP, which would rebuild z.
//
// Emission: color_fresnel * saturate(bias + scale * pow(1 - N.V, power)) * emission, with N the (unnormalized)
// normal of the normal texture, as the Amplify Fresnel node computes it.
//
// Lighting: Godot's lighting (not URP's BRDF). URP specular setup with a scalar specular color: METALLIC = 0, the
// Godot SPECULAR is chosen so that its dielectric F0 (0.16 * SPECULAR^2) equals the Unity specular value, and the
// albedo keeps URP's (1 - specular) diffuse energy factor. Roughness from the URP smoothness (vfx_urp_roughness).
//
// Vertex streams: TEXCOORD0.xy = particle UV, TEXCOORD0.z = erosion (Custom1.x in the effects of the pack).
// Render state (blend / cull) is set by the variant .gdshader files that include this one.

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
uniform float erosion_smoothness = 0.1;
group_uniforms;

group_uniforms Reflections;
/** URP screen space reflection toggles of the material. Godot's screen space reflections are an Environment
 *  setting (and never apply to transparent surfaces), so they are not read here. */
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

/** HLSL smoothstep: also defined when edge0 >= edge1 (GLSL leaves that undefined). Equal edges
 *  (erosion_smoothness 0) give a hard step (0 at the edge itself, as saturate(NaN) on the GPU). */
float hlsl_smoothstep(float edge0, float edge1, float x) {
	if (edge0 == edge1) {
		return x > edge0 ? 1.0 : 0.0;
	}
	float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

/** normalize() that keeps a fallback direction for a zero vector. */
vec3 goo_safe_normalize(vec3 v, vec3 fallback) {
	float len = length(v);
	return len > 1e-6 ? v / len : fallback;
}

void fragment() {
	vec2 uv = vfx_tc0.xy;

	// Distortion: the green channel of the panning noise, remapped to [-1, 1], offsets both UV axes alike.
	vec2 distortion_uv = TIME * noise_texture_distortion_pan.xy + uv * noise_texture_distortion_scale.xy;
	float distortion = mix(-1.0, 1.0, vfx_sample(noise_texture_distortion, distortion_uv, noise_texture_distortion_sampling).g);
	vec2 noise_uv = uv + mix(vec2(0.0), vec2(distortion), noise_distortion_lerp);

	// Color ramp from the noise.
	float noise = vfx_sample(noise_texture, noise_uv, noise_texture_sampling).g;
	vec3 color = mix(color02.rgb, color01.rgb, noise);
	color = mix(color, color03.rgb, clamp((noise - 0.9) / 2.0, 0.0, 1.0));
	float bright = clamp((vfx_pow(noise, 3.0) - 0.5) * 2.0, 0.0, 1.0);
	color = mix(color * 0.7, color, bright);
	vec3 hsv = rgb_to_hsv(color);
	vec3 base_color = hsv_to_rgb(vec3(hsv.x + hue_shift, hsv.y, hsv.z));

	// Tangent space normal: flat normal faded towards the raw normal texture color.
	vec3 normal_raw = vfx_sample(noise_texture_normal, noise_uv, noise_texture_normal_sampling).rgb;
	vec3 normal_ts = mix(vec3(0.0, 0.0, 1.0), normal_raw, normal_intensity);
	vec3 normal_view = TANGENT * normal_ts.x + BINORMAL * normal_ts.y + NORMAL * normal_ts.z;

	// Fresnel rim (Amplify Fresnel node, tangent space normal transformed but not normalized).
	vec3 view_dir = normalize(-VERTEX);
	float fresnel_ndotv = dot(normal_view, view_dir);
	float fresnel = fresnel_bias + fresnel_scale * vfx_pow(max(1.0 - fresnel_ndotv, 0.0001), fresnel_power);
	vec3 emission_color = mix(vec3(0.0), color_fresnel.rgb, clamp(fresnel, 0.0, 1.0)) * emission;

	// Opacity: noise eroded by a radial gradient from the UV center plus the particle erosion.
	float radial = clamp(length(vec2(-1.0) + uv * 2.0) * 0.3, 0.0, 1.0);
	float erosion = vfx_tc0.z + radial;
	float opacity = hlsl_smoothstep(erosion, erosion + erosion_smoothness, noise);

	NORMAL = goo_safe_normalize(normal_view, NORMAL);

	// URP specular setup: F0 = specular, diffuse = albedo * (1 - specular).
	float reflectivity = clamp(specular, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = clamp(sqrt(reflectivity / 0.16), 0.0, 1.0);
	ROUGHNESS = vfx_urp_roughness(mix(smoothness_min, smoothness_max, bright));
	EMISSION = emission_color;
	VFX_OUTPUT(base_color * (1.0 - reflectivity), opacity);
}
