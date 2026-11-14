// Vefects - SH_Vefects_VFX_URP_Poo_Goo_01: opaque lit, back faces culled.
shader_type spatial;
render_mode skip_vertex_transform, depth_draw_opaque, cull_back;

#define VFX_NO_SCENE_DEPTH
#define VFX_LIT
#include "res://Vefects/Poo VFX/Shared/Shaders/SH_Vefects_VFX_URP_Poo_Goo_01.gdshaderinc"
