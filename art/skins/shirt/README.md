# The shirt

A **garment** skin (D-100, `docs/SKIN_PIPELINE.md` Route 3): a mesh bound
to the BOG's own 49 `mixamorig_*` bones, so it inherits every clip in
`art/generated/bog_clips.res` without a refit and without touching the body,
the rig or the clip library.

- `garment.glb` — the mesh, skinned to the Mixamo rig by bone name. Godot
  turns the exporter's `mixamorig:` into `mixamorig_`, which is what the
  game's `Skeleton3D` uses, so `wear` re-parents it and nothing else.
- `thumb.png` — the picker's tile, rendered with the shirt on
  (`tools/skin_thumbs.gd`).

Since D-163 this is a **pickable skin**, the fifteenth in `Skins.NAMES`, and
the first with no `basecolor.png` at all: what the picker offers is the plain
body wearing clothes. `Bog.wear_skin` dons it through `SkinGarment`, the corpse
keeps it, and it takes its team's colour with the body.

## How it was made

Route 3, end to end:

1. Image AI drew the BOG wearing the outfit from the front, with the Route 3
   prompt in `docs/SKIN_PIPELINE.md` and `bog_front.png` as the reference.
2. Tripo *Image to 3D* turned that picture into a dressed body,
   `assets/source/skins/SHIRT/SHIRT_dressed.glb`.
3. Tripo *part segmentation* cut the clothing off it,
   `assets/source/skins/SHIRT/SHIRT_garment.glb`.
4. `tools/fit_garment.py` put the cut back on the body it came from
   (translation-only ICP), took it into the game's metres, subdivided it once,
   pushed every vertex outside the real body, borrowed the body's own vertex
   weights and exported the result.

## Rebuilt by

```
"$BLENDER" --background --python tools/fit_garment.py -- SHIRT shirt
```

It ran with the defaults: `--offset 0.008` metres of clearance, `--influences 4`
bones per vertex, `--subdivide 1` simple subdivision of Tripo's coarse cut,
`--relax 2` smooth-then-re-push passes to take the dents out of it and
`--smooth-weights 2` passes over the transferred weights.

## What that run printed

```
source SHIRT -> art/skins/shirt, offset 0.0080 m, 4 influences, subdivide 1, relax 2, smooth-weights 2
body: imported 0.01000 m tall, scaled x179.9879 -> 1.7990 m, feet at z=0.00000
body: hips bone head at z=0.6184 m (expect ~0.618), 49 bones, 15872 verts
tripo: dressed mesh 3679 verts, garment mesh 'meshes[3]' 705 verts
weld: merge by 0.00050, 705 verts -> 548, boundary edges 348 -> 64
icp: 30 iterations, mean nearest 0.00763, max nearest 0.02286 (dressed units, body is 0.9995 tall)
into body space: scaled x1.7999; arm span dressed 1.699 m vs body 1.665 m (ratio 1.020)
densify: 1 simple subdivision(s), 548 verts -> 3170
push-out: offset 0.0080 m; inside before 677 (deepest 84.5 mm), after shrinkwrap 709, 2 relax passes, 1430 vertices lifted by hand, inside after 0 (deepest 0.0 mm)
push-out: clearance at rest, smallest 2.35 mm, mean 21.48 mm; under half the offset 123 verts -> 1 after 967 inflate moves
weights: 14 bones, <=4 influences per vertex, 2 smoothing passes
    Spine2                       1973 verts
    Neck                         1400 verts
    Head                         1341 verts
    Spine1                        972 verts
    Spine                         795 verts
    Hips                          714 verts
    LeftShoulder                  714 verts
    RightShoulder                 621 verts
    RightArm                      441 verts
    LeftArm                       439 verts
    RightForeArm                  304 verts
    LeftForeArm                   293 verts
    RightUpLeg                    150 verts
    LeftUpLeg                     150 verts
material: 'shirt', base colour SHIRT_garment_basecolor.jpg 1024x1024, roughness 0.9, metallic 0
export: art/skins/shirt/garment.glb, 470 KB
render: build/review/shirt_tpose.png
render: build/review/shirt_idle.png (frames [1, 100, 200, 299])
render: build/review/shirt_walk.png (frames [1, 13, 24, 36])
render: build/review/shirt_crouch.png (frames [1, 69, 138, 206])
render: build/review/shirt_roll.png (frames [1, 25, 48, 72])
render: build/review/shirt_sword.png (frames [1, 36, 72, 107])
penetration: clip     frame  inside          deepest   inside what
    idle     1        81 / 3170      17.1 mm  RightShoulder 42, LeftShoulder 23, LeftHandIndex2 10
    idle     100      99 / 3170      19.0 mm  RightShoulder 36, LeftShoulder 28, LeftHandMiddle1 9
    idle     200      79 / 3170      19.1 mm  RightShoulder 40, LeftShoulder 24, LeftHandIndex2 8
    idle     299      81 / 3170      17.1 mm  RightShoulder 42, LeftShoulder 23, LeftHandIndex2 10
    walk     1        39 / 3170      15.6 mm  LeftHandThumb2 12, LeftHand 10, LeftHandThumb1 6
    walk     13       23 / 3170      17.6 mm  LeftForeArm 6, LeftShoulder 5, RightHandIndex3 5
    walk     24        9 / 3170       7.3 mm  Hips 7, RightArm 2
    walk     36       39 / 3170      15.6 mm  LeftHandThumb2 12, LeftHand 10, LeftHandThumb1 6
    crouch   1        99 / 3170      18.5 mm  Hips 31, Head 12, LeftUpLeg 11
    crouch   69      106 / 3170      17.6 mm  Hips 33, Head 16, LeftUpLeg 13
    crouch   138      94 / 3170      16.4 mm  Hips 28, LeftUpLeg 15, Spine2 13
    crouch   206      99 / 3170      18.5 mm  Hips 31, Head 13, LeftUpLeg 11
    roll     1         5 / 3170      22.0 mm  Hips 3, RightForeArm 1, Head 1
    roll     25      236 / 3170      27.4 mm  Head 135, RightArm 27, LeftForeArm 23
    roll     48       81 / 3170      23.9 mm  Head 36, Hips 21, LeftArm 9
    roll     72        5 / 3170      22.0 mm  Hips 3, RightForeArm 1, Head 1
    sword    1       206 / 3170      30.4 mm  Spine2 77, LeftForeArm 29, LeftShoulder 28
    sword    36      409 / 3170      24.7 mm  Spine 89, Hips 86, Spine2 54
    sword    72      508 / 3170      39.6 mm  Head 279, Hips 69, Spine 46
    sword    107     209 / 3170      30.4 mm  Spine2 77, LeftForeArm 29, LeftShoulder 28
penetration: worst sword frame 72, 508 verts inside, 39.6 mm deep (Head 279, Hips 69, Spine 46)
```

The review renders are `build/review/shirt_tpose.png` and one strip of four
frames per proof clip — idle, walk, crouch, dive roll, sword combo — body in
grey, garment in red, rendered in Blender rather than Godot so the fit can be
judged before the game ever loads it.

## What the penetration table is not saying

The count is *garment vertices inside the body mesh*, and the body mesh includes
the arms and that enormous head. So a pose where the arms cross the chest, or
where the head pitches down onto the collar, scores in the hundreds without
anything being visibly wrong — the cloth is behind an arm or tucked under a chin,
which is where cloth goes. Read the `inside what` column before the number:
`Head`, `LeftForeArm` and the `*Hand*` bones are those cases. What is left on
the torso is the hem: the BOG's abdomen is a sphere and this shirt is short, so
past about sixty degrees of forward spine bend the hem lifts off the belly and
bare body shows *below* the cloth — visible in the sword combo and the middle of
the dive roll. That is the garment being short, not the fit being wrong.

Three things in the tool exist only to keep the cloth off the body, and each was
put there because a render showed the body coming through:

- **The weld.** Tripo ships the cut with its UV seams unwelded — 348 boundary
  edges on a shell whose only openings are a neck, two cuffs and a hem. The
  subdivide, the shrinkwrap and the relax move coincident vertices differently
  and every seam opens into a crack with grey body behind it.
- **The inflate.** A shrinkwrap cannot clear a *crease* — in the armpit the
  nearest body point is the crease line itself, so pushing out along one face's
  normal presses the vertex into the other face. The inflate pass moves a vertex
  along the *cloth's* own normal instead, which points out of the crease.
- **The weight smoothing.** Nearest-surface weights put arm bones on one side of
  the armpit and spine bones a centimetre away on the other; the cloth shears
  along that line when the arm swings.
