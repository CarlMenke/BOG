# Assets for Halcyon Wake (`scenes/world/maps/yacht.tscn`)

| file | source | licence |
|---|---|---|
| `teak_veneer_diff_1k.jpg` | [Poly Haven — Teak Veneer](https://polyhaven.com/a/teak_veneer), 1k JPG, `diff` | CC0 (public domain) |
| `teak_veneer_nor_gl_1k.jpg` | same asset, 1k JPG, `nor_gl` (OpenGL-convention normal) | CC0 (public domain) |
| `teak_veneer_rough_1k.jpg` | same asset, 1k JPG, `rough` | CC0 (public domain) |

1.7 MB in total. Downloaded from `https://api.polyhaven.com/files/teak_veneer`.
Poly Haven publishes everything it hosts under CC0: no attribution is required
and commercial redistribution is permitted, so these can live in the repository
and ship in an export build.

## How they are used

`YachtMap._teak_maps()` reads the diffuse and the normal at load, resizes both to
512, and multiplies the map's own generated plank-and-caulk layout into them — a
sixteen-plank tile with a butt joint in every plank, and a groove at every seam
that goes into the *normal* as well as the albedo. The result is two
`ImageTexture`s and one material.

That is done at load rather than by shipping a pre-baked deck texture because
the two halves have to tile at different rates and be authored separately: the
grain is photographic and repeats every 2.4 m, and the caulking is arithmetic
and has to land exactly every 150 mm whatever the grain does. It costs about
150 ms once, when the map is built.

The roughness map is used directly, unmodified, through
`StandardMaterial3D.roughness_texture`.

## What was downloaded and rejected

A 2k Poly Haven HDRI (`spiaggia_di_mondello`, a clear Mediterranean morning) was
downloaded and rendered as this map's sky, and then deleted. See the decision
record for why: a photographic dome brings its own baked coastline and its own
baked sun, and this map has authored geometry for the first and a gameplay
requirement for the second.
