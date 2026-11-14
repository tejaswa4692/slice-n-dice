shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;
uniform vec4 color : source_color = vec4(0.6, 0.9, 1.0, 1.0);
uniform float progress: hint_range(0.0, 1.0) = 0.0;
uniform float trail = 0.5;
uniform float intensity = 3.0;
varying float arc;
void vertex() {
	arc = atan(-VERTEX.z, VERTEX.x) / PI;
}
void fragment() {
	float d = progress - (1.0 - arc);
	float mask = step(0.0, d) * (1.0 - clamp(d / trail, 0.0, 1.0));
	mask = pow(mask, 1.5);
	ALBEDO = color.rgb * intensity;
	ALPHA = mask;
}