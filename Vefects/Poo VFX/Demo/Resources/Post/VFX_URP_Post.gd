@tool
extends CompositorEffect
## Vefects - Unity URP post processing for Godot (Forward+ / Mobile): Bloom, Chromatic Aberration, Vignette and
## tonemapping / color grading, run with the same passes and constants as URP 17 (see VFX_URP_Post.glsl).
## Tonemapping and grading come from `display_lut`: URP's whole display transform measured in Unity (one render
## per entry of a 33^3 LogC grid through the scene's volume profile), so it matches whatever URP does there; without
## a LUT, `tonemap_aces` applies the port of URP's AcesTonemap.
##
## It runs after the transparent pass, on the HDR image, and writes the tonemapped display values: the scene's
## Environment must keep Godot's own post effects neutral (tonemap Linear, glow off, no adjustments), which the demo
## scenes of the pack do. Anti-aliasing (SMAA / FXAA) still runs afterwards, like in URP.

@export_group("Bloom")
@export var bloom_enabled := true
## URP Bloom Threshold (gamma space, as in the URP inspector).
@export var bloom_threshold := 1.0
@export var bloom_intensity := 1.0
@export_range(0.0, 1.0) var bloom_scatter := 0.7
@export var bloom_clamp := 65472.0
@export var bloom_high_quality_filtering := true
@export_range(2, 8) var bloom_max_iterations := 6
## URP Bloom Skip Iterations: the smallest mips of the pyramid that are left out.
@export_range(0, 16) var bloom_skip_iterations := 1
@export_group("Chromatic Aberration")
@export_range(0.0, 1.0) var chromatic_aberration := 0.0
@export_group("Vignette")
@export_range(0.0, 1.0) var vignette_intensity := 0.0
@export_range(0.01, 1.0) var vignette_smoothness := 0.2
@export_group("Tonemapping")
## Unity URP display transform as a 33^3 LUT (EXR strip 1089 x 33: entry (r, g, b) at x = r + 33 b, y = g; LogC input).
@export var display_lut: Texture2D
## URP Tonemapping mode ACES (used when there is no display_lut).
@export var tonemap_aces := true

const SHADER_PATH := "res://Vefects/Poo VFX/Demo/Resources/Post/VFX_URP_Post.glsl"
const CONTEXT := &"vefects_urp_post"

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_initialize)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		if _sampler.is_valid():
			_rd.free_rid(_sampler)
		if _shader.is_valid():
			_rd.free_rid(_shader)


func _initialize() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var file := load(SHADER_PATH) as RDShaderFile
	if file == null:
		push_error("VFX_URP_Post: cannot load " + SHADER_PATH)
		return
	_shader = _rd.shader_create_from_spirv(file.get_spirv())
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)


func _tex(rsb: RenderSceneBuffersRD, tex_name: StringName, size: Vector2i) -> RID:
	if rsb.has_texture(CONTEXT, tex_name):
		var f := rsb.get_texture_format(CONTEXT, tex_name)
		if f.width == size.x and f.height == size.y:
			return rsb.get_texture(CONTEXT, tex_name)
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return rsb.create_texture(CONTEXT, tex_name, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)


func _pass(mode: int, src: RID, src_size: Vector2i, low: RID, low_size: Vector2i, dst: RID, dst_size: Vector2i, extra: PackedFloat32Array, lut := RID()) -> void:
	var u_src := RDUniform.new()
	u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_src.binding = 0
	u_src.add_id(_sampler)
	u_src.add_id(src)
	var u_low := RDUniform.new()
	u_low.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_low.binding = 1
	u_low.add_id(_sampler)
	u_low.add_id(low)
	var u_dst := RDUniform.new()
	u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_dst.binding = 2
	u_dst.add_id(dst)
	var u_lut := RDUniform.new()
	u_lut.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_lut.binding = 3
	u_lut.add_id(_sampler)
	u_lut.add_id(lut if lut.is_valid() else low)
	var set_rid := UniformSetCacheRD.get_cache(_shader, 0, [u_src, u_low, u_dst, u_lut])
	var pc := PackedFloat32Array([src_size.x, src_size.y, low_size.x, low_size.y, dst_size.x, dst_size.y, mode])
	pc.append_array(extra)
	var bytes := pc.to_byte_array()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, set_rid, 0)
	_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
	_rd.compute_list_dispatch(cl, (dst_size.x + 7) / 8, (dst_size.y + 7) / 8, 1)
	_rd.compute_list_end()


func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid():
		return
	var rsb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if rsb == null:
		return
	var size := rsb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	# URP: the pyramid starts at half resolution; iterations = floor(log2(max size) - 1), clamped to Max Iterations.
	var tw := maxi(1, size.x >> 1)
	var th := maxi(1, size.y >> 1)
	var mips := clampi(int(floor(log(float(maxi(tw, th))) / log(2.0) - 1.0)) - bloom_skip_iterations, 1, bloom_max_iterations)
	var threshold := _gamma_to_linear(bloom_threshold)
	var scatter := lerpf(0.05, 0.95, bloom_scatter)
	var lut_rid := RID()
	if display_lut:
		lut_rid = RenderingServer.texture_get_rd_texture(display_lut.get_rid())
	var flags := (1 if bloom_enabled else 0) + (2 if bloom_high_quality_filtering else 0) + (4 if tonemap_aces else 0) 			+ (8 if lut_rid.is_valid() else 0)
	var params := PackedFloat32Array([scatter, threshold, threshold * 0.5, bloom_clamp, bloom_intensity,
			chromatic_aberration * 0.05, vignette_intensity * 3.0, vignette_smoothness * 5.0, 1.0, flags, 0.0])
	var sizes: Array[Vector2i] = []
	for i in mips:
		sizes.append(Vector2i(maxi(1, tw >> i), maxi(1, th >> i)))
	for view in rsb.get_view_count():
		var color := rsb.get_color_layer(view)
		var copy := _tex(rsb, &"source", size)
		_pass(5, color, size, color, size, copy, size, params)
		var down: Array[RID] = []
		var up: Array[RID] = []
		for i in mips:
			down.append(_tex(rsb, StringName("down%d" % i), sizes[i]))
			up.append(_tex(rsb, StringName("up%d" % i), sizes[i]))
		var bloom := copy
		var bloom_size := size
		if bloom_enabled:
			_pass(0, copy, size, copy, size, down[0], sizes[0], params)
			for i in range(1, mips):
				_pass(1, down[i - 1], sizes[i - 1], down[i - 1], sizes[i - 1], up[i], sizes[i], params)
				_pass(2, up[i], sizes[i], up[i], sizes[i], down[i], sizes[i], params)
			for i in range(mips - 2, -1, -1):
				var low := down[i + 1] if i == mips - 2 else up[i + 1]
				_pass(3, down[i], sizes[i], low, sizes[i + 1], up[i], sizes[i], params)
			bloom = up[0] if mips > 1 else down[0]
			bloom_size = sizes[0]
		_pass(4, copy, size, bloom, bloom_size, color, size, params, lut_rid)


func _gamma_to_linear(v: float) -> float:
	# Unity Mathf.GammaToLinearSpace (sRGB curve).
	if v <= 0.04045:
		return v / 12.92
	return pow((v + 0.055) / 1.055, 2.4)
