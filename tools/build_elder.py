"""Build the Elder's robe and hat — one skinned mesh that wears the Gub's own skeleton.

`art/generated/gub.glb` is the Gub: one mesh, one 49-bone skeleton, nine clips
(`tools/build_gub.py` builds it and is the model this script is written after).
The Elder is that same Gub in a floor-length purple robe and a wizard hat, and
the cheapest honest way to say that is a **second skinned mesh bound to the same
skeleton**: `art/generated/elder.glb` carries the robe, the hat and a copy of the
skeleton to bind against, and no animation data at all. At runtime its
`MeshInstance3D` is re-parented onto a Gub's existing `Skeleton3D` — the same
reach-into-the-skeleton move `HeldSpear.attach_to()` already makes — so there is
one copy of the nine clips in the project and a future rebuild of the Gub flows
through the Elder for free.

Run it as:

    "$BLENDER" --background --python tools/build_elder.py [-- --emission FLOAT]

or `bash tools/build_elder.sh` to have Blender located for you. Re-running is
always safe: it reads `art/generated/gub.glb`, writes `art/generated/elder.glb`,
and never touches `assets/`.

What it does, and why each step is needed:

*Measure, then fit.* Nothing here is a typed-in dimension. The Gub is imported,
its arm vertices are set aside (the arms stick straight out in the rest pose and
reach 0.95 m against the body's 0.37, so any silhouette measured through them
would be a metre and a half wide at the shoulder), and the rest of the body is
sliced 41 times and turned into a **support function** — for each of 48
directions, the furthest any vertex in the slice projects along it. The robe is
fitted to that. The numbers are printed on the way past so a regression shows up
in the log rather than in game, which is `build_gub.py`'s rule and the reason
that script's rig report exists.

A support function rather than a ray-cast, and both halves of that matter. It is
defined at every angle whether or not a vertex happens to sit there, which a ray
into the sparse column above the belly is not; and it describes the convex
outline of each slice rather than its dents, which is what cloth lying across a
body does horizontally for the same reason the hull below does it vertically.
(The first attempt did ray-cast, against a mesh with the arm *faces* deleted, and
was wrong in a way worth keeping: deleting those faces takes the shoulder caps
with them, so the silhouette at collar height measured as nothing and the robe
tapered to a funnel.)

*The robe is the upper convex hull of the body, per angle.* Cloth hanging over a
body touches its widest points and bridges the hollows between them; it does not
shrink-wrap. So for each of the 48 angles the measured profile r(z) — plus the
hem point and the collar point — is run through a convex hull and only the upper
side is kept. That is what puts the robe out at the belly (0.37 m at z = 0.75)
and straight down to the hem instead of pinching in at the thigh gap at z = 0.45,
and it is a measurement rather than a guess about where the cloth should sit.
`SKIRT_FULLNESS` then adds the fabric a taut hull cannot have, and `FOLDS`
ripples it, because a smooth cone reads as a traffic cone at any distance.

*The hem is the risk, and it is measured rather than hoped for.* The Gub's legs
are spindly and its feet are enormous, and a skirt is a rigid surface with no
cloth sim behind it (this is a game asset; eight Gubs can be on screen). The
skirt is therefore skinned partly to `LeftUpLeg`/`RightUpLeg` — `LEG_SHARE_MAX`
of it at the hem, split left/right by how far across the body a vertex sits — so
the panels swing with the thighs instead of standing still while a knee walks
through them. What that buys is then *checked*: every clip is played, both meshes
are evaluated with their armature deformation applied, and every Gub vertex that
starts the rest pose inside the robe is tested against the robe's surface with a
signed distance. The report splits what comes out into a leg appearing from under
the hem — which is what a hem is for — and a limb through a panel, which is the
failure; `Run`, `Slide` and `JumpTwo` are the rows to read. As shipped, `Idle`,
`Walk` and `CrouchIdle` put nothing through a panel and the three extremes do
(see D-037, which has the table and the renders). This is the honest number, not
a pass mark: nothing here can hold a rigid surface off a body that folds in half,
and saying so in the log is the point of measuring it.

*The hat is rigid-weighted 100% to `Head`, which makes it correct by
construction* — it cannot clip a head it never moves relative to. Its crown base
is sized by measuring the head's cross-section at the brim plane, so it fits this
skull rather than a nominal one. The Gub's two antennae leave the crown at
z = 1.58 and arch forward to z = 1.80, which is the whole of the space a hat
wants, so they come out through the front of the crown just above the brim. That
is deliberate: the alternatives are a hat floating above a head it does not touch
or a crown fat enough to swallow two antennae, and a hat with the antennae poking
out under it is what a hat on this creature would actually look like.

*The material is the part the brief is about.* Deep desaturated blue-leaning
purple, built as two procedurally generated images rather than as shader nodes,
because glTF carries images and flat factors and nothing else — a Noise Texture
node would simply not survive the export. `--emission` scales an emissive map
that is black cloth with bright runes on it, so the arcane detail glows and the
robe around it does not. See *Material* below for the numbers and D-027 for why
anything on this island needs an emission lever at all.

*Then it proves the bind.* The exported file's inverse bind matrices and joint
rest transforms are read back out of both GLBs with `tools/gltf_io.py` and
compared bone for bone. A separate mesh binding to somebody else's `Skeleton3D`
is only correct if the two skeletons agree about where every bone rests, and
"the export finished" does not say that. If they disagree the build fails here,
loudly, rather than shipping a robe that deforms around a subtly different body.

*Material.* One Principled BSDF over two 1024² images this script generates:

  `elder_basecolor`  the purple. A vertical value ramp (lighter at the shoulders
      and the hat brim, deeper toward the hem), the fold shading aligned to the
      geometry's own folds — the texture and the ripple share `FOLDS`, so the
      painted valleys sit in the modelled valleys — a woven grain, and the trim
      bands and rune glyphs.
  `elder_emissive`   black cloth with the runes and the trim edges on it, plus
      `CLOTH_GLOW`, a near-black violet over the whole robe.

Roughness is `ROUGHNESS` = 0.82 against the Gub's 0.9: velvet is not quite as
flat as whatever the Gub is made of, and a fraction of sheen is most of what
tells a viewer they are two materials. Metallic 0.

`--emission` (default `EMISSION_DEFAULT`) is the Principled emission strength
over that emissive map, and it is an argument for the reason `build_gub.py`'s is:
D-027 measured a flat-shaded body against Whisperbloom's undergrowth and found it
a near-silhouette wherever no torch reached, and this robe is far darker than the
Gub's yellow — 0.10 in linear against 0.6 — so it has further to fall. The cloth
term lifts it off the background at a spear's range; the runes are what reads as
a wizard at 20 m. `--emission 0` leaves the socket unwired, which gives back a
plain base-colour PBR material rather than one multiplied by zero (the same trap
`build_gub.py` documents: a wired-but-black emission is a texture fetch per
fragment that can never do anything).

The images are named `basecolor` and `emissive` and the file `elder.glb` on
purpose: Godot extracts an embedded texture as `<glb name>_<image name>`, so
what lands in the tree is
`art/generated/elder_basecolor.png` and `art/generated/elder_emissive.png`. They
are PNG rather than JPEG — these are flat synthetic gradients with hard-edged
glyphs on them, which is the case JPEG is worst at and PNG is best at.
"""

import math
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree
from mathutils.bvhtree import BVHTree

# ---------------------------------------------------------------------------
# What is being built
# ---------------------------------------------------------------------------

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_PATH = os.path.join(REPO, "art", "generated", "gub.glb")
OUT_PATH = os.path.join(REPO, "art", "generated", "elder.glb")

FPS = 60

# The bones the robe is allowed to touch. Anything else in the 49 is either an
# arm (the robe deliberately has no sleeves — see *The robe* below) or a finger.
SPINE_CHAIN = ("Hips", "Spine", "Spine1", "Spine2")
LEG_BONES = ("LeftUpLeg", "RightUpLeg")
HEAD_BONE = "Head"
NECK_BONE = "Neck"

# Vertex groups whose name contains one of these belong to an arm, and the arms
# are cut out of the mesh the silhouette is measured from. In the rest pose they
# are held straight out sideways — |x| reaches 0.95 m against the body's 0.37 —
# so a robe fitted to a profile that included them would be a metre and a half
# wide at the shoulder.
ARM_MARKERS = ("Shoulder", "Arm", "ForeArm", "Hand")

# Where Blender's glTF importer parks the helper objects it makes for itself and
# its own exporter then skips. See `import_gub`.
NOT_EXPORTED = "glTF_not_exported"

# ------------------------------------------------------------------ the robe --
#
# Every number here is in metres in the Gub's own rest space: +Z is up, feet at
# z = 0, head top at z = 1.80, and **-Y is front** (`build_gub.py` establishes
# that from the LeftFoot -> LeftToeBase vector). Angles below are measured from
# the front and increase toward the Gub's left, so theta = 0 is the belly and
# theta = pi is the spine.

SEGMENTS = 48          # ring resolution. 48 is 7.5 degrees; at 0.55 m radius
                       # that is a 7 cm facet, under a tenth of the fold pitch.
HEM_Z = 0.055          # just clear of the floor, and below the 0.15 m feet, so
                       # the Gub stands *in* the robe rather than on it.
HEM_RADIUS = 0.55      # the feet reach 0.437 from the body axis: this clears
                       # them by 0.11 in rest and is what the legs swing inside.
TOP_Z = 1.160          # a shade above the shoulder joints at 1.098 and well
                       # below the eyes at ~1.36, so the robe ends at a shoulder
                       # line and leaves the face clear.
BODY_CLEARANCE = 0.045     # air between cloth and body over the torso.
TOP_CLEARANCE = 0.030      # less at the collar, where the cloth is pulled in.
# Fabric a taut hull cannot account for, peaking mid-skirt: a straight cone from
# hem to belly is only 0.13 m of flare over 0.7 m and reads as a lampshade.
SKIRT_FULLNESS = 0.055
SKIRT_TOP_Z = 0.78         # where the skirt's fullness has faded to nothing.

FOLDS = 9              # odd on purpose: the front and the back of the robe then
                       # sit on different parts of the wave, so the silhouette
                       # is not mirror-identical from the two sides a player
                       # most often sees it from.
FOLD_DEPTH = 0.075     # of the local radius, at the hem; 0 at the collar.
FOLD_PHASE = 0.37      # radians, so a fold valley does not land dead centre
                       # front where it would read as a seam.

# The hem is rolled: the outer ring, then a ring inside and above it. Without it
# a camera below the waist looks straight up a hollow cone.
HEM_ROLL_IN = 0.045
HEM_ROLL_UP = 0.040
# ...and the collar the same way, so the top edge has a thickness.
TOP_ROLL_IN = 0.035
TOP_ROLL_DOWN = 0.050

# How much of the skirt follows the thighs instead of the pelvis, at the hem.
# Linear blend skinning cannot push cloth, so a skirt bound wholly to `Hips`
# stands still while a knee walks through it. Bound wholly to the legs it is
# dragged around the hip joint instead, and that is not a trade nobody notices:
# at 0.55 the hem of `Run` was pulled into a point on whichever side the thigh
# had swung — 0.6 m below a joint, a 40-degree swing moves the cloth 0.42 m — and
# the robe read as a sack being dragged rather than as a skirt. 0.35 keeps the
# ring's shape, and `fit_report` says what it cost: `Run` and `Walk` both hold,
# and the crouches are where it is paid.
LEG_SHARE_MAX = 0.35
LEG_SHARE_TOP = 0.660      # the hip joints' height: no leg influence above it.
# How far across the body counts as "wholly on that side". The hip joints are
# 0.25 m apart, so 0.16 puts the outer third of each panel on one leg and blends
# the front and back of the skirt evenly between the two.
LEG_SPLIT_HALF = 0.16

# Where the robe hands over from one spine bone to the next, as (height, bone).
# Linear between neighbours, so every vertex is a two-bone blend and nothing in
# the cloth can hinge.
SPINE_RAMP = (
    (0.000, "Hips"),
    (0.720, "Hips"),
    (0.815, "Spine"),
    (0.905, "Spine1"),
    (1.020, "Spine2"),
    (1.400, "Spine2"),
)

# ----------------------------------------------------------------- the cowl --
#
# A standing collar behind the head, over the back 116 degrees only. A full hood
# would fight the hat and a full mantle would fight the arms — which on this body
# leave the shoulders at z = 1.098, directly under the head, with nowhere for a
# cape to be that an elbow does not pass through.
COWL_ARC = math.radians(48.0)   # either side of the back. Wider than this and
                                # the two ends of it come round far enough to
                                # stand up beside the Gub's cheeks in a front
                                # view, which reads as a broken collar.
COWL_RISE = 0.260               # tops out at z = 1.42, under the brim.
COWL_GAP = 0.075                # air between the cowl's top edge and the skull.
COWL_FLARE = 0.075              # how far the top edge stands off, as a fan.
COWL_RINGS = 7
# The cowl's top edge follows the head this much and the chest the rest. It is
# not 0 because the top edge finishes 7.5 cm from a skull that tilts, and not 1
# because a collar that rides the head is a hood.
COWL_HEAD_SHARE = 0.45

# ------------------------------------------------------------------ the hat --

HAT_BRIM_Z = 1.470     # the brim plane's height on the hat axis. The skull is
                       # still 0.26 m across here; above 1.60 there is nothing
                       # left of it but the two antennae.
HAT_TILT = math.radians(18.0)   # leant back, because the head leans forward —
                                # and far enough back that the brim's front edge
                                # rides above the Gub's eyes instead of across
                                # them, which is what 12 degrees did.
HAT_BASE_CLEARANCE = 0.028      # around the skull at the brim plane.
HAT_HEIGHT = 0.620              # crown, along the axis.
HAT_TAPER = 1.25                # r = R (1-t)^TAPER. Above 1 the cone is
                                # slightly concave, which is what stops it
                                # reading as a party hat.
HAT_TIP_RADIUS = 0.008
HAT_CROWN_RINGS = 18
HAT_SEGMENTS = 40
# The droop. Back and to the Gub's left, which is the one direction the antennae
# do not already occupy — they arch forward. Cubic from DROOP_START so the bend
# starts as cloth rather than as a kink.
HAT_DROOP = 0.255
HAT_DROOP_START = 0.42
HAT_DROOP_DIR = (0.36, 0.93)    # (x, y) before it is squared up to the axis.

HAT_BRIM_WIDTH = 0.245          # outer radius = crown base + this.
HAT_BRIM_DROP = 0.045           # the edge sags this far below the brim plane.
HAT_BRIM_WAVE = 0.026           # ...and waves, 3 lobes, so it is cloth.
HAT_BRIM_WAVE_LOBES = 3
HAT_BRIM_LIP = 0.022            # a turned-up return at the very edge.
HAT_BRIM_RINGS = 5

# ------------------------------------------------------------- the material --

TEXTURE_EDGE = 1024
# How wide a rune stroke and a trim rule are drawn, in texels. The first build
# used 1.5, which is a hairline: it survives a 2 m close-up and is gone by the
# time the mip chain has halved it twice, and 20 m is where the Elder has to be
# recognisable. 2.6 is still a line rather than a band and it is still there at
# the third mip.
GLYPH_WIDTH = 2.6
TRIM_RULE_WIDTH = 2.5
ROUGHNESS = 0.82
METALLIC = 0.0
EMISSION_DEFAULT = 1.0

# Authored in sRGB, 0-1, because that is the space the PNG stores and the space
# a colour picker agrees with. HSV of CLOTH_MID is 274 degrees / 58% / 27%:
# blue-leaning, desaturated enough not to read as a costume, and dark. The first
# build of this was two stops lighter — #3A2A58, which is a perfectly good purple
# on a swatch — and it rendered as lilac, because a robe is lit by an ambient
# term and a key light and then run through ACES before anybody sees it. These
# are the values that came back *looking* like the brief once all three had had
# their turn, which is the only place a colour can be judged.
CLOTH_DEEP = (0.078, 0.047, 0.125)   # #140C20, the bottom of a fold
CLOTH_MID = (0.184, 0.114, 0.271)     # #2F1D45, the body of the cloth
CLOTH_HIGH = (0.247, 0.165, 0.357)   # #3F2A5B, shoulders and the brim's top
TRIM = (0.424, 0.306, 0.596)         # #6C4E98, the woven bands
RUNE = (0.760, 0.686, 1.000)         # #C2AFFF, the glyphs
# What the cloth emits everywhere, before `--emission`. Linear ~0.012, which is
# the same order as the 0.15-of-albedo the Gub's darkest surfaces emit (D-027)
# and is the difference between a silhouette and a shape under a 0.30-energy
# moon.
CLOTH_GLOW = (0.086, 0.063, 0.157)

# The atlas. Each piece gets a full-width horizontal band, because every piece is
# a loft whose two parameters already are (around, along) — there is no unwrap
# here, the UVs are the surface parameters.
UV_BANDS = {
    "robe": (0.015, 0.600),
    "cowl": (0.620, 0.720),
    "crown": (0.740, 0.930),
    "brim": (0.945, 0.995),
}

# ------------------------------------------------------------- the fit check --

# Clips are walked at this stride and this many vertices are tracked. The point
# is a number that moves when the weights move, not a per-vertex audit: 800
# vertices over a 3000-vertex lower body catches a panel, and a poke-through
# smaller than that is not one.
FIT_FRAME_STEP = 3
FIT_SAMPLE = 800
FIT_SEED = 20260913
# A tracked vertex this far outside the cloth is reported as a poke-through. A
# millimetre or two is the surface touching itself, which happens wherever the
# clearance is spent.
FIT_TOLERANCE = 0.004

# How close to the robe's open edge a nearest-surface point counts as "this
# vertex left through the opening rather than through the cloth". The hem ring
# has 48 vertices around 3.4 m, so they are 70 mm apart: 90 mm is over half that
# spacing — anything genuinely on the edge is inside it — and far short of the
# 250 mm a panel poke has to be wrong by to matter.
HEM_EDGE_NEAR = 0.09

# Clips whose hem behaviour is the question, printed first and in full.
EXTREME_CLIPS = ("Run", "Slide", "JumpTwo")


def log(msg=""):
    print(msg, flush=True)


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def wrap_pi(angle):
    return (angle + math.pi) % (2.0 * math.pi) - math.pi


def direction(theta):
    """Unit vector at `theta`, measured from the front and turning toward +X.

    theta = 0 is -Y (the belly), pi/2 is +X (the Gub's left), pi is +Y (the
    spine). Keeping the front at zero is what lets the cowl and the fold phase
    be written as angles off the front rather than as offsets nobody can read.
    """
    return Vector((math.sin(theta), -math.cos(theta), 0.0))


# ---------------------------------------------------------------------------
# 1. The Gub, and the shape of it
# ---------------------------------------------------------------------------

def import_gub():
    """Import `gub.glb` and return (armature, mesh, {clip: action}).

    Blender 5.2's glTF importer drops a 42-vertex Icosphere into a collection
    called `glTF_not_exported` — a placeholder it keeps for its own bookkeeping
    and that its own exporter then skips. It is a third object in the scene and
    a second mesh, so it is filtered out here by the collection it lives in
    rather than by its name, which is the part of it that is a promise.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0

    if not os.path.isfile(SOURCE_PATH):
        raise SystemExit("missing %s — run tools/build_gub.sh first" % SOURCE_PATH)
    bpy.ops.import_scene.gltf(filepath=SOURCE_PATH)

    def real(obj):
        return not any(c.name == NOT_EXPORTED for c in obj.users_collection)

    skipped = [o.name for o in scene.objects if not real(o)]
    if skipped:
        log("  ignoring the importer's own %s: %s"
            % (NOT_EXPORTED, ", ".join(skipped)))
    armatures = [o for o in scene.objects if o.type == 'ARMATURE' and real(o)]
    meshes = [o for o in scene.objects if o.type == 'MESH' and real(o)]
    if len(armatures) != 1 or len(meshes) != 1:
        raise SystemExit("expected 1 armature and 1 mesh in %s, got %d/%d"
                         % (SOURCE_PATH, len(armatures), len(meshes)))
    arm, mesh = armatures[0], meshes[0]
    actions = dict((a.name.replace("-loop", ""), a) for a in bpy.data.actions)

    missing = [b for b in SPINE_CHAIN + LEG_BONES + (HEAD_BONE, NECK_BONE)
               if b not in arm.data.bones]
    if missing:
        raise SystemExit("the Gub's skeleton has no %s — bone names have moved"
                         % ", ".join(missing))

    log("  imported %s: %d bones, %d verts, %d clips (%s)"
        % (os.path.relpath(SOURCE_PATH, REPO).replace("\\", "/"),
           len(arm.data.bones), len(mesh.data.vertices), len(actions),
           ", ".join(sorted(actions))))
    return arm, mesh, actions


def dominant_groups(mesh):
    """{vertex index: the name of the group that owns it}."""
    names = dict((g.index, g.name) for g in mesh.vertex_groups)
    out = {}
    for vert in mesh.data.vertices:
        if vert.groups:
            out[vert.index] = names[max(vert.groups, key=lambda g: g.weight).group]
        else:
            out[vert.index] = ""
    return out


def body_points(mesh, dominant):
    """The Gub's body as an (N, 3) array, with the arms left out.

    Arms go by *vertex* rather than by face. Cutting whole faces was the first
    attempt and it is wrong: it takes the shoulder caps with them and leaves a
    hole exactly where the robe's collar has to be fitted, so the silhouette
    there measured as nothing and the robe tapered to a funnel at the top.
    """
    kept = [tuple(v.co) for v in mesh.data.vertices
            if not any(m in dominant[v.index] for m in ARM_MARKERS)]
    log("  silhouette: %d of %d vertices (%d belong to an arm and are left out)"
        % (len(kept), len(mesh.data.vertices), len(mesh.data.vertices) - len(kept)))
    return np.asarray(kept, dtype=np.float64)


def report_rest(arm, mesh):
    """Re-print the measurements this build is fitted to."""
    coords = [v.co for v in mesh.data.vertices]
    low = min(c.z for c in coords)
    high = max(c.z for c in coords)
    log("  Gub is %.3f m tall, feet at z=%+.4f" % (high - low, low))
    heights = ("Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
               "LeftShoulder", "LeftUpLeg", "LeftFoot")
    log("  rest heights " + "  ".join(
        "%s %.3f" % (n, arm.data.bones[n].head_local.z) for n in heights))
    hips = arm.data.bones["LeftUpLeg"].head_local - arm.data.bones["RightUpLeg"].head_local
    log("  hip joints %.3f m apart; a hem vertex more than LEG_SPLIT_HALF %.3f m "
        "across the body follows that thigh alone, and the front and back of the "
        "skirt split evenly between the two"
        % (hips.length, LEG_SPLIT_HALF))
    if abs(high - 1.80) > 1e-3 or abs(low) > 1e-3:
        raise SystemExit("the Gub is %.4f tall with feet at %.4f — this script is "
                         "fitted to 1.80 at 0" % (high - low, low))
    return Vector((arm.data.bones["Hips"].head_local.x,
                   arm.data.bones["Hips"].head_local.y, 0.0))


# ---------------------------------------------------------------------------
# 2. The silhouette, measured
# ---------------------------------------------------------------------------

# How thick a slice of the body each ring is measured from. 35 mm is thin enough
# that the belly and the waist are separate measurements and thick enough that
# the sparse column above the belly — 25 vertices in a 50 mm band — still has
# something in it at every angle.
Z_SLAB = 0.035

# The unit vectors of the SEGMENTS ring angles, as a (SEGMENTS, 2) array.
RING_DIRS = np.asarray(
    [[math.sin(2.0 * math.pi * i / SEGMENTS), -math.cos(2.0 * math.pi * i / SEGMENTS)]
     for i in range(SEGMENTS)], dtype=np.float64)


def support(points, axis, z, dirs=None):
    """How far the body reaches from the axis at this height, per ring angle.

    This is the *support function* of the slice — for each direction, the
    furthest any vertex in the slab projects along it — and not the distance to
    the surface along a ray. That is the right measurement for cloth twice over.
    It is defined at every angle whether or not a vertex happens to sit there,
    which a ray-cast against a sparse column is not; and it describes the convex
    outline of the slice rather than its dents, which is what a robe lying across
    a body does horizontally for the same reason `upper_hull` does it vertically.
    """
    if dirs is None:
        dirs = RING_DIRS
    slab = points[np.abs(points[:, 2] - z) <= Z_SLAB]
    if len(slab) == 0:
        return np.zeros(len(dirs))
    offsets = slab[:, :2] - np.asarray([axis.x, axis.y])
    return np.maximum(offsets @ dirs.T, 0.0).max(axis=0)


def support_at(points, axis, z, theta):
    """The same, for one angle — what the cowl needs to stand off the skull."""
    dirs = np.asarray([[math.sin(theta), -math.cos(theta)]])
    return float(support(points, axis, z, dirs)[0])


def upper_hull(points):
    """The upper convex hull of (z, r) points, z ascending.

    Cloth over a body is the hull, not the body: it rests on the belly and the
    shoulder and bridges the hollow between them. Monotone chain, upper side
    only; the result is returned as the hull's vertices and read back with
    `hull_at`.
    """
    hull = []
    for p in sorted(points):
        while len(hull) >= 2:
            (z0, r0), (z1, r1) = hull[-2], hull[-1]
            # Keep the turn clockwise, which for an upper hull means dropping any
            # middle point that sits below the chord across it.
            if (z1 - z0) * (p[1] - r0) - (r1 - r0) * (p[0] - z0) >= 0.0:
                hull.pop()
            else:
                break
        hull.append(p)
    return hull


def hull_at(hull, z):
    for i in range(1, len(hull)):
        if z <= hull[i][0]:
            (z0, r0), (z1, r1) = hull[i - 1], hull[i]
            if z1 - z0 < 1e-9:
                return max(r0, r1)
            return lerp(r0, r1, (z - z0) / (z1 - z0))
    return hull[-1][1]


def robe_radii(points, axis):
    """[radius per angle] at each ring height, plus the raw body measurements.

    41 slices of the body are measured, each one turned into "how far out must
    the cloth be, in this direction, to clear it"; the hem and the collar are
    added as given points, because the hem is where the cloth is *put* and the
    collar is where it stops; and the upper hull of that per angle is the robe.
    The ring heights are then sampled off the hull, denser at the two rolled
    edges than down the straight of the skirt.
    """
    sample_z = [HEM_Z + (TOP_Z - HEM_Z) * (i / 40.0) for i in range(41)]
    raw = dict((z, support(points, axis, z)) for z in sample_z)

    rings = []
    for i in range(23):
        # A cosine-ish spacing: tight at both ends, open in the middle.
        t = i / 22.0
        rings.append(lerp(HEM_Z, TOP_Z, t - 0.12 * math.sin(2.0 * math.pi * t)))
    rings = sorted(set(round(z, 5) for z in rings))

    hulls = []
    for theta_i in range(SEGMENTS):
        # Clearance tightens toward the collar, where the cloth is pulled in
        # against a shoulder rather than hanging clear of a belly.
        clearance = [(z, raw[z][theta_i] + lerp(BODY_CLEARANCE, TOP_CLEARANCE,
                                                smoothstep((z - 0.90) / 0.26)))
                     for z in sample_z if raw[z][theta_i] > 0.01]
        top_r = raw[TOP_Z][theta_i] + TOP_CLEARANCE
        hulls.append(upper_hull(clearance + [(HEM_Z, HEM_RADIUS), (TOP_Z, top_r)]))

    profile = []
    for z in rings:
        row = []
        for theta_i in range(SEGMENTS):
            r = hull_at(hulls[theta_i], z)
            # Fullness: fabric the taut hull has no way to account for, largest
            # halfway down the skirt and gone by the waist.
            if z < SKIRT_TOP_Z:
                u = (SKIRT_TOP_Z - z) / (SKIRT_TOP_Z - HEM_Z)
                r += SKIRT_FULLNESS * math.sin(math.pi * min(1.0, u) ** 0.75)
            row.append(r)
        profile.append((z, row))
    return profile, raw


def report_profile(profile, raw, axis):
    log("  body axis at (%.4f, %.4f); %d directions x %d slices %.0f mm thick"
        % (axis.x, axis.y, SEGMENTS, len(raw), Z_SLAB * 2000.0))
    log("            body reaches            robe sits at           robe")
    log("  height   front  left   back     front  left   back      min    max")
    picks = (0, SEGMENTS // 4, SEGMENTS // 2)
    for z, row in profile:
        near = min(raw, key=lambda s: abs(s - z))
        log("  %6.3f   %5.3f %5.3f %5.3f    %5.3f %5.3f %5.3f     %5.3f  %5.3f"
            % (z, raw[near][picks[0]], raw[near][picks[1]], raw[near][picks[2]],
               row[picks[0]], row[picks[1]], row[picks[2]], min(row), max(row)))


# ---------------------------------------------------------------------------
# 3. Building the surfaces
#
# Every piece is a grid of rings. `Piece` collects vertices, quads, per-corner
# UVs and per-vertex weights, and `assemble` welds the pieces into one mesh —
# one MeshInstance3D, one material, one skin, one node to re-parent in Godot.
#
# The rings carry `SEGMENTS` vertices and wrap, with no duplicated seam vertex:
# UVs live on *loops* in Blender, so the face that closes the ring is given
# u = 1 on its trailing corners and the vertices stay shared. A duplicated seam
# vertex would split the shading down the front of the robe.
# ---------------------------------------------------------------------------

class Piece:
    def __init__(self, name, band):
        self.name = name
        self.band = band          # (v_low, v_high) in the atlas
        self.verts = []
        self.faces = []
        self.uvs = []             # one (u, v) per face corner, faces in order
        self.weights = []         # one {bone: weight} per vertex
        self.sharp = set()        # frozenset({a, b}) edges to mark sharp

    def add_ring(self, points, weights):
        first = len(self.verts)
        self.verts.extend(points)
        self.weights.extend(weights)
        return first

    def stitch(self, ring_a, ring_b, count, v_a, v_b, closed=True, sharp=False):
        """Quads between two rings, with the atlas v of each."""
        span = count if closed else count - 1
        for i in range(span):
            j = (i + 1) % count
            a0, a1 = ring_a + i, ring_a + j
            b0, b1 = ring_b + i, ring_b + j
            self.faces.append((a0, a1, b1, b0))
            u0 = i / count
            u1 = (i + 1) / count
            self.uvs.extend([(u0, v_a), (u1, v_a), (u1, v_b), (u0, v_b)])
            if sharp:
                self.sharp.add(frozenset((a0, a1)))

    def band_v(self, t):
        return lerp(self.band[0], self.band[1], t)


def spine_weights(z):
    """The two-bone blend of the spine chain at this height."""
    for i in range(1, len(SPINE_RAMP)):
        z0, b0 = SPINE_RAMP[i - 1]
        z1, b1 = SPINE_RAMP[i]
        if z <= z1 or i == len(SPINE_RAMP) - 1:
            if b0 == b1 or z1 - z0 < 1e-9:
                return {b1: 1.0}
            t = min(1.0, max(0.0, (z - z0) / (z1 - z0)))
            if t <= 0.0:
                return {b0: 1.0}
            if t >= 1.0:
                return {b1: 1.0}
            return {b0: 1.0 - t, b1: t}
    return {SPINE_RAMP[-1][1]: 1.0}


def robe_weights(point, axis):
    """Spine blend, plus the thigh share that keeps the hem out of the legs."""
    weights = dict(spine_weights(point.z))
    if point.z < LEG_SHARE_TOP:
        share = LEG_SHARE_MAX * smoothstep(
            (LEG_SHARE_TOP - point.z) / (LEG_SHARE_TOP - HEM_Z))
        side = min(1.0, max(-1.0, (point.x - axis.x) / LEG_SPLIT_HALF))
        for bone, w in list(weights.items()):
            weights[bone] = w * (1.0 - share)
        weights["LeftUpLeg"] = share * (1.0 + side) * 0.5
        weights["RightUpLeg"] = share * (1.0 - side) * 0.5
    # Drop the crumbs and put what they were worth back into what is left. glTF
    # carries four influences per vertex and Godot renormalises what it is given,
    # so a 0.00006 weight is a wasted slot — but dropping it without redividing
    # leaves a vertex whose weights sum to 0.99994, and the check in `assemble`
    # is there to catch exactly the kind of mistake that looks like that.
    kept = dict((b, w) for b, w in weights.items() if w > 1e-4)
    total = sum(kept.values())
    return dict((b, w / total) for b, w in kept.items())


def build_robe(profile, axis):
    piece = Piece("robe", UV_BANDS["robe"])
    total = profile[-1][0] - profile[0][0]

    def ring_points(z, radii, scale=1.0, dz=0.0):
        out = []
        for i in range(SEGMENTS):
            theta = 2.0 * math.pi * i / SEGMENTS
            # The folds: deepest at the hem, gone at the collar, and cutting
            # inward rather than bulging outward — a fold is a valley.
            depth = FOLD_DEPTH * (1.0 - smoothstep((z - HEM_Z) / (TOP_Z - HEM_Z)))
            wave = 0.5 - 0.5 * math.cos(FOLDS * theta + FOLD_PHASE)
            r = radii[i] * (1.0 - depth * wave) * scale
            out.append(Vector((axis.x, axis.y, z + dz)) + direction(theta) * r)
        return out

    rings = []
    # The rolled hem, from the inside up and out to the outer edge.
    hem_r = [r - HEM_ROLL_IN for r in profile[0][1]]
    rings.append((ring_points(profile[0][0] + HEM_ROLL_UP, hem_r), 0.0))
    for index, (z, radii) in enumerate(profile):
        t = (z - profile[0][0]) / total
        rings.append((ring_points(z, radii), 0.02 + 0.94 * t))
    # ...and the rolled collar, folding inward and down inside the shoulder line.
    top_r = [r - TOP_ROLL_IN for r in profile[-1][1]]
    rings.append((ring_points(profile[-1][0] - TOP_ROLL_DOWN, top_r), 1.0))

    starts = []
    for points, _v in rings:
        starts.append(piece.add_ring(points, [robe_weights(p, axis) for p in points]))
    for i in range(len(rings) - 1):
        sharp = i == 0 or i == len(rings) - 2
        piece.stitch(starts[i], starts[i + 1], SEGMENTS,
                     piece.band_v(rings[i][1]), piece.band_v(rings[i + 1][1]),
                     sharp=sharp)
    # The two rings that are the surface's open edges — the inside of the rolled
    # hem and the inside of the rolled collar. `fit_report` needs them: a leg
    # below the hem is outside the cloth and is *supposed* to be, and the only
    # thing that tells that apart from a knee through a panel is whether the
    # nearest cloth to it is one of these edges.
    boundary = (list(range(starts[0], starts[0] + SEGMENTS))
                + list(range(starts[-1], starts[-1] + SEGMENTS)))
    return piece, boundary


def build_cowl(profile, axis, body):
    """The standing collar over the back of the robe's top edge."""
    piece = Piece("cowl", UV_BANDS["cowl"])
    count = int(SEGMENTS * (2.0 * COWL_ARC) / (2.0 * math.pi)) + 1
    top_z, top_r = profile[-1]

    def theta_of(i):
        return math.pi - COWL_ARC + 2.0 * COWL_ARC * i / (count - 1)

    starts = []
    for ring in range(COWL_RINGS + 1):
        t = ring / COWL_RINGS
        points, weights = [], []
        for i in range(count):
            theta = theta_of(i)
            # The rise fades to nothing at the two ends of the arc, so the collar
            # grows out of the shoulder line instead of starting as a step.
            edge = smoothstep(1.0 - abs(theta - math.pi) / COWL_ARC)
            rise = COWL_RISE * edge * t
            z = top_z - 0.020 + rise
            index = int(round(theta / (2.0 * math.pi) * SEGMENTS)) % SEGMENTS
            base = top_r[index]
            head = support_at(body, axis, z, theta)
            target = (head + COWL_GAP) if head > 0.01 else base
            r = lerp(base, target, t ** 0.9) + COWL_FLARE * t * t * edge
            points.append(Vector((axis.x, axis.y, z)) + direction(theta) * r)
            spine = spine_weights(min(z, 1.30))
            if t > 0.0:
                share = COWL_HEAD_SHARE * t
                weight = dict((b, w * (1.0 - share)) for b, w in spine.items())
                weight[NECK_BONE] = share
                weights.append(weight)
            else:
                weights.append(dict(spine))
        starts.append(piece.add_ring(points, weights))
    for ring in range(COWL_RINGS):
        piece.stitch(starts[ring], starts[ring + 1], count,
                     piece.band_v(ring / COWL_RINGS),
                     piece.band_v((ring + 1) / COWL_RINGS), closed=False,
                     sharp=(ring == COWL_RINGS - 1))
    return piece


def hat_frame(mesh, dominant):
    """Where the hat sits, measured off the skull rather than typed in.

    The axis is the crown's own centre line at the brim plane, leant back by
    HAT_TILT; the crown's base radius is whatever it takes to clear the skull in
    the slab the brim sits in, plus HAT_BASE_CLEARANCE.
    """
    head = [mesh.data.vertices[i].co for i, name in dominant.items()
            if name == HEAD_BONE]
    slab = [c for c in head if abs(c.z - HAT_BRIM_Z) < 0.045]
    if len(slab) < 8:
        raise SystemExit("only %d head vertices near z=%.3f — the head has moved"
                         % (len(slab), HAT_BRIM_Z))
    # The midpoint of the slice's bounding box, not its centroid. The Gub's two
    # eyes are Head-weighted geometry crowded onto the front of the skull, and a
    # centroid is pulled forward by them by 8 cm — enough to hang the hat off the
    # front of the head.
    centre = Vector(((min(c.x for c in slab) + max(c.x for c in slab)) * 0.5,
                     (min(c.y for c in slab) + max(c.y for c in slab)) * 0.5,
                     HAT_BRIM_Z))
    axis = Vector((0.0, math.sin(HAT_TILT), math.cos(HAT_TILT)))
    side = Vector((1.0, 0.0, 0.0))
    up = axis.cross(side).normalized()      # the in-plane "back" direction
    side = up.cross(axis).normalized()

    radius = 0.0
    for c in head:
        v = c - centre
        along = v.dot(axis)
        if -0.030 <= along <= 0.055:
            radius = max(radius, (v - axis * along).length)
    base = radius + HAT_BASE_CLEARANCE

    # What is left above the crown base, which is the pair of antennae: reported
    # rather than fitted around, because a crown wide enough to hold them is a
    # bucket. Where they leave the cloth is a number the log should carry.
    above = [c for c in head if (c - centre).dot(axis) > 0.06]
    out = 0.0
    exit_z = None
    for c in above:
        v = c - centre
        along = v.dot(axis)
        perp = (v - axis * along).length
        t = min(1.0, along / HAT_HEIGHT)
        crown = max(HAT_TIP_RADIUS, base * (1.0 - t) ** HAT_TAPER)
        if perp - crown > out:
            out = perp - crown
            exit_z = c.z
    log("  hat axis through (%.4f, %.4f) at z=%.3f, leant back %.0f deg"
        % (centre.x, centre.y, HAT_BRIM_Z, math.degrees(HAT_TILT)))
    log("  skull is %.3f across the brim plane -> crown base %.3f, brim %.3f"
        % (radius * 2.0, base, base + HAT_BRIM_WIDTH))
    log("  %d head vertices sit above the crown base (the antennae); the furthest "
        "stands %.3f m proud of the cloth, around z=%.2f — they come out through "
        "the front of the crown, which is deliberate" % (len(above), out, exit_z or 0.0))
    return centre, axis, side, up, base


def build_hat(centre, axis, side, up, base):
    crown = Piece("crown", UV_BANDS["crown"])
    droop_dir = (side * HAT_DROOP_DIR[0] + up * HAT_DROOP_DIR[1])
    droop_dir = (droop_dir - axis * droop_dir.dot(axis)).normalized()

    def spine_point(t):
        bend = 0.0
        if t > HAT_DROOP_START:
            u = (t - HAT_DROOP_START) / (1.0 - HAT_DROOP_START)
            bend = HAT_DROOP * u ** 2.4
        return centre + axis * (HAT_HEIGHT * t) + droop_dir * bend

    def frame_at(t):
        step = 1e-3
        tangent = (spine_point(min(1.0, t + step)) - spine_point(max(0.0, t - step)))
        tangent.normalize()
        a = side - tangent * side.dot(tangent)
        if a.length < 1e-5:
            a = up - tangent * up.dot(tangent)
        a.normalize()
        b = tangent.cross(a).normalized()
        return spine_point(t), a, b

    starts = []
    for ring in range(HAT_CROWN_RINGS + 1):
        t = ring / HAT_CROWN_RINGS
        origin, a, b = frame_at(t)
        r = max(HAT_TIP_RADIUS, base * (1.0 - t) ** HAT_TAPER)
        points = []
        for i in range(HAT_SEGMENTS):
            theta = 2.0 * math.pi * i / HAT_SEGMENTS
            points.append(origin + (a * math.cos(theta) + b * math.sin(theta)) * r)
        starts.append(crown.add_ring(points, [{HEAD_BONE: 1.0}] * HAT_SEGMENTS))
    for ring in range(HAT_CROWN_RINGS):
        crown.stitch(starts[ring], starts[ring + 1], HAT_SEGMENTS,
                     crown.band_v(ring / HAT_CROWN_RINGS),
                     crown.band_v((ring + 1) / HAT_CROWN_RINGS),
                     sharp=(ring == 0))
    # Close the tip with a fan rather than leaving a hole a camera can look down.
    tip = len(crown.verts)
    crown.verts.append(spine_point(1.0) + axis * 0.004)
    crown.weights.append({HEAD_BONE: 1.0})
    last = starts[-1]
    for i in range(HAT_SEGMENTS):
        j = (i + 1) % HAT_SEGMENTS
        crown.faces.append((last + i, last + j, tip))
        crown.uvs.extend([(i / HAT_SEGMENTS, crown.band_v(1.0)),
                          ((i + 1) / HAT_SEGMENTS, crown.band_v(1.0)),
                          ((i + 0.5) / HAT_SEGMENTS, crown.band_v(1.0))])

    brim = Piece("brim", UV_BANDS["brim"])
    starts = []
    for ring in range(HAT_BRIM_RINGS + 1):
        s = ring / HAT_BRIM_RINGS
        points = []
        for i in range(HAT_SEGMENTS):
            theta = 2.0 * math.pi * i / HAT_SEGMENTS
            wave = math.cos(HAT_BRIM_WAVE_LOBES * theta + 0.8)
            drop = (HAT_BRIM_DROP + HAT_BRIM_WAVE * wave) * s ** 1.6
            lift = HAT_BRIM_LIP * s ** 7.0
            r = base + HAT_BRIM_WIDTH * s
            points.append(centre
                          + (side * math.cos(theta) + up * math.sin(theta)) * r
                          + axis * (lift - drop))
        starts.append(brim.add_ring(points, [{HEAD_BONE: 1.0}] * HAT_SEGMENTS))
    for ring in range(HAT_BRIM_RINGS):
        brim.stitch(starts[ring], starts[ring + 1], HAT_SEGMENTS,
                    brim.band_v(ring / HAT_BRIM_RINGS),
                    brim.band_v((ring + 1) / HAT_BRIM_RINGS),
                    sharp=(ring in (0, HAT_BRIM_RINGS - 1)))
    return crown, brim


# ---------------------------------------------------------------------------
# 4. One object out of the pieces
# ---------------------------------------------------------------------------

def assemble(arm, pieces, name="Elder"):
    verts, faces, uvs, weights, sharp = [], [], [], [], set()
    for piece in pieces:
        offset = len(verts)
        verts.extend(piece.verts)
        weights.extend(piece.weights)
        for face in piece.faces:
            faces.append(tuple(i + offset for i in face))
        uvs.extend(piece.uvs)
        sharp |= set(frozenset(i + offset for i in e) for e in piece.sharp)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate(verbose=False)
    mesh.update()

    layer = mesh.uv_layers.new(name="UVMap")
    flat = []
    for uv in uvs:
        flat.extend(uv)
    if len(flat) != len(mesh.loops) * 2:
        raise SystemExit("%d uv corners for %d loops — a face list and a uv list "
                         "have gone out of step" % (len(uvs), len(mesh.loops)))
    layer.uv.foreach_set("vector", flat)

    for poly in mesh.polygons:
        poly.use_smooth = True
    marked = 0
    for edge in mesh.edges:
        if frozenset(edge.vertices) in sharp:
            edge.use_edge_sharp = True
            marked += 1

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = arm
    obj.matrix_parent_inverse = Matrix.Identity(4)
    modifier = obj.modifiers.new("Armature", 'ARMATURE')
    modifier.object = arm

    groups = {}
    for index, weight in enumerate(weights):
        for bone, value in weight.items():
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([index], value, 'REPLACE')

    used = sorted(groups)
    log("  %s: %d verts, %d faces, %d tris, %d sharp edges"
        % (name, len(mesh.vertices), len(mesh.polygons),
           sum(len(p.vertices) - 2 for p in mesh.polygons), marked))
    log("  bound to %d bones: %s" % (len(used), ", ".join(used)))
    for piece in pieces:
        log("    %-6s %4d verts" % (piece.name, len(piece.verts)))

    worst = max(abs(sum(w.values()) - 1.0) for w in weights)
    if worst > 1e-5:
        raise SystemExit("a vertex's weights sum to %.6f, not 1" % (1.0 + worst))
    log("  every vertex's weights sum to 1 (worst error %.2g)" % worst)
    return obj


# ---------------------------------------------------------------------------
# 5. The textures, generated
#
# glTF carries images and flat factors. A Noise Texture node would not survive
# the export at all, so the value variation, the trim and the runes are all
# rasterised here with numpy and packed into the GLB as two PNGs. Everything is
# authored in sRGB 0-1 and written into a byte-buffer image, which Blender stores
# verbatim — no colour transform between what is written here and what ends up in
# the file.
# ---------------------------------------------------------------------------

def value_noise(shape, cells, seed):
    """Smooth tiling noise in [0, 1], bilinear over a `cells`-square lattice."""
    rng = np.random.default_rng(seed)
    lattice = rng.random((cells + 1, cells + 1))
    lattice[-1, :] = lattice[0, :]        # tile horizontally: u wraps around the
    lattice[:, -1] = lattice[:, 0]        # robe and a visible seam is a stripe
    lattice[-1, -1] = lattice[0, 0]
    ys = np.linspace(0.0, cells, shape[0], endpoint=False)
    xs = np.linspace(0.0, cells, shape[1], endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy = fy * fy * (3.0 - 2.0 * fy)
    fx = fx * fx * (3.0 - 2.0 * fx)
    a = lattice[y0][:, x0]
    b = lattice[y0][:, x0 + 1]
    c = lattice[y0 + 1][:, x0]
    d = lattice[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy)
            + c * (1 - fx) * fy + d * fx * fy)


def stamp(target, colour, mask):
    """Composite `colour` over `target` through a 0-1 mask."""
    m = np.clip(mask, 0.0, 1.0)[:, :, None]
    target *= (1.0 - m)
    target += m * np.asarray(colour, dtype=np.float32)[None, None, :]


def segment_mask(shape, points, width, closed=False):
    """Antialiased polyline, as a distance field thresholded at `width`."""
    ys = np.arange(shape[0], dtype=np.float32)[:, None]
    xs = np.arange(shape[1], dtype=np.float32)[None, :]
    best = np.full(shape, 1e9, dtype=np.float32)
    pairs = list(zip(points, points[1:] + ([points[0]] if closed else [])))
    for (x0, y0), (x1, y1) in pairs:
        dx, dy = x1 - x0, y1 - y0
        length = dx * dx + dy * dy
        if length < 1e-6:
            continue
        t = np.clip(((xs - x0) * dx + (ys - y0) * dy) / length, 0.0, 1.0)
        px = x0 + t * dx - xs
        py = y0 + t * dy - ys
        best = np.minimum(best, np.sqrt(px * px + py * py))
    return np.clip(width - best + 0.5, 0.0, 1.0)


def ring_mask(shape, cx, cy, radius, width):
    ys = np.arange(shape[0], dtype=np.float32)[:, None]
    xs = np.arange(shape[1], dtype=np.float32)[None, :]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    return np.clip(width - np.abs(d - radius) + 0.5, 0.0, 1.0)


def glyph(shape, cx, cy, size, kind, width):
    """One arcane mark. Five shapes, chosen by `kind`, all built from lines."""
    s = size
    if kind == 0:      # six-point star
        pts = []
        for k in range(6):
            a = math.pi * k / 3.0
            pts.append((cx + s * math.cos(a), cy + s * math.sin(a)))
        return np.maximum(
            segment_mask(shape, [pts[0], pts[2], pts[4]], width, closed=True),
            segment_mask(shape, [pts[1], pts[3], pts[5]], width, closed=True))
    if kind == 1:      # eye / vesica
        return np.maximum(
            segment_mask(shape, [(cx - s, cy), (cx, cy - s * 0.8), (cx + s, cy)], width),
            segment_mask(shape, [(cx - s, cy), (cx, cy + s * 0.8), (cx + s, cy)], width))
    if kind == 2:      # circled cross
        return np.maximum(
            ring_mask(shape, cx, cy, s * 0.8, width),
            segment_mask(shape, [(cx - s, cy), (cx + s, cy)], width))
    if kind == 3:      # forked rune
        return np.maximum(
            segment_mask(shape, [(cx, cy - s), (cx, cy + s)], width),
            np.maximum(
                segment_mask(shape, [(cx, cy - s * 0.1), (cx + s * 0.8, cy - s * 0.8)], width),
                segment_mask(shape, [(cx, cy + s * 0.2), (cx - s * 0.8, cy + s * 0.9)], width)))
    # chevron stack
    return np.maximum(
        segment_mask(shape, [(cx - s, cy - s * 0.5), (cx, cy + s * 0.2),
                             (cx + s, cy - s * 0.5)], width),
        segment_mask(shape, [(cx - s, cy + s * 0.2), (cx, cy + s * 0.9),
                             (cx + s, cy + s * 0.2)], width))


def make_textures(edge):
    """(base colour, emissive) as float arrays, both sRGB 0-1, top row = v 1."""
    base = np.zeros((edge, edge, 3), dtype=np.float32)
    glow = np.zeros((edge, edge, 3), dtype=np.float32)
    base[:, :] = np.asarray(CLOTH_MID, dtype=np.float32)

    rows = np.arange(edge, dtype=np.float32)
    # Blender's images run bottom-up; v = 0 is the last row of this array.
    v = 1.0 - (rows + 0.5) / edge
    u = (np.arange(edge, dtype=np.float32) + 0.5) / edge

    def band_rows(name):
        lo, hi = UV_BANDS[name]
        return np.where((v >= lo - 0.012) & (v <= hi + 0.012))[0]

    # --- the value ramp. One expression over the whole atlas: each band is
    # mapped back to "how far up this piece is" so the shoulders of the robe and
    # the top of the brim get the same lift.
    height = np.zeros(edge, dtype=np.float32)
    for name, (lo, hi) in UV_BANDS.items():
        rows_in = (v >= lo - 0.012) & (v <= hi + 0.012)
        t = np.clip((v - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
        if name == "brim":
            t = 1.0 - t * 0.45          # a brim is lit from above at its root
        height = np.where(rows_in, t, height)

    ramp = np.clip(height, 0.0, 1.0)[:, None, None]
    deep = np.asarray(CLOTH_DEEP, dtype=np.float32)[None, None, :]
    mid = np.asarray(CLOTH_MID, dtype=np.float32)[None, None, :]
    high = np.asarray(CLOTH_HIGH, dtype=np.float32)[None, None, :]
    lower = deep + (mid - deep) * np.clip(ramp / 0.45, 0.0, 1.0)
    upper = mid + (high - mid) * np.clip((ramp - 0.45) / 0.55, 0.0, 1.0)
    # One column so far — the ramp is a function of v alone — so it is widened
    # to the full image before anything that varies with u touches it.
    base = np.where(ramp < 0.45, lower, upper).astype(np.float32)
    base = np.ascontiguousarray(np.broadcast_to(base, (edge, edge, 3)))

    # --- the folds, in the same phase as the geometry's. u is theta / 2pi
    # everywhere on the robe, and `FOLD_PHASE` and `FOLDS` are the modelled
    # values, so a painted valley lands in a modelled valley.
    wave = 0.5 - 0.5 * np.cos(FOLDS * 2.0 * math.pi * u + FOLD_PHASE)
    fold_depth = np.clip(1.0 - height, 0.0, 1.0)[:, None]      # deepest at the hem
    base *= (1.0 - 0.20 * (wave[None, :] * fold_depth))[:, :, None]

    # --- grain. Two octaves, ±3%, which at this size is a weave rather than a
    # pattern anyone can point at.
    grain = (value_noise((edge, edge), 48, 11) * 0.6
             + value_noise((edge, edge), 180, 12) * 0.4)
    base *= (0.94 + 0.12 * grain)[:, :, None]

    glow[:, :] = np.asarray(CLOTH_GLOW, dtype=np.float32)

    # --- trim bands and runes.
    rng = np.random.default_rng(FIT_SEED)
    trim = np.asarray(TRIM, dtype=np.float32)
    marks = 0

    def draw_band(centre_v, thickness, glyph_size, count, with_rules=True):
        nonlocal marks
        row = (1.0 - centre_v) * edge
        half = thickness * edge * 0.5
        if with_rules:
            for offset in (-half, half):
                mask = segment_mask((edge, edge),
                                    [(0.0, row + offset), (float(edge), row + offset)],
                                    TRIM_RULE_WIDTH)
                stamp(base, trim, mask * 0.85)
                stamp(glow, RUNE, mask * 0.55)
        for k in range(count):
            cx = (k + 0.5) * edge / count
            kind = int(rng.integers(0, 5))
            mask = glyph((edge, edge), cx, row, glyph_size, kind, GLYPH_WIDTH)
            stamp(base, trim, mask * 0.9)
            stamp(glow, RUNE, mask)
            marks += 1

    robe_lo, robe_hi = UV_BANDS["robe"]
    draw_band(robe_lo + (robe_hi - robe_lo) * 0.075, 0.055, 14.0, 14)
    draw_band(robe_lo + (robe_hi - robe_lo) * 0.955, 0.030, 9.0, 12)
    # Scattered on the body of the robe, sparse enough to read as marks rather
    # than as a pattern.
    for k in range(14):
        cv = robe_lo + (robe_hi - robe_lo) * float(rng.uniform(0.22, 0.85))
        cu = float(rng.uniform(0.0, 1.0))
        mask = glyph((edge, edge), cu * edge, (1.0 - cv) * edge,
                     float(rng.uniform(9.0, 15.0)), int(rng.integers(0, 5)),
                     GLYPH_WIDTH)
        stamp(base, trim, mask * 0.55)
        stamp(glow, RUNE, mask * 0.75)
        marks += 1
    cowl_lo, cowl_hi = UV_BANDS["cowl"]
    draw_band(cowl_hi - (cowl_hi - cowl_lo) * 0.12, 0.020, 7.0, 14)
    crown_lo, crown_hi = UV_BANDS["crown"]
    draw_band(crown_lo + (crown_hi - crown_lo) * 0.10, 0.026, 9.0, 10)
    for k in range(9):
        cv = crown_lo + (crown_hi - crown_lo) * float(rng.uniform(0.25, 0.8))
        mask = glyph((edge, edge), float(rng.uniform(0.0, 1.0)) * edge,
                     (1.0 - cv) * edge, 9.0, int(rng.integers(0, 5)), GLYPH_WIDTH)
        stamp(base, trim, mask * 0.5)
        stamp(glow, RUNE, mask * 0.8)
        marks += 1
    brim_lo, brim_hi = UV_BANDS["brim"]
    draw_band(brim_hi - (brim_hi - brim_lo) * 0.18, 0.012, 6.0, 18)

    log("  textures %dx%d: %d rune glyphs, %d trim bands, folds at %d lobes in "
        "phase with the geometry" % (edge, edge, marks, 5, FOLDS))
    return np.clip(base, 0.0, 1.0), np.clip(glow, 0.0, 1.0), marks


def make_image(name, pixels):
    """A byte-buffer sRGB image with `pixels` written into it verbatim.

    `float_buffer=False` matters: Blender stores byte images as the bytes they
    are and applies no colour transform through `Image.pixels`, so the sRGB
    values authored above are the sRGB values in the PNG. On a float buffer the
    same assignment would be read as scene-linear and the robe would export two
    stops too dark.
    """
    edge = pixels.shape[0]
    image = bpy.data.images.new(name, edge, edge, alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'sRGB'
    # ...and Godot names an extracted texture `<glb>_<image>`, while the exporter
    # takes the image's *name* from its filepath when it has one. Both point at
    # the same file, so it is set here rather than left to chance.
    image.filepath_raw = "//%s.png" % name
    image.file_format = 'PNG'
    rgba = np.ones((edge, edge, 4), dtype=np.float32)
    rgba[:, :, :3] = pixels[::-1]      # Blender's row 0 is the bottom of the image
    image.pixels.foreach_set(rgba.reshape(-1))
    image.pack()
    return image


def build_material(obj, emission, edge):
    """One Principled BSDF, built from scratch over the two generated images."""
    base_px, glow_px, _marks = make_textures(edge)
    base_img = make_image("basecolor", base_px)
    glow_img = make_image("emissive", glow_px)

    material = bpy.data.materials.new("elder")
    material.use_nodes = True
    # Double-sided: the skirt is a cone with an open bottom and the cowl is an
    # open sheet, and both are seen from the inside — from a camera below the
    # waist and from behind the head. Culling them costs one draw's worth of
    # overdraw on 5,000 triangles and buys two holes.
    material.use_backface_culling = False
    tree = material.node_tree
    tree.nodes.clear()

    base = tree.nodes.new("ShaderNodeTexImage")
    base.image = base_img
    base.location = (-560, 150)
    glow = tree.nodes.new("ShaderNodeTexImage")
    glow.image = glow_img
    glow.location = (-560, -220)
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-100, 0)
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (220, 0)

    tree.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    bsdf.inputs["Emission Strength"].default_value = emission
    if emission > 0.0:
        tree.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
    else:
        # Wiring it at zero still exports an emissiveTexture with a black factor,
        # which Godot turns into an enabled-but-black emission: a second texture
        # fetch per fragment that can never do anything. `--emission 0` is meant
        # to give back a plain base-colour PBR material, so the socket is left
        # alone instead. (The same trap `build_gub.py` documents.)
        bpy.data.images.remove(glow_img)

    obj.data.materials.append(material)
    log("  material 'elder': base #%02X%02X%02X, folds to #%02X%02X%02X, trim "
        "#%02X%02X%02X, runes #%02X%02X%02X"
        % tuple(int(round(c * 255)) for c in CLOTH_MID + CLOTH_DEEP + TRIM + RUNE))
    log("  roughness %.2f, metallic %.2f, emission %.2f%s, double-sided"
        % (ROUGHNESS, METALLIC, emission,
           "" if emission > 0.0 else " (not wired)"))
    return material


# ---------------------------------------------------------------------------
# 6. Does it hold together? — the check the hem needs
# ---------------------------------------------------------------------------

def use_action(arm, action):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    if action is not None and len(action.slots):
        arm.animation_data.action_slot = action.slots[0]


def action_span(action):
    lo = hi = None
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fcurve in bag.fcurves:
                    for kp in fcurve.keyframe_points:
                        lo = kp.co.x if lo is None else min(lo, kp.co.x)
                        hi = kp.co.x if hi is None else max(hi, kp.co.x)
    return int(round(lo)), int(round(hi))


def tracked_vertices(gub, elder, dominant):
    """The Gub vertices that start the rest pose inside the robe.

    Those are the ones the robe has undertaken to cover; anything that leaves is
    a poke-through. Starting from "inside in rest" rather than from "below the
    waist" is what keeps the enormous feet — which are outside the hem from the
    first frame and are *supposed* to be — out of the count.
    """
    bvh = BVHTree.FromObject(elder, bpy.context.evaluated_depsgraph_get())
    inside = []
    for vert in gub.data.vertices:
        name = dominant[vert.index]
        if any(m in name for m in ARM_MARKERS) or name == HEAD_BONE:
            continue
        found = bvh.find_nearest(vert.co)
        if found[0] is None:
            continue
        if (vert.co - found[0]).dot(found[1]) < 0.0:
            inside.append(vert.index)
    rng = np.random.default_rng(FIT_SEED)
    if len(inside) > FIT_SAMPLE:
        picked = sorted(rng.choice(len(inside), FIT_SAMPLE, replace=False))
        inside = [inside[i] for i in picked]
    return inside


def fit_report(arm, gub, elder, actions, dominant, boundary):
    """Play every clip and measure what comes out of the cloth, and how.

    Two very different things read as "outside the robe". A foot below the hem is
    outside it and is meant to be — that is what a hem *is*. A knee through the
    front of a skirt is the failure. They are told apart by where the nearest
    cloth to the escaped vertex is: anything that left through an opening has the
    open edge itself as its nearest surface, because the cloth stops there. So a
    nearest point sitting on the hem ring means "came out from under", and one in
    the middle of a panel means "came through it".
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    use_action(arm, None)
    bpy.context.scene.frame_set(1)
    depsgraph.update()
    tracked = tracked_vertices(gub, elder, dominant)
    log("  tracking %d Gub vertices that start inside the robe, every %d frames"
        % (len(tracked), FIT_FRAME_STEP))

    rows = []
    for clip in sorted(actions):
        action = actions[clip]
        use_action(arm, action)
        first, last = action_span(action)
        worst, worst_at, worst_bone = 0.0, 0.0, ""
        hem_count, wall_count, samples = 0, 0, 0
        for frame in range(first, last + 1, FIT_FRAME_STEP):
            bpy.context.scene.frame_set(frame)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            cloth = BVHTree.FromObject(elder, depsgraph)
            worn = elder.evaluated_get(depsgraph).to_mesh()
            edges = kdtree.KDTree(len(boundary))
            for slot, index in enumerate(boundary):
                edges.insert(worn.vertices[index].co, slot)
            edges.balance()
            elder.evaluated_get(depsgraph).to_mesh_clear()

            body = gub.evaluated_get(depsgraph).to_mesh()
            try:
                for index in tracked:
                    point = body.vertices[index].co
                    found = cloth.find_nearest(point)
                    if found[0] is None:
                        continue
                    signed = (point - found[0]).dot(found[1])
                    samples += 1
                    if signed <= FIT_TOLERANCE:
                        continue
                    if edges.find(found[0])[2] < HEM_EDGE_NEAR:
                        hem_count += 1
                        continue
                    wall_count += 1
                    if signed > worst:
                        worst = signed
                        worst_at = (frame - first) / FPS
                        worst_bone = dominant[index]
            finally:
                gub.evaluated_get(depsgraph).to_mesh_clear()
        rows.append((clip, 100.0 * wall_count / max(samples, 1),
                     100.0 * hem_count / max(samples, 1), worst, worst_at,
                     worst_bone))
    use_action(arm, None)
    bpy.context.scene.frame_set(1)

    log()
    log("  of the tracked vertices, per frame, the share that is outside the robe:")
    log("  clip         through a panel   under the hem   deepest panel poke")
    for clip, wall, hem, worst, at, bone in sorted(
            rows, key=lambda r: (r[0] not in EXTREME_CLIPS, r[0])):
        mark = "   <-- extreme" if clip in EXTREME_CLIPS else ""
        log("  %-11s  %6.2f%%          %6.2f%%        %6.3f m at %5.3f s (%s)%s"
            % (clip, wall, hem, worst, at, bone or "-", mark))
    log("  'under the hem' is a leg appearing from below the skirt, which is what")
    log("  a hem is for; 'through a panel' is the cloth being walked through.")
    return rows


def head_swing(arm, actions):
    """How far the skull turns away from the chest, which is the cowl's risk.

    The cowl's top edge finishes COWL_GAP from a head it only follows
    COWL_HEAD_SHARE of the way. If the Head bone barely moves against Spine2 in
    these clips that is free; if it swings, the number belongs in the log next to
    the share it was chosen against.
    """
    worst = 0.0
    worst_clip = ""
    for clip, action in actions.items():
        use_action(arm, action)
        first, last = action_span(action)
        # The head's rotation *in the chest's frame*, compared with the same
        # thing in the rest pose. Reading a Euler angle off either bone on its
        # own would report the whole body turning as a head turn.
        rest = (arm.data.bones["Spine2"].matrix_local.to_quaternion().inverted()
                @ arm.data.bones[HEAD_BONE].matrix_local.to_quaternion())
        for frame in range(first, last + 1, 2):
            bpy.context.scene.frame_set(frame)
            head = arm.pose.bones[HEAD_BONE].matrix.to_quaternion()
            chest = arm.pose.bones["Spine2"].matrix.to_quaternion()
            deviation = rest.inverted() @ (chest.inverted() @ head)
            angle = abs(wrap_pi(deviation.angle))
            if angle > worst:
                worst, worst_clip = angle, clip
    use_action(arm, None)
    bpy.context.scene.frame_set(1)
    log("  head turns at most %.1f deg against the chest (in %s); the cowl's top "
        "edge follows it %.0f%% of the way and stands %.0f mm off it"
        % (math.degrees(worst), worst_clip, COWL_HEAD_SHARE * 100.0,
           COWL_GAP * 1000.0))
    return worst


# ---------------------------------------------------------------------------
# 7. Export, and proving the bind
# ---------------------------------------------------------------------------

def export_glb(arm, elder, gub, path):
    """Robe, hat and a rest-pose copy of the skeleton. No animation.

    The Gub's own mesh and its material go first: the Elder's file exists to be
    bound onto a Gub that is already in the scene, and shipping a second copy of
    the body and its 115 KB texture inside it would be exactly the duplication
    this whole approach is for. `export_def_bones=False` keeps all 49 bones, so
    the joint list in this file is the joint list in `gub.glb` and the comparison
    below has something to compare.
    """
    bpy.data.objects.remove(gub, do_unlink=True)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)
    if arm.animation_data is not None:
        arm.animation_data.action = None
        for track in list(arm.animation_data.nla_tracks):
            arm.animation_data.nla_tracks.remove(track)

    if not os.path.isdir(os.path.dirname(path)):
        os.makedirs(os.path.dirname(path))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=False,
        use_visible=False,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_skins=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_influence_nb=4,
        export_all_influences=False,
        export_rest_position_armature=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_morph=False,
    )
    return os.path.getsize(path)


def joint_rests(path):
    """{joint name: (world rest matrix, inverse bind matrix)} out of a GLB."""
    sys.path.insert(0, os.path.join(REPO, "tools"))
    from gltf_io import Gltf                                   # noqa: E402

    gltf = Gltf.load(path)
    doc = gltf.doc
    nodes = doc["nodes"]

    def local(node):
        if "matrix" in node:
            return np.asarray(node["matrix"], dtype=np.float64).reshape(4, 4).T
        out = np.eye(4)
        if "scale" in node:
            out = np.diag(list(node["scale"]) + [1.0]) @ out
        if "rotation" in node:
            x, y, z, w = node["rotation"]
            rot = np.array([
                [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
                [0, 0, 0, 1]])
            out = rot @ out
        if "translation" in node:
            trs = np.eye(4)
            trs[:3, 3] = node["translation"]
            out = trs @ out
        return out

    world = {}

    def walk(index, parent):
        node = nodes[index]
        matrix = parent @ local(node)
        world[index] = matrix
        for child in node.get("children", []):
            walk(child, matrix)

    roots = set(range(len(nodes)))
    for node in nodes:
        for child in node.get("children", []):
            roots.discard(child)
    for index in sorted(roots):
        walk(index, np.eye(4))

    skin = doc["skins"][0]
    ibm = np.asarray(gltf.read_accessor(skin["inverseBindMatrices"]),
                     dtype=np.float64).reshape(-1, 4, 4)
    out = {}
    for slot, index in enumerate(skin["joints"]):
        name = nodes[index].get("name", "joint%d" % index)
        out[name] = (world[index], ibm[slot].T)
    return out


def verify_bind(out_path, source_path):
    """Prove the Elder can wear the Gub's skeleton, rather than assume it.

    Godot binds a `Skin` to a `Skeleton3D` by bone *name* and then draws each
    vertex through `bone_global_pose * bind_pose`. That is only the right answer
    if the two skeletons agree about where every bone rests — and a round trip
    through Blender's glTF importer and exporter is exactly the kind of thing
    that can quietly change a bone's axes. So both files' joint rest transforms
    and inverse bind matrices are read back and compared bone for bone. A
    disagreement here is a robe that would deform around a subtly different body,
    and it stops the build.
    """
    elder = joint_rests(out_path)
    gub = joint_rests(source_path)
    missing = sorted(set(gub) - set(elder))
    extra = sorted(set(elder) - set(gub))
    if missing or extra:
        raise SystemExit("joint lists differ: %d missing (%s), %d extra (%s)"
                         % (len(missing), ", ".join(missing[:4]),
                            len(extra), ", ".join(extra[:4])))
    worst_rest, worst_bind, worst_name = 0.0, 0.0, ""
    for name, (rest, bind) in elder.items():
        other_rest, other_bind = gub[name]
        rest_error = float(np.max(np.abs(rest - other_rest)))
        bind_error = float(np.max(np.abs(bind - other_bind)))
        if rest_error > worst_rest:
            worst_rest, worst_name = rest_error, name
        worst_bind = max(worst_bind, bind_error)
    log("  %d joints, same names and the same order as gub.glb" % len(elder))
    log("  rest transforms agree within %.2g (worst: %s); inverse bind matrices "
        "within %.2g" % (worst_rest, worst_name, worst_bind))
    if max(worst_rest, worst_bind) > 1e-4:
        raise SystemExit(
            "the Elder's skeleton does not match the Gub's (%.3g) — a mesh bound "
            "to this skin would deform around a different body, so it cannot be "
            "attached to a Gub's Skeleton3D at runtime. Export a whole "
            "gub_elder.glb variant instead." % max(worst_rest, worst_bind))


# ---------------------------------------------------------------------------

def parse_args(argv):
    """`--emission FLOAT`, the one lever, as `build_gub.py` does it.

    Blender stops parsing at `--` and hands the rest over; `build_elder.sh` adds
    a `--` of its own, so both `build_elder.sh --emission 2` and
    `build_elder.sh -- --emission 2` work and a bare separator is skipped rather
    than counted.
    """
    emission = EMISSION_DEFAULT
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    i = 0
    while i < len(argv):
        if argv[i] == "--":
            i += 1
        elif argv[i] == "--emission" and i + 1 < len(argv):
            emission = float(argv[i + 1])
            i += 2
        else:
            raise SystemExit("usage: build_elder.py [-- --emission FLOAT] (got %r)"
                             % argv[i])
    return emission


def main():
    started = time.time()
    emission = parse_args(list(sys.argv))
    log("=== build_elder  Blender %s, emission %.2f, %d-segment rings, %d² textures"
        % (bpy.app.version_string, emission, SEGMENTS, TEXTURE_EDGE))

    log("\n-- the Gub")
    arm, gub, actions = import_gub()
    dominant = dominant_groups(gub)
    axis = report_rest(arm, gub)
    points = body_points(gub, dominant)

    log("\n-- silhouette")
    profile, raw = robe_radii(points, axis)
    report_profile(profile, raw, axis)

    log("\n-- robe")
    robe, boundary = build_robe(profile, axis)
    cowl = build_cowl(profile, axis, points)
    log("  hem at z=%.3f r=%.3f, collar at z=%.3f, %d folds %.0f%% deep at the hem"
        % (HEM_Z, HEM_RADIUS, TOP_Z, FOLDS, FOLD_DEPTH * 100.0))
    log("  cowl over the back %.0f deg, rising %.3f m to z=%.3f"
        % (math.degrees(COWL_ARC * 2.0), COWL_RISE, TOP_Z + COWL_RISE))
    log("  skirt carries %.0f%% thigh weight at the hem, none above z=%.3f"
        % (LEG_SHARE_MAX * 100.0, LEG_SHARE_TOP))

    log("\n-- hat")
    centre, hat_axis, side, up, base = hat_frame(gub, dominant)
    crown, brim = build_hat(centre, hat_axis, side, up, base)
    tip = centre + hat_axis * HAT_HEIGHT
    log("  crown %.3f m tall, drooping %.3f m from %.0f%% up; tip reaches z=%.3f "
        "so the Elder stands %.3f m to the Gub's 1.800"
        % (HAT_HEIGHT, HAT_DROOP, HAT_DROOP_START * 100.0, tip.z, tip.z))

    log("\n-- assemble")
    elder = assemble(arm, [robe, cowl, crown, brim])

    log("\n-- material")
    build_material(elder, emission, TEXTURE_EDGE)

    log("\n-- fit")
    head_swing(arm, actions)
    fit_report(arm, gub, elder, actions, dominant, boundary)

    log("\n-- export")
    size = export_glb(arm, elder, gub, OUT_PATH)
    log("  wrote %s  %.2f MB"
        % (os.path.relpath(OUT_PATH, REPO).replace("\\", "/"), size / 1e6))

    log("\n-- bind")
    verify_bind(OUT_PATH, SOURCE_PATH)

    log("\ndone in %.1f s." % (time.time() - started))


if __name__ == "__main__":
    main()
