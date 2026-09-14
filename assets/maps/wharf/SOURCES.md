# Lantern Wharf — downloaded source textures

Everything here is **CC0 1.0 Universal** (public domain dedication): no
attribution required, commercial use permitted, redistribution in this
repository permitted. Listed anyway, because "where did this come from" is a
question worth never having to guess at.

| file | asset | source | licence |
|---|---|---|---|
| `brushed_concrete_2_diff_2k.jpg` | Brushed Concrete 2, diffuse | [Poly Haven](https://polyhaven.com/a/brushed_concrete_2) | CC0 |
| `brushed_concrete_2_nor_gl_2k.jpg` | Brushed Concrete 2, normal (OpenGL / Y+) | [Poly Haven](https://polyhaven.com/a/brushed_concrete_2) | CC0 |
| `brushed_concrete_2_rough_2k.jpg` | Brushed Concrete 2, roughness | [Poly Haven](https://polyhaven.com/a/brushed_concrete_2) | CC0 |
| `rust_coarse_01_diff_1k.jpg` | Rust Coarse 01, diffuse | [Poly Haven](https://polyhaven.com/a/rust_coarse_01) | CC0 |

## Why these four, and why at these sizes

The yard floor is the single biggest surface in the game's smallest map — it is
half of every frame a player has, it is what the four floodlights pool on, and
it is the thing that has to read as *wet* for the map to be a dock at dusk
rather than a box. It gets the full set at 2k: 2048 px over the 6 m tile is
341 px/m, and the floor is 40.8 m across, so a player standing on it is looking
at real grain rather than at magnified noise. The `nor_gl` variant is the one
Godot wants (OpenGL/Y+ green channel); `nor_dx` would light every pit as a bump.

These are **not used raw**. `resources/shaders/wharf_wet_concrete.gdshader`
samples all three and then wets the floor down: a seeded low-frequency mask
picks out standing water, and inside it the roughness drops to near-mirror, the
albedo darkens, the photographic normal is flattened toward the water surface
and a slow two-wave ripple is added. So the download supplies the grain and the
shader supplies the weather.

`rust_coarse_01` is 1k and greyscale in use: it is the containers' roughness
variation, which is what stops eleven flat paints reading as plastic. The
diffuse map is the only channel needed for that, so the rest of the set was not
downloaded.

No HDRI. This map is lit by four sodium floods, a grazing sun and a 36 m box
with 7.8 m walls — the dome is a strip of sky over the wall tops and contributes
less here than on any other map in the game, while the thing it would cost is
the one thing the island proves matters: the sky *moves*.
`resources/config/wharf_sky.tres` drifts cloud and twinkles stars on the shared
`enchanted_sky.gdshader`, and a static photographic dome would have been a
downgrade dressed as an upgrade.
