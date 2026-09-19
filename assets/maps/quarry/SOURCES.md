# Twin Quarry — downloaded source textures

Everything here is **CC0 1.0 Universal** (public domain dedication): no
attribution required, commercial use permitted, redistribution in this
repository permitted. Listed anyway, because "where did this come from" is a
question worth never having to guess at — the same table `assets/maps/wharf`
keeps, for the same reason.

| set | files | source | licence |
|---|---|---|---|
| Quarry Wall 02 | `quarry_wall_02_{diff,nor_gl,rough}_2k.jpg` | [Poly Haven](https://polyhaven.com/a/quarry_wall_02) | CC0 |
| Large Sandstone Blocks 01 | `large_sandstone_blocks_01_{diff,nor_gl,rough}_1k.jpg` | [Poly Haven](https://polyhaven.com/a/large_sandstone_blocks_01) | CC0 |
| Gravel Floor 03 | `gravel_floor_03_{diff,nor_gl,rough}_1k.jpg` | [Poly Haven](https://polyhaven.com/a/gravel_floor_03) | CC0 |
| Weathered Planks | `weathered_planks_{diff,nor_gl,rough}_1k.jpg` | [Poly Haven](https://polyhaven.com/a/weathered_planks) | CC0 |
| Corrugated Iron 02 | `corrugated_iron_02_{diff,nor_gl,rough}_1k.jpg` | [Poly Haven](https://polyhaven.com/a/corrugated_iron_02) | CC0 |
| Rusty Metal 02 | `rusty_metal_02_{diff,nor_gl,rough}_1k.jpg` | [Poly Haven](https://polyhaven.com/a/rusty_metal_02) | CC0 |

Eighteen files, 19 MB. The `nor_gl` variant is the one Godot wants (OpenGL /
Y+ green channel); `nor_dx` would light every drill hole as a bump.

## Why these six, and why at these sizes

**`quarry_wall_02` is the map.** The rim, the shaft walls, the monolith and the
three columns are between them most of every frame a player has, and they are
all one rock, so that rock is the only set here that gets 2k: 2048 px over the
5 m tile `QUARRY_FACE`/`FACE_TILE` sets is 410 px/m, and a Bog standing at the
cliff is looking at grain rather than at magnified blur. It was picked over
`rock_face_03` and `rock_wall_10` because it is *bedded* — horizontal seams and
blocky joints, photographed off a working face — which is exactly the read the
old procedural drill-line generator was drawing by hand and losing.

**`large_sandstone_blocks_01` is everything somebody cut.** Pale, coursed and
obviously worked, against the rim's dark bedded brown: that contrast is D-082's
readability rule — pale stone is what you can climb — carried by the material
and not only by a tint, which is how it survives a player turning the
brightness down.

`gravel_floor_03` is the pit floor and both haul roads, at 1k over 2 m, which
is 512 px/m on the one surface a player is always within a metre and a half of.
`weathered_planks` is the catwalks, the portal frames, the sleepers, the site
hut and the block pallets. `corrugated_iron_02` is the shelter roofs, the
hopper and the conveyor hood. `rusty_metal_02` is the derricks, the masts, the
hoist falls and the conveyor frame.

These are used **raw**, unlike the wharf's floor, which runs its concrete set
through `wharf_wet_concrete.gdshader` to wet it down. A quarry at eleven in the
morning has no weather to add: what the photographs want is a hard sun and a
sensible texel density, and both of those are in `quarry_map.gd` and
`quarry_env.tres` rather than in a shader.

No HDRI. The sky here is two thirds of the frame from the pit floor and it has
to be cloudless, hard and cheap; `quarry_env.tres` draws it with a
`ProceduralSkyMaterial` whose disc curve is tight enough that the sun reads as
a sun, and a photographic dome would cost more than it returns on a map where
the interesting light is all bounce off pale stone.
