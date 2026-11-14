#[compute]
#version 450

// Vefects - Unity URP 17 post processing (Bloom, Chromatic Aberration, Vignette, ACES tonemapping) for Godot.
// Translated from URP's Bloom.shader, UberPost.shader, Common.hlsl and core's ACES.hlsl / Color.hlsl / Filtering.hlsl.
// One shader, five passes (`mode`):
//   0 prefilter   full res color -> half res, 13-tap filter (High Quality) + soft threshold
//   1 blur H      2x downsample + 9-tap gaussian
//   2 blur V      5-tap (9-tap equivalent) gaussian
//   3 upsample    lerp(high mip, bicubic low mip, scatter)
//   4 uber        chromatic aberration, + bloom, vignette, ACES -> display linear in [0, 1]
//   5 copy        same size copy (texel centres)
// Godot images start at the top, Unity's at the bottom: every filter here is symmetric, so nothing is mirrored.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src_tex;
layout(set = 0, binding = 1) uniform sampler2D low_tex;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D dst_img;
layout(set = 0, binding = 3) uniform sampler2D lut_tex;

layout(push_constant, std430) uniform Params {
	vec2 src_size;
	vec2 low_size;
	vec2 dst_size;
	float mode;
	float scatter;
	float threshold;
	float knee;
	float clamp_max;
	float bloom_intensity;
	float chroma;
	float vig_intensity;
	float vig_smoothness;
	float vig_roundness;
	float flags; // 1 bloom, 2 high quality filtering, 4 ACES, 8 display LUT
	float pad;
} p;

vec3 src_at(vec2 uv) {
	vec2 texel = 1.0 / p.src_size;
	return textureLod(src_tex, min(uv, 1.0 - 0.5 * texel), 0.0).rgb;
}

// Filtering.hlsl SampleTexture2DBicubic (B-spline, 4 bilinear taps).
vec3 bicubic(sampler2D tex, vec2 uv, vec2 size) {
	vec2 xy = uv * size + 0.5;
	vec2 ic = floor(xy);
	vec2 fc = fract(xy);
	vec2 r = 0.16666667 + fc * (-0.5 + fc * (0.5 - fc * 0.16666667));
	vec2 mr = 0.66666667 + fc * (-1.0 + 0.5 * fc) * fc;
	vec2 ml = 0.16666667 + fc * (0.5 + fc * (0.5 - fc * 0.5));
	vec2 l = 1.0 - mr - ml - r;
	vec2 w0 = r + mr;
	vec2 w1 = ml + l;
	vec2 o0 = -1.0 + mr / w0;
	vec2 o1 = 1.0 + l / w1;
	vec2 inv = 1.0 / size;
	vec3 a = textureLod(tex, min((ic + vec2(o0.x, o0.y) - 0.5) * inv, vec2(1.0)), 0.0).rgb;
	vec3 b = textureLod(tex, min((ic + vec2(o1.x, o0.y) - 0.5) * inv, vec2(1.0)), 0.0).rgb;
	vec3 c = textureLod(tex, min((ic + vec2(o0.x, o1.y) - 0.5) * inv, vec2(1.0)), 0.0).rgb;
	vec3 d = textureLod(tex, min((ic + vec2(o1.x, o1.y) - 0.5) * inv, vec2(1.0)), 0.0).rgb;
	return w0.y * (w0.x * a + w1.x * b) + w1.y * (w0.x * c + w1.x * d);
}

// ----------------------------------------------------------------------------- ACES (URP AcesTonemap, not the full RRT/ODT)
// HLSL matrices are listed row by row; a GLSL mat3 built from the same list is their transpose, so v * M = mul(M_hlsl, v).
const mat3 sRGB_2_AP0 = mat3(0.4397010, 0.3829780, 0.1773350, 0.0897923, 0.8134230, 0.0967616, 0.0175440, 0.1115440, 0.8707040);
const mat3 AP0_2_AP1_MAT = mat3(1.4514393161, -0.2365107469, -0.2149285693, -0.0765537734, 1.1762296998, -0.0996759264, 0.0083161484, -0.0060324498, 0.9977163014);
const mat3 AP1_2_XYZ_MAT = mat3(0.6624541811, 0.1340042065, 0.1561876870, 0.2722287168, 0.6740817658, 0.0536895174, -0.0055746495, 0.0040607335, 1.0103391003);
const mat3 XYZ_2_AP1_MAT = mat3(1.6410233797, -0.3248032942, -0.2364246952, -0.6636628587, 1.6153315917, 0.0167563477, 0.0117218943, -0.0082844420, 0.9883948585);
const mat3 XYZ_2_REC709_MAT = mat3(3.2409699419, -1.5373831776, -0.4986107603, -0.9692436363, 1.8759675015, 0.0415550574, 0.0556300797, -0.2039769589, 1.0569715142);
const mat3 D60_2_D65_CAT = mat3(0.98722400, -0.00611327, 0.0159533, -0.00759836, 1.00186000, 0.0053302, 0.00307257, -0.00509595, 1.0816800);
const vec3 AP1_RGB2Y = vec3(0.272229, 0.674082, 0.0536895);
const float RRT_GLOW_GAIN = 0.05;
const float RRT_GLOW_MID = 0.08;
const float RRT_RED_SCALE = 0.82;
const float RRT_RED_PIVOT = 0.03;
const float RRT_RED_HUE = 0.0;
const float RRT_RED_WIDTH = 135.0;
const float RRT_SAT_FACTOR = 0.96;
const float ODT_SAT_FACTOR = 0.93;
const float DIM_SURROUND_GAMMA = 0.9811;
const float HALF_MAX = 65504.0;

float rgb_2_saturation(vec3 rgb) {
	float mi = min(min(rgb.r, rgb.g), rgb.b);
	float ma = max(max(rgb.r, rgb.g), rgb.b);
	return (max(ma, 1e-4) - max(mi, 1e-4)) / max(ma, 1e-2);
}

float rgb_2_yc(vec3 rgb) {
	float k = rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b);
	float chroma = sqrt(max(k, 0.0));
	return (rgb.b + rgb.g + rgb.r + 1.75 * chroma) / 3.0;
}

float rgb_2_hue(vec3 rgb) {
	float hue = 0.0;
	if (!(rgb.x == rgb.y && rgb.y == rgb.z)) {
		hue = (180.0 / 3.14159265359) * atan(sqrt(3.0) * (rgb.y - rgb.z), 2.0 * rgb.x - rgb.y - rgb.z);
	}
	if (hue < 0.0) {
		hue += 360.0;
	}
	return hue;
}

float center_hue(float hue, float center) {
	float h = hue - center;
	if (h < -180.0) {
		h += 360.0;
	} else if (h > 180.0) {
		h -= 360.0;
	}
	return h;
}

float sigmoid_shaper(float x) {
	float t = max(1.0 - abs(x / 2.0), 0.0);
	float y = 1.0 + (x >= 0.0 ? 1.0 : -1.0) * (1.0 - t * t);
	return y / 2.0;
}

float glow_fwd(float yc, float gain, float mid) {
	if (yc <= 2.0 / 3.0 * mid) {
		return gain;
	} else if (yc >= 2.0 * mid) {
		return 0.0;
	}
	return gain * (mid / yc - 1.0 / 2.0);
}

vec3 XYZ_2_xyY(vec3 XYZ) {
	float divisor = max(dot(XYZ, vec3(1.0)), 1e-4);
	return vec3(XYZ.xy / divisor, XYZ.y);
}

vec3 xyY_2_XYZ(vec3 xyY) {
	float m = xyY.z / max(xyY.y, 1e-4);
	vec3 XYZ = vec3(xyY.x, xyY.z, 1.0 - xyY.x - xyY.y);
	XYZ.xz *= m;
	return XYZ;
}

vec3 dark_to_dim_surround(vec3 linear_cv) {
	vec3 XYZ = linear_cv * AP1_2_XYZ_MAT;
	vec3 xyY = XYZ_2_xyY(XYZ);
	xyY.z = pow(clamp(xyY.z, 0.0, HALF_MAX), DIM_SURROUND_GAMMA);
	return xyY_2_XYZ(xyY) * XYZ_2_AP1_MAT;
}

vec3 aces_tonemap(vec3 color_linear) {
	vec3 aces = color_linear * sRGB_2_AP0;
	// Glow module.
	float saturation = rgb_2_saturation(aces);
	float yc = rgb_2_yc(aces);
	float s = sigmoid_shaper((saturation - 0.4) / 0.2);
	aces *= 1.0 + glow_fwd(yc, RRT_GLOW_GAIN * s, RRT_GLOW_MID);
	// Red modifier.
	float hue = center_hue(rgb_2_hue(aces), RRT_RED_HUE);
	float hw = smoothstep(0.0, 1.0, 1.0 - abs(2.0 * hue / RRT_RED_WIDTH));
	hw *= hw;
	aces.r += hw * saturation * (RRT_RED_PIVOT - aces.r) * (1.0 - RRT_RED_SCALE);
	// ACES to rendering space, global desaturation.
	vec3 acescg = max(vec3(0.0), aces * AP0_2_AP1_MAT);
	acescg = mix(vec3(dot(acescg, AP1_RGB2Y)), acescg, RRT_SAT_FACTOR);
	// RRT + ODT fit.
	const float a = 0.0245786;
	const float b = 0.000090537;
	const float c = 0.983729;
	const float d = 0.4329510;
	const float e = 0.238081;
	vec3 rgb_post = (acescg * (acescg + a) - b) / (acescg * (c * acescg + d) + e);
	vec3 linear_cv = dark_to_dim_surround(rgb_post);
	linear_cv = mix(vec3(dot(linear_cv, AP1_RGB2Y)), linear_cv, ODT_SAT_FACTOR);
	vec3 XYZ = linear_cv * AP1_2_XYZ_MAT;
	XYZ = XYZ * D60_2_D65_CAT;
	return XYZ * XYZ_2_REC709_MAT;
}

// URP LinearToLogC_Precise (ALEXA LogC EI 800), the input encoding of the display LUT.
vec3 linear_to_logc(vec3 x) {
	const float cut = 0.011361, a = 5.555556, b = 0.047996, c = 0.244161, d = 0.386036, e = 5.301883, f = 0.092819;
	vec3 o;
	for (int i = 0; i < 3; i++) {
		o[i] = x[i] > cut ? c * log(max(a * x[i] + b, 1e-10)) / log(10.0) + d : e * x[i] + f;
	}
	return o;
}

// 33^3 LUT stored as a 1089 x 33 strip (x = r + 33 b, y = g), trilinear.
vec3 apply_display_lut(vec3 color) {
	vec3 c = clamp(linear_to_logc(color), 0.0, 1.0) * 32.0;
	float b0 = min(floor(c.b), 31.0);
	float fb = c.b - b0;
	vec2 inv = vec2(1.0 / 1089.0, 1.0 / 33.0);
	vec2 uv0 = vec2(b0 * 33.0 + c.r + 0.5, c.g + 0.5) * inv;
	vec2 uv1 = vec2((b0 + 1.0) * 33.0 + c.r + 0.5, c.g + 0.5) * inv;
	return mix(textureLod(lut_tex, uv0, 0.0).rgb, textureLod(lut_tex, uv1, 0.0).rgb, fb);
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.dst_size.x) || px.y >= int(p.dst_size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / p.dst_size;
	int mode = int(p.mode + 0.5);
	int flags = int(p.flags + 0.5);
	vec3 color;
	if (mode == 0) {
		vec2 t = 1.0 / p.src_size;
		if ((flags & 2) != 0) {
			vec3 A = src_at(uv + t * vec2(-1.0, -1.0));
			vec3 B = src_at(uv + t * vec2(0.0, -1.0));
			vec3 C = src_at(uv + t * vec2(1.0, -1.0));
			vec3 D = src_at(uv + t * vec2(-0.5, -0.5));
			vec3 E = src_at(uv + t * vec2(0.5, -0.5));
			vec3 F = src_at(uv + t * vec2(-1.0, 0.0));
			vec3 G = src_at(uv);
			vec3 H = src_at(uv + t * vec2(1.0, 0.0));
			vec3 I = src_at(uv + t * vec2(-0.5, 0.5));
			vec3 J = src_at(uv + t * vec2(0.5, 0.5));
			vec3 K = src_at(uv + t * vec2(-1.0, 1.0));
			vec3 L = src_at(uv + t * vec2(0.0, 1.0));
			vec3 M = src_at(uv + t * vec2(1.0, 1.0));
			vec2 div = (1.0 / 4.0) * vec2(0.5, 0.125);
			color = (D + E + I + J) * div.x;
			color += (A + B + G + F) * div.y;
			color += (B + C + H + G) * div.y;
			color += (F + G + L + K) * div.y;
			color += (G + H + M + L) * div.y;
		} else {
			color = src_at(uv);
		}
		color = min(vec3(p.clamp_max), color);
		float brightness = max(max(color.r, color.g), color.b);
		float softness = clamp(brightness - p.threshold + p.knee, 0.0, 2.0 * p.knee);
		softness = (softness * softness) / (4.0 * p.knee + 1e-4);
		float multiplier = max(brightness - p.threshold, softness) / max(brightness, 1e-4);
		color = max(color * multiplier, vec3(0.0));
	} else if (mode == 1) {
		vec2 t = 2.0 / p.src_size;
		const float w[9] = float[](0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703, 0.19459459, 0.12162162, 0.05405405, 0.01621622);
		color = vec3(0.0);
		for (int i = 0; i < 9; i++) {
			color += w[i] * textureLod(src_tex, min(uv + vec2(t.x * float(i - 4), 0.0), 1.0 - 0.5 * t), 0.0).rgb;
		}
	} else if (mode == 2) {
		vec2 t = 1.0 / p.src_size;
		color = 0.07027027 * textureLod(src_tex, min(uv - vec2(0.0, t.y * 3.23076923), 1.0 - 0.5 * t), 0.0).rgb
				+ 0.31621622 * textureLod(src_tex, min(uv - vec2(0.0, t.y * 1.38461538), 1.0 - 0.5 * t), 0.0).rgb
				+ 0.22702703 * textureLod(src_tex, min(uv, 1.0 - 0.5 * t), 0.0).rgb
				+ 0.31621622 * textureLod(src_tex, min(uv + vec2(0.0, t.y * 1.38461538), 1.0 - 0.5 * t), 0.0).rgb
				+ 0.07027027 * textureLod(src_tex, min(uv + vec2(0.0, t.y * 3.23076923), 1.0 - 0.5 * t), 0.0).rgb;
	} else if (mode == 5) {
		color = textureLod(src_tex, uv, 0.0).rgb;
	} else if (mode == 3) {
		vec3 high = textureLod(src_tex, uv, 0.0).rgb;
		vec3 low = (flags & 2) != 0 ? bicubic(low_tex, uv, p.low_size) : textureLod(low_tex, uv, 0.0).rgb;
		color = mix(high, low, p.scatter);
	} else {
		color = src_at(uv);
		if (p.chroma > 0.0) {
			vec2 coords = 2.0 * uv - 1.0;
			vec2 end = uv - coords * dot(coords, coords) * p.chroma;
			vec2 delta = (end - uv) / 3.0;
			color = vec3(color.r, src_at(delta + uv).g, src_at(delta * 2.0 + uv).b);
		}
		if ((flags & 1) != 0) {
			vec2 bt = 1.0 / p.low_size;
			vec2 ub = min(uv, 1.0 - 0.5 * bt);
			vec3 bloom = (flags & 2) != 0 ? bicubic(low_tex, ub, p.low_size) : textureLod(low_tex, ub, 0.0).rgb;
			color += bloom * p.bloom_intensity;
		}
		if (p.vig_intensity > 0.0) {
			vec2 dist = abs(uv - 0.5) * p.vig_intensity;
			dist.x *= p.vig_roundness;
			float vf = pow(clamp(1.0 - dot(dist, dist), 0.0, 1.0), p.vig_smoothness);
			color *= vf;
		}
		if ((flags & 8) != 0) {
			color = apply_display_lut(color);
		} else if ((flags & 4) != 0) {
			color = clamp(aces_tonemap(color), 0.0, 1.0);
		}
	}
	imageStore(dst_img, px, vec4(color, 1.0));
}
