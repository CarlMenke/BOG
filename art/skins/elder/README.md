# The Elder's robe and hat

The first skin (D-099): a clothing mesh on the BOG's skeleton, worn by
`ElderRobe.don` while a BOG is the Elder and dropped as a pickup when it dies.

- `robe.res` — the mesh, 2 497 vertices, four influences each, bound by bone
  name to `mixamorig_Hips`, `Spine`, `Spine1`, `Spine2`, `Neck`, `Head`,
  `LeftUpLeg` and `RightUpLeg`.
- `robe.tscn` — a root with the `Elder` mesh under it, which is what the game
  instances.
- `robe_material.tres` — the purple, with `elder_basecolor.png` and
  `elder_emissive.png` beside it (D-037's textures).

Rebuilt by `tools/refit_robe.gd` from `art/generated/elder.glb`'s geometry;
`tools/preview_elder.tscn` is the picture and the bind check.
