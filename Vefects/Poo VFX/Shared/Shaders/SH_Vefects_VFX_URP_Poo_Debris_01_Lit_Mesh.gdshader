// Vefects - SH_Vefects_VFX_URP_Poo_Debris_01_Lit: alpha blended, back faces culled, regular meshes (MeshInstance3D).
shader_type spatial;
render_mode skip_vertex_transform, depth_draw_never, blend_mix, cull_back;

#define VFX_STATIC_MESH
#define VFX_LIT
#include "res://Vefects/Poo VFX/Shared/Shaders/SH_Vefects_VFX_URP_Poo_Debris_01_Lit.gdshaderinc"
