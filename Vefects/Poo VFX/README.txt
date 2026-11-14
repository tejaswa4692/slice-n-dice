VEFECTS - POO VFX for GODOT
Version 1.0.3

20 stylized poo effects: floor splats (radial and directional, single, rotated, random bunches, and "GS_Pure"
grayscale versions you can tint with the particle color), goo splashes (one shot, looping, and versions that splat on
the floor where the drops land), drips with a puddle, an animated goo blob with a bubbling sound loop, a goo stream
mesh and a demo projectile that orbits and leaves a trail of splats. Includes the demo scene of the original pack.


REQUIREMENTS
------------
- Godot 4.7 or newer.
- Renderer: Forward+ (recommended).


INSTALLATION
------------
1. Copy the "Vefects" folder into the root of your Godot project (res://).
   The pack must stay at res://Vefects/Poo VFX/.
2. Open the project and let Godot import the files (the first import takes a few minutes).
3. Recommended: Project > Project Settings > Rendering > Textures >
   Anisotropic Filtering Level = 8x
   so the effects stay sharp when seen at grazing angles, as in the original pack.

The Demo Project download already includes this setting and opens the demo scene.


DEMO
----
Open res://Vefects/Poo VFX/Demo/VFX_Demo.tscn and press F6 (Run Current Scene).
  Left / Right (or A / D)  change effect
  Space (or R)             replay
  Right mouse drag         orbit the camera
  Mouse wheel              zoom

The scene res://Vefects/Poo VFX/Demo/Scenes/Poo VFX URP.tscn shows every effect at once.
The demo and overview scenes need the Forward+ or Mobile renderer (their post processing).


USING THE EFFECTS
-----------------
Drag any effect scene into your scene, or instance it from code:

    var fx := preload("res://Vefects/Poo VFX/<path to the effect>.tscn").instantiate()
    add_child(fx)
    fx.global_position = hit_position

The _Loop effects and the goo meshes loop; the other effects play once. VFX_Poorojectile_01_Demo moves its goo
with Demo/Scripts/Demo_TurningAround.gd and its splash drops inherit that motion (Shared/Scripts/VFX_Inherit_Velocity.gd).
The demo scene uses Demo/Resources/Post/VFX_URP_Post.gd (a Compositor effect) to reproduce the bloom, tonemapping and
color grading of the original Unity scene; the effects do not need it.
Effects are GPUParticles3D nodes and play automatically when they enter the scene tree.
To play an effect again, call restart() on its GPUParticles3D nodes, or instance the scene again.
VFX_Poo_Goo_01 and VFX_Poorojectile_01_Demo play a looping bubbling sound (AudioStreamPlayer3D, SFX/).

To play, pause, stop or restart many effects at once, attach Shared/Scripts/Vefects_VFX_Controller.gd to any parent node
(an effect's root, a group of effects) and use the Play, Pause / Resume, Stop and Restart buttons in the
Inspector, in the editor and in game; from code call play(), pause(), stop() and restart() on that node.
Auto Replay restarts every particle system under it every Replay Interval seconds, one-shot effects included.


FOLDERS
-------
  VFX/Particles/                    the effects (VFX_Poo_*.tscn, VFX_Poorojectile_01_Demo.tscn)
  VFX/Materials/, VFX/Textures/, VFX/Meshes/   materials (ShaderMaterial; *_Mesh.tres = for regular meshes), textures, meshes
  SFX/                             the goo bubbling sound
  Shared/Shaders/                  shaders (one .gdshaderinc per shader + one .gdshader per variant)
  Shared/Scripts/                  helper scripts
  Demo/Scenes/                     the demo scene of the pack
  Demo/Resources/                  demo environment (sky, floor, lighting, post processing, effect layouts)
  Demo/                            demo scene


CUSTOMIZING
-----------
The effects use the shaders of Shared/Shaders/ (Poo_Splat_01 and Poo_Debris_01_Lit for splats and drips, Poo_Goo_Splash_01 for the
splashes, Poo_Goo_01 and Poo_Goo_Stream_01 for the opaque goo meshes). All of them are lit. Each shader is written
once in a .gdshaderinc file; the .gdshader files next to it only choose its blend mode and culling, and the _Mesh
versions draw regular meshes (MeshInstance3D) instead of particles.
Duplicate a material and change its LUT, colors, smoothness or normal intensity, then assign it to a duplicated
effect scene (Material Override of the GPUParticles3D node). The GS_Pure effects use a grayscale LUT: change the
Start Color of their particles to get any color. The splashes and drips collide with GPUParticlesCollision nodes: the
demo adds a box collider for the floor; add colliders to your level so the splats appear where the drops land. Each
texture slot has a "_sampling" setting (clamp U, clamp V, sRGB) matching the texture it holds.
The particle settings of each effect are in the process material of its GPUParticles3D node
(Inspector > Process Material).


SUPPORT
-------
Join our Discord server: https://discord.gg/VeRbY8kMaD
Questions: info@vefects.com
More info about our products: https://vefects.com/
Instagram: https://www.instagram.com/vefects/
X / Twitter: https://twitter.com/vefects/
LinkedIn: https://www.linkedin.com/company/vefects
YouTube: https://www.youtube.com/channel/UCC8Ookxa2TOdCoKRT4wLcbA/videos

Have fun! :)
