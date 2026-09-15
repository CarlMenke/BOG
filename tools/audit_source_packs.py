"""Audit a folder of hand-downloaded Mixamo FBX before `build_gub.py` ever opens one.

    "$BLENDER" --background --python tools/audit_source_packs.py
    "$BLENDER" --background --python tools/audit_source_packs.py -- 5_Locomotion

Every clip in this game arrives the same way: somebody opens Mixamo, applies an
animation to *the Gub as uploaded*, downloads it by hand, and drops the file in a
folder under `assets/source/`. `build_gub.py` then refuses to build unless every
one of those files shares a body with `GUB_2/Idle.fbx` — same vertex count, same
bone list, same vertex groups, bind poses agreeing to 1e-5
(`assert_same_character`). That check is correct and it is not going anywhere.

What it is not is a *diagnosis*. A pack downloaded with the wrong settings fails
`import_sources` one file at a time with

    expected 1 armature, 1 mesh and 1 action, got 1/0/1

which is true, and which does not say the words "you downloaded this Without
Skin". Worse, a pack can only be checked at all once somebody has written a
`Clip(...)` line for every file in it — and choosing which clips to declare is
the thing you wanted the measurements *for*. That is the gap this script fills:
it measures files the table has never heard of, says what is wrong with them in
the vocabulary of the Mixamo download dialog, and never writes anything.

What it reports, and why each column is the one that matters:

*Skin.* The single most likely thing to be wrong, and the least visible. Mixamo's
download dialog offers "With Skin" and "Without Skin", and a **pack** download —
selecting several animations in My Assets and downloading them together — ships
the skinned mesh in exactly one file and the rest as skeleton-and-animation only.
Those skinless files are not merely "missing a mesh you could ignore": with no
skin cluster in the file there are no bind matrices, so Blender's FBX importer
falls back to each node's own local transform and builds a **different rest
pose** — bone heads up to a quarter of a metre out and bone rolls tens of degrees
off, at the same scale and with the same bone names. Pose-bone rotation curves
are expressed relative to the rest pose, so `consolidate()`'s retarget-by-name
would land plausible-looking numbers on the wrong axes. There is no rescue
cheaper than downloading the clip again With Skin, which is why this is the first
column and why a failure here says so in one sentence.

*Travel.* The column the locomotion work lives on. Mixamo's "In Place" checkbox
strips the root motion, and this pipeline **needs** it: `lock_root_motion` throws
the travel away only after `measure_clip` has read the speed the clip was drawn
at, and that speed is what `gub.gd` matches its playback rate to so the feet grip
instead of skating. `AUTHORED_RUN = 4.314` is that measurement on `GUB_2/Run.fbx`
and nothing else. A locomotion clip that reports 0.000 m here was downloaded In
Place and is unusable for that no matter how good it looks — so travel is printed
for every clip, with the implied speed beside it, before anybody picks one.

Both the end-to-end travel and the furthest the hips get from where they started
are printed, because they answer different questions. A cycle's end-to-end number
is its authored speed. A one-shot that ends where it began — a turn in place, a
react, most attacks — has no speed but may still lunge, and the peak is what says
how far.

*Bearing.* Where those metres go, in degrees off the body's own forward, positive
to its left — read off the hip line and off the chest line, because on a sidestep
those two disagree by more than twenty degrees and the game's strafes are aligned
by the chest (D-066). This is the column that decides whether a sideways clip
belongs at a sideways pole, and it is **not knowable from the filename**:
`StandingRunLeft.fbx` and `StandingRunRight.fbx` sound like a pair and measure
+76.5 and −45.9, which cost three downloads to find out (D-071).

It is also the one measurement here that a **skinless** file does not ruin, and
that is worth more than it sounds. A missing skin rebuilds the rest pose, so
absolute positions and the bind delta are worthless — but this is a clip's travel
against its *own* chest line, and both halves move together. **Eight** files
exist in this tree twice over, skinned in `5_Locomotion/` and skinless in
`_rejected/`, and every one of the eight reproduces to 0.1° either way.

So a rejected pack can be shopped from on this column alone, without
re-downloading anything first. That is what `_rejected/MANIFEST.md`'s handedness
table was built from, and it is the difference between three speculative
downloads and one measured one (D-071).

*Bind pose.* Reported twice: raw, which is what `assert_same_character` actually
tests, and again after normalising out a uniform scale difference. Two numbers
rather than one because they mean opposite things. If the raw delta is large and
the normalised delta collapses, the rig is the same and something rescaled it. If
both stay large, it is a different rig — a stock Mixamo character, a second
upload of the Gub, a pack from somewhere else — and no re-download of *that* file
helps, because the file was never the Gub.

Nothing here writes to the repo, invokes Godot, or needs a `Clip(...)` to exist.
It is safe to run on a folder somebody has just unzipped into, which is the
moment it is for.
"""

import math
import os
import sys

import bpy

# Matching build_gub.py, because every number printed here is meant to be
# comparable with the numbers that build prints.
FPS = 60
PREFIX = "mixamorig:"
HIPS = PREFIX + "Hips"
TARGET_HEIGHT = 1.80

# The one pair of joints that stays put while the arms and torso animate, which
# is why build_gub.py measures facing between them and why a scale ratio is
# measured between them here.
HIP_JOINTS = (PREFIX + "LeftUpLeg", PREFIX + "RightUpLeg")

# The other line a clip's facing can be read off — the two clavicle roots. Both
# are printed because on a sidestep they disagree by more than twenty degrees and
# the strafes in the game are aligned by the chest (D-066), so the hip figure
# alone would not be the number a blend point is placed from.
CHEST_JOINTS = (PREFIX + "LeftShoulder", PREFIX + "RightShoulder")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_ROOT = os.path.join(REPO, "assets", "source")
REFERENCE = os.path.join(SOURCE_ROOT, "GUB_2", "Idle.fbx")

# Below this, a clip's hips finished where they started: it does not travel.
STILL = 0.05

WITHOUT_SKIN = (
    "downloaded Without Skin. A Mixamo *pack* download — several animations "
    "selected in My\n    Assets and downloaded together — puts the skinned mesh "
    "in one file of the pack and\n    ships the rest as skeleton and animation "
    "only. With no skin cluster there are no bind\n    matrices, so the importer "
    "rebuilds a different rest pose (different bone heads, "
    "different\n    rolls) and the rotation curves no longer mean the same thing "
    "on the Gub's skeleton.\n    Download each clip again With Skin; there is no "
    "fix that does not involve doing that."
)


def log(msg=""):
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Layered-action plumbing, the same shape build_gub.py uses
# ---------------------------------------------------------------------------

def iter_fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fcurve in bag.fcurves:
                    yield fcurve


def action_frame_span(action):
    lo, hi = None, None
    for fcurve in iter_fcurves(action):
        for kp in fcurve.keyframe_points:
            lo = kp.co.x if lo is None else min(lo, kp.co.x)
            hi = kp.co.x if hi is None else max(hi, kp.co.x)
    return (0, 0) if lo is None else (int(round(lo)), int(round(hi)))


def import_one(path):
    """One file into an empty scene. Returns (armatures, meshes, actions)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    bpy.ops.import_scene.fbx(filepath=path, use_anim=True)
    return ([o for o in bpy.data.objects if o.type == 'ARMATURE'],
            [o for o in bpy.data.objects if o.type == 'MESH'],
            list(bpy.data.actions))


def hip_span(arm):
    a = arm.data.bones[HIP_JOINTS[0]].head_local
    b = arm.data.bones[HIP_JOINTS[1]].head_local
    return (a - b).length


# ---------------------------------------------------------------------------
# The reference body
# ---------------------------------------------------------------------------

def read_reference():
    """GUB_2/Idle.fbx, and the factor that turns its import units into metres."""
    if not os.path.isfile(REFERENCE):
        raise SystemExit("the reference body is not in the tree: %s" % REFERENCE)
    arms, meshes, _ = import_one(REFERENCE)
    arm, mesh = arms[0], meshes[0]
    world = arm.matrix_world.copy()
    zs = [(world @ v.co).z for v in mesh.data.vertices]
    ref = {
        "bones": [b.name for b in arm.data.bones],
        "groups": sorted(g.name for g in mesh.vertex_groups),
        "verts": len(mesh.data.vertices),
        "matrices": dict((b.name, [list(r) for r in b.matrix_local])
                         for b in arm.data.bones),
        # The same factor scale_to_height derives, so travel comes out in the
        # metres the build log and gub.gd talk in.
        "factor": TARGET_HEIGHT / (max(zs) - min(zs)),
        "span": hip_span(arm),
    }
    log("  reference %s: %d verts, %d bones, %d vertex groups"
        % (os.path.relpath(REFERENCE, SOURCE_ROOT).replace("\\", "/"),
           ref["verts"], len(ref["bones"]), len(ref["groups"])))
    return ref


# ---------------------------------------------------------------------------
# One file
# ---------------------------------------------------------------------------

def audit_file(path, ref):
    row = {"problems": []}
    arms, meshes, actions = import_one(path)
    row["meshes"] = len(meshes)
    row["actions"] = len(actions)

    if len(arms) != 1 or len(meshes) != 1 or len(actions) != 1:
        row["problems"].append(
            "import_sources wants 1 armature, 1 mesh and 1 action; this is %d/%d/%d"
            % (len(arms), len(meshes), len(actions)))
    if not meshes:
        row["skinless"] = True
    if not arms:
        row["problems"].append("no armature at all")
        return row

    arm = arms[0]
    row["bones"] = len(arm.data.bones)
    row["verts"] = len(meshes[0].data.vertices) if meshes else 0
    names = [b.name for b in arm.data.bones]
    row["bones_match"] = names == ref["bones"]
    if not row["bones_match"]:
        row["problems"].append("bone list differs from the reference")
    if meshes:
        if row["verts"] != ref["verts"]:
            row["problems"].append("%d verts, the reference has %d"
                                   % (row["verts"], ref["verts"]))
        if sorted(g.name for g in meshes[0].vertex_groups) != ref["groups"]:
            row["problems"].append("vertex groups differ from the reference")

    # Bind pose, raw and with a uniform scale divided out. See the docstring:
    # the pair of numbers is the diagnosis, either one alone is not.
    if row["bones_match"]:
        ratio = ref["span"] / hip_span(arm)
        row["ratio"] = ratio
        raw = norm = 0.0
        for name in ref["bones"]:
            a = ref["matrices"][name]
            b = arm.data.bones[name].matrix_local
            for r in range(4):
                for c in range(4):
                    raw = max(raw, abs(a[r][c] - b[r][c]))
                    scaled = b[r][c] * ratio if (c == 3 and r < 3) else b[r][c]
                    norm = max(norm, abs(a[r][c] - scaled))
        row["bind_raw"], row["bind_norm"] = raw, norm
        if raw > 1e-5:
            row["problems"].append(
                "bind pose is %.3g from the reference, past the 1e-5 "
                "assert_same_character allows" % raw)

    if not actions:
        return row

    # Travel. Sampled off the posed rig rather than read off the Hips fcurve,
    # because that is what measure_clip does and the two must agree.
    action = actions[0]
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    if len(action.slots):
        arm.animation_data.action_slot = action.slots[0]
    first, last = action_frame_span(action)
    row["frames"] = last - first + 1
    row["seconds"] = (last - first) / float(FPS)

    metres = ref["factor"] * row.get("ratio", 1.0)
    scene = bpy.context.scene
    points = []
    yaws = {HIP_JOINTS: [], CHEST_JOINTS: []}
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        points.append((arm.matrix_world @ arm.pose.bones[HIPS].matrix)
                      .translation.copy())
        for pair in yaws:
            left = (arm.matrix_world @ arm.pose.bones[pair[0]].matrix).translation
            right = (arm.matrix_world @ arm.pose.bones[pair[1]].matrix).translation
            yaws[pair].append(math.atan2(right.y - left.y, right.x - left.x))
    row["travel"] = math.hypot(points[-1].x - points[0].x,
                               points[-1].y - points[0].y) * metres
    row["peak"] = max(math.hypot(p.x - points[0].x, p.y - points[0].y)
                      for p in points) * metres
    row["rise"] = (max(p.z for p in points) - points[0].z) * metres
    row["speed"] = (row["travel"] / row["seconds"]) if row["seconds"] else 0.0

    # Where those metres go, off each of the two body lines (D-071). This is the
    # column that decides whether a sideways clip belongs at a sideways pole, and
    # it is not knowable from the filename: `StandingRunLeft.fbx` and
    # `StandingRunRight.fbx` sound like a pair and measure +76.5 and -45.9.
    #
    # It is also the one measurement here that survives a **skinless** file
    # intact, which is what makes it worth printing for everything. A missing
    # skin rebuilds the rest pose, so absolute positions and the bind delta are
    # ruined — but this is a clip's travel against *its own* chest line, and both
    # halves move together. Measured against the skinned copies of two files that
    # are in `_rejected/` twice over, the skinless reading reproduces to 0.1°, so
    # a rejected pack can be shopped from on this column without re-downloading
    # it first.
    if row["travel"] > STILL:
        travel = math.atan2(points[-1].y - points[0].y, points[-1].x - points[0].x)
        for pair, key in ((HIP_JOINTS, "hip_bearing"), (CHEST_JOINTS, "chest_bearing")):
            mean = math.atan2(sum(math.sin(y) for y in yaws[pair]) / len(yaws[pair]),
                              sum(math.cos(y) for y in yaws[pair]) / len(yaws[pair]))
            # Forward is the body line turned a quarter turn, the construction
            # `measure_clip` and `align_facing` both use.
            row[key] = math.degrees(
                (travel - (mean + math.pi / 2.0) + math.pi) % (2.0 * math.pi) - math.pi)
    return row


# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    where = os.path.join(SOURCE_ROOT, argv[0]) if argv else SOURCE_ROOT
    if not os.path.isdir(where):
        raise SystemExit("not a folder under assets/source: %s" % where)

    paths = []
    for dirpath, _dirs, files in os.walk(where):
        for name in sorted(files):
            if name.lower().endswith(".fbx"):
                paths.append(os.path.join(dirpath, name))
    paths.sort()
    if not paths:
        raise SystemExit("no .fbx anywhere under %s" % where)

    log("-- reference")
    ref = read_reference()
    log()
    log("-- %d files under %s" % (len(paths), os.path.relpath(where, REPO)))
    log()

    width = max(len(os.path.relpath(p, SOURCE_ROOT)) for p in paths)
    width = min(width, 62)
    log("  %-*s  skin  frames  length  travel    peak   speed   bearing: hips  chest"
        % (width, "file"))
    rows = []
    for path in paths:
        rel = os.path.relpath(path, SOURCE_ROOT).replace("\\", "/")
        row = audit_file(path, ref)
        row["file"] = rel
        rows.append(row)
        log("  %-*s  %-4s  %6s  %6s  %6s  %6s  %6s   %12s %6s"
            % (width, rel[-width:], "no" if row.get("skinless") else "yes",
               row.get("frames", "-"),
               "%.3f" % row["seconds"] if "seconds" in row else "-",
               "%.3f" % row["travel"] if "travel" in row else "-",
               "%.3f" % row["peak"] if "peak" in row else "-",
               "%.3f" % row["speed"] if "speed" in row else "-",
               "%+.1f" % row["hip_bearing"] if "hip_bearing" in row else "-",
               "%+.1f" % row["chest_bearing"] if "chest_bearing" in row else "-"))

    # The verdict, grouped: a hand-downloaded batch goes wrong the same way for
    # every file in it, so saying it once per file would bury it.
    skinless = [r for r in rows if r.get("skinless")]
    still = [r for r in rows if r.get("travel", 1.0) < STILL]
    broken = [r for r in rows if r["problems"] and not r.get("skinless")]

    log()
    log("-- verdict")
    if skinless:
        log("  %d of %d files carry no mesh — %s"
            % (len(skinless), len(rows), WITHOUT_SKIN))
        for r in skinless:
            log("      %s" % r["file"])
    if broken:
        log("  %d files fail for another reason:" % len(broken))
        for r in broken:
            log("      %-*s %s" % (width, r["file"], "; ".join(r["problems"])))
    if still:
        log("  %d clips do not travel (hips finish within %.2f m of where they "
            "started)." % (len(still), STILL))
        log("      An idle, a turn in place or a react should be in this list. A "
            "walk, run or")
        log("      strafe in it was downloaded with In Place ticked, and no "
            "authored speed can be")
        log("      measured from it — see AUTHORED_RUN in gub.gd.")
        for r in still:
            log("      %-*s peak %.3f m" % (width, r["file"], r.get("peak", 0.0)))
    if not skinless and not broken:
        log("  every file shares a body with the reference and would import.")

    bad = len(skinless) + len(broken)
    log()
    log("  %d of %d files would fail build_gub.py as they are." % (bad, len(rows)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
