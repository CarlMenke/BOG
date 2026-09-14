"""Look at a raw Mixamo FBX before anybody writes a `Clip(...)` line for it.

    "$BLENDER" --background --python tools/preview_clips.py -- FILE [FILE ...]
    bash tools/preview_clips.sh 2_Spear_Suite/SpearThrowLonger.fbx

Every animation in this game has so far been chosen by reading a table of
numbers, because a downloaded `.fbx` cannot be *looked at* until somebody
declares it in `PACKS` in `build_gub.py` and runs a full build. "Which of these
two throws reads better?" therefore cost a code edit, a 14 s build, a Godot
import and a snapshot — so in practice it was answered off a speed graph
instead, by somebody who is not an animator and should not have to be. This
script is the other half of `tools/audit_source_packs.py`: that one measures
files the table has never heard of, this one *renders* them. Neither writes
anything into the repo, neither declares a clip, and neither touches
`art/generated/`.

It takes any number of `.fbx` under `assets/source/` — including inside
`_rejected/`, which is where the fallbacks live — and writes one PNG contact
sheet with a row per clip. The three-row, twelve-column spear sheet that step 4
of `docs/PLAN_COMBAT.md` is waiting on takes **9.5 s end to end**, seven FBX
imports and the render included.

What it does, and why each choice is the one it is:

*It renders in Blender, not in Godot.* `tools/preview_anim.gd` is the same idea
one stage later: it works on *built* clips, out of `art/generated/gub.glb`, and
getting a raw download that far is the whole cost this exists to remove. Going
through Godot would also mean an `.import` per PNG in a tree where several
agents share `.godot/`. Blender is already open for the FBX and renders the
whole sheet in one pass — thirty-six posed bodies, 317k triangles, one camera —
and the thing being judged is a silhouette, which is not a thing Godot renders
better.

*The source is corrected the way the build corrects it, by calling the build's
own functions.* A raw Mixamo FBX is 9.5 mm tall, rotated 90° about X, prefixed
`mixamorig:` and sitting at an arbitrary resting yaw, and a sheet of *that* is a
sheet of something the game will never show. So `build_gub.py` is imported (not
copied, and never edited) and four of its stages are run per clip, in its order:

  `strip_bone_prefix`  — cosmetic on a picture, but it is what makes every bone
                         name below the same string the pipeline uses.
  `scale_to_height`    — 1.80 m, the import transform baked into the rest data,
                         and the location-fcurve fix Blender will not do for you
                         (×1.903149 on every one of these files). Without it
                         every distance printed on the sheet is in armature
                         units.
  `align_facing`       — the clips were authored at different resting yaws, and
                         at their own releases `GUB_2/Throw` sits −4.63° off the
                         rest facing while `2_Spear_Suite/SpearThrowLonger` sits
                         +14.06°. Uncorrected, two candidates for one slot stand
                         at 18.7° to each other and a column cannot be read down.
  `lock_root_motion`   — with a synthetic clip whose `rise_kept` is None, so the
                         two horizontal axes clamp to the first key and the
                         vertical is left alone. This is what stops a clip that
                         travels 2.842 m from walking out of its own cell — and
                         it is also what the *game* does, so the sheet shows the
                         lunge that survives rather than the run-up that does
                         not.

Five things the build does that this **deliberately does not**:

  *The vertical rule.* `rise_kept`/`floor_limit` is a judgement written per clip
  in `PACKS` (JumpOne clamps, JumpTwo does not, and the docstring there argues
  both). An undeclared clip has no answer, and inventing one would put a pose on
  the sheet that no build would produce.
  *`assert_same_character`.* It is a hard stop in the build, and here it would
  refuse to render exactly the clip somebody most needs to look at. The check is
  still *run* — the auditor runs it — it just turns the row red instead of
  exiting.
  *The material.* Silhouette beats texture for this decision (below), and
  Workbench takes its colour from the object, so the packed 2048² JPEG is never
  unpacked. That is also most of why the render is fast.
  *The loop-tail trim and CrouchIdle.* Neither means anything for a one-shot.
  *Writing anything.* No GLB, no `.import`, no `PACKS` entry, no decision.

*Frames are chosen around the moment being judged, not spread evenly.*
`GUB_2/Throw` is 3.833 s. Six evenly spaced samples of it land at 0.00, 0.77,
1.53, 2.30, 3.07 and 3.83 s — one of them within 0.11 s of the release and the
other five looking at a Gub standing still. So the default layout is a **burst**
of 7 frames across 0.36 s centred on the interesting moment, plus 6 **context**
frames spread over the rest, with any context frame that lands inside the burst
window dropped as a duplicate. Every offset is snapped to a real 60 fps key —
the sheet never shows an interpolation — and every cell is labelled with its own
clip time.

*The interesting moment is detected, printed, and overridable.* For a throw it
is peak hand speed measured **relative to the hips**, which is the measurement
step 4 of `docs/PLAN_COMBAT.md` is written on, and it is hip-relative on
purpose: a clip that travels 2.842 m has a hand doing metres per second in world
space while it is merely being carried. Both hands are measured and the faster
one wins, so a two-handed sword swing does not have to be told which arm to
watch. Measured here, in m/s on the 1.80 m rig, against a 3-frame central
difference, with each peak divided by the mean speed over the quarter-second
either side of it:

    GUB_2/Throw                     right hand  9.81 m/s at 1.633 s   2.02x
    2_Spear_Suite/SpearThrow        right hand  9.11 m/s at 1.617 s   1.84x
    2_Spear_Suite/SpearThrowLonger  right hand  9.88 m/s at 1.583 s   1.73x
    GreatSwordHighSpinAttack        right hand  6.81 m/s at 1.067 s   1.61x
    Great Sword Pack/GreatSwordAttack  left hand 5.30 m/s at 0.450 s  2.59x

The first row reproduces the 1.633 s the plan quotes for `GUB_2/Throw`, and the
third lands one frame from the 1.600 s it quotes for `SpearThrowLonger`, off a
different rig scale and a different differencing window — which is the check
that the detector is finding a release and not a numerical artefact. The last
column is there because **the peak alone does not carry step 4's argument**: that
step's case is not that the new clip's hand is faster (9.88 against 9.81 is
nothing) but that its peak is *a sharp isolated spike rather than a broad
plateau*. Measured that way it does not hold up — `SpearThrowLonger` is the
*flattest* of the three — and the sheet is what settles what that means.

It settled it (D-063): the clip was taken anyway, because what makes its release
legible is a **silhouette change** and not a speed. The shaft goes up over the
head at arm's length and is gone a sixth of a second later, which is a thing this
script draws and the speed column cannot say. Note also that the detected moment
is the peak *speed* and the release the game uses is the peak *reach* — 1.600 and
1.567 on that clip, one frame apart and not the same criterion. `--focus` is how
you look at the other one.
`--focus 1.2` overrides the detector for every clip; `--focus 1.633,1.6,1.6`
overrides it per clip, in the order the files were given.

*Comparison is the point, so the offsets are shared and measured from each
clip's own release.* Column 7 of the spear sheet is "the release" for all three
rows even though that is 1.633 s of one clip and 1.583 s of another, and the
poses under it can be compared by eye. The span defaults to the largest window
inside **every** clip — `min(focus)` before and `min(length − focus)` after — so
no column is ever a real frame in one row and a clamped one in another.
`--pre`/`--post` override it, and a cell that then falls off the end of a clip
says so rather than going blank.

*Rows after the first carry their distance from row one, and the test is on the
spread.* Both hands, relative to the hips, at the sheet's own column offsets,
minimised over a shift of up to 0.12 s — because two exports of one motion can
put their releases a frame apart and comparing frame N against frame N+1 charges
that frame up as "difference". Measured, `2_Spear_Suite/SpearThrow` holds
0.055–0.057 m from `GUB_2/Throw` over the whole sheet: **2 mm of variation**,
which is a constant offset and therefore one motion exported twice, exactly as
step 4 says. `SpearThrowLonger` runs 0.089–0.766 m over the same columns. The
threshold is on the 2 mm, not on the 56 mm, because a threshold between 0.06 and
0.09 would be a coincidence and this one is not.

*The measurements come from the auditor, and a clip that would fail says so on
the sheet.* `audit_source_packs.audit_file` is called on every file before
anything is staged, so the length, travel, implied speed and same-character
verdict on the sheet are the same numbers `tools/audit_source_packs.py` prints,
not a second opinion that can drift. Travel is that script's end-to-end
displacement of the hips with its furthest-from-the-start figure beside it,
because a one-shot that returns to where it began still lunges (`GUB_2/Throw`:
0.858 m end to end, 1.227 m at its furthest). A file that would fail the build
turns its whole row red and names the failure, because a beautiful clip off the
wrong upload is the one fault that looks perfect in a picture.

*A file with no mesh is drawn as its skeleton rather than refused.* Most of
`assets/source/_rejected/` — 105 of its 110 files, including step 9's fallback
`Great Sword Pack/GreatSwordAttack.fbx` — was downloaded Without Skin and has no
mesh at all. Refusing those would make this useless on the one folder that is
entirely candidates-not-taken. So the bones are drawn as bars between their
joints, scaled by the hip span instead of by a mesh height (the substitution the
auditor already makes), in red, under a row that says what is wrong with it.
What it must not do is *pretend*: a skinless file has no bind matrices, Blender
rebuilds a different rest pose — measured at 1.39 against the 1e-5
`assert_same_character` allows — and putting the Gub's body on it would draw a
confident, wrong figure. Bars are the honest picture, and step 9's question
("in-place swing, or spinning advance?") is a gross-motion question they answer.

*The render is lit, not silhouetted, and this is the argument that went the
other way.* The game is read across a clearing, so the silhouette is what
matters and `--mode flat` is one flag away — Workbench FLAT light, one colour
per object, a true shape-on-a-ground with no shading in it at all. It is not the
default, because the question this was built to answer is "is the release a
plant and a full extension", and that is a question about the *lead leg crossing
in front of the trailing one* and about where the throwing arm is relative to
the head. A solid shape cannot show either: front and back are the same blob and
a limb in front of the torso is the same blob as a limb behind it. The default
is a matte untextured clay under raking studio light with screen-space cavity
on — a silhouette with just enough form to read depth, and still untextured and
one colour, so the outline keeps the argument. Judge the *shape* on `--mode
flat` and the *pose* on the default; the two sheets are ten seconds apart, so
the answer is to look at both.

*The camera is three-quarters, from the Gub's throwing side.* Straight on, a
right-handed throw swings the arm directly at the lens and its arc foreshortens
to nothing — the release frame looks like the frames either side of it, which is
the exact complaint step 4 exists to fix. Side on, the arc is at its longest but
the chest is edge-on, so the shoulder-to-hip separation that makes a javelin
wind-up read is invisible and the far arm spends the clip behind the torso. 35°
off the front keeps both, on the side the throwing arm is on (the rest pose
looks along −Y with its right hand toward −X, so a positive azimuth swings that
way). The elevation is 12°, about where a player's camera sits at range, so "are
the feet planted" is still a fair question of the picture. `--azimuth` and
`--elevation` move it; 0/0 is dead front and 90 is a true side view.

The projection is **orthographic**, for the reason `tools/preview_anim.gd` gives
at greater length: under perspective the end cells of a 24 m sheet are seen from
far further round than the middle ones, so a clip whose facing never changes
appears to swing across the sheet — and "do these poses face the same way" is
one of the questions being asked. Columns are laid out along the camera's own
horizontal axis, so twelve columns are evenly spaced at any azimuth; rows stack
in world Z, so each row's floor is a real horizontal line a foot either touches
or does not.

*A fixed camera cannot show 364.9° of yaw, so the yaw is drawn.* Step 9's
candidate `GreatSwordHighSpinAttack` turns the body through a full revolution
and ends 4.9° from where it started, which on a still sheet makes its first and
last frames look identical and its middle ones look like a stumble. So when a
clip's **net** turn passes 45°, every cell gets a compass on the floor — a ring
with an arrow pointing where the hip line points at that instant — and the
*unwrapped* turn in the cell's label. Unwrapped is the whole point: that clip's
sheet reads −19° to +390° across twelve cells, and +390° is the number somebody
choosing it needs rather than the +30° a wrapped angle would print. The trigger
is net turn rather than "how far it swings", because every throw in the game
winds its hips through 90–160° and comes back — `GUB_2/Throw` reaches 98.0° from
its release pose and finishes 0.1° from where it started — and a compass under
all twelve cells of that is twelve dials saying the same thing. A clip that
genuinely turns and returns is the case this misses, and `--yaw` is how to ask
for it. Turning it on also lifts the camera to 24°, because a floor compass seen
from 12° is edge-on.

Nothing here writes to the repo except the PNG, and that goes to `out/`, which
is gitignored.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# `build_gub.py` is the pipeline and is imported, never edited and never copied:
# the whole value of this sheet is that what it shows is what a build would
# produce, and a second copy of `scale_to_height` would be a second copy that
# goes stale. `audit_source_packs.py` is imported for the same reason — its
# `audit_file` is the measurement code, and the numbers printed on the sheet have
# to be the same numbers that script prints or one of them is lying.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_gub as pipeline          # noqa: E402
import audit_source_packs as auditor  # noqa: E402

REPO = pipeline.REPO
SOURCE_ROOT = pipeline.SOURCE_ROOT
OUT_DIR = os.path.join(REPO, "out")
FPS = pipeline.FPS

# The two hands, because a sword is swung with both and a throw with one, and
# asking "which hand is doing the interesting thing" is cheaper than a flag.
HANDS = ("RightHand", "LeftHand")

# Frame layout. See the docstring: the burst is the moment being judged and the
# context is everything that makes it legible as a motion rather than a pose.
BURST = 7
BURST_SPAN = 0.36
CONTEXT = 6

# The grid, in metres of world space. A Gub is 1.80 m tall and about 1.7 m wide
# with an arm extended, so 1.55 m of column pitch lets a follow-through overlap
# its neighbour slightly rather than leaving a corridor of empty floor between
# every pose — the poses are what is being compared, not the gaps.
COL_PITCH = 1.55
ROW_PITCH = 2.85
# A row reaches from its own floor up to the top of its time stamp; ROW_PITCH is
# that plus the gap that keeps one row's feet clear of the labels below it.
CELL_TOP = 2.35
# Room at the left for each row's name and its measurements, and along the top
# for the title, the subtitle and the column headers.
GUTTER = 4.8
HEADER = 1.45
COLHEAD = 0.50
FOOT = 0.35
MARGIN = 0.7

# Blender's default font has it, and every label here that carries an angle
# needs it. Named rather than inlined so the file stays legible on a terminal
# that does not.
DEGREE = "\u00b0"

# Pixels per metre of world space. 160 puts the 1.80 m Gub at 288 px tall, which
# is enough to see a knee cross a knee and not so much that a twelve-column sheet
# stops fitting on a screen.
SCALE = 160
MAX_WIDTH = 8000

# Camera. The arguments for both of these are in the docstring; they are here as
# numbers so `--azimuth 0` is visibly a departure from a default rather than from
# nothing. Positive azimuth swings toward the Gub's right, which is the throwing
# side.
AZIMUTH = 35.0
ELEVATION = 12.0
# A floor compass seen from 12° is edge-on and useless, so a sheet that draws one
# lifts the camera unless the camera was asked for explicitly.
ELEVATION_YAW = 24.0

# A clip whose *net* turn exceeds this gets the compass. Net rather than "how far
# it swings", because every throw in the game swings its hips through 90-160° of
# wind-up and comes back — `GUB_2/Throw` reaches 98.0° from its release pose and
# finishes 0.1° from where it started, and a compass under all twelve cells of
# that is twelve dials that all say the same thing. A clip that genuinely turns
# and returns (a dodge, a 180 and back) is the case this misses, and `--yaw`
# is how to ask for it.
YAW_TRIGGER = math.radians(45.0)

# When two rows are one motion exported twice. The test is on the **spread**, not
# on the size of the gap, and that is the whole of the argument step 4 of
# `docs/PLAN_COMBAT.md` makes: *"A gap that barely varies is the same motion
# shifted by export, not a different animation."* Measured here,
# `2_Spear_Suite/SpearThrow` against `GUB_2/Throw` holds 0.055 m at its closest
# and 0.057 m at its worst — 2 mm of variation over the whole sheet — while
# `SpearThrowLonger` runs from 0.10 m to 0.77 m. A threshold on the gap alone
# would have to sit between 0.06 and 0.10 and would be a coincidence; a
# threshold on 2 mm against 670 mm is not.
SAME_MOTION = 0.20
SAME_MOTION_SPREAD = 0.03

# Object colours, by render mode. Workbench's OBJECT colour mode is what lets one
# render carry a clay body, a grey floor, dark text and a red failure without a
# single material being built.
PALETTE = {
    "lit": {
        "background": (0.930, 0.930, 0.940),
        "body":       (0.820, 0.790, 0.740, 1.0),
        "body_bad":   (0.880, 0.560, 0.520, 1.0),
        "ground":     (0.560, 0.580, 0.620, 1.0),
        "text":       (0.130, 0.140, 0.170, 1.0),
        "dim":        (0.360, 0.380, 0.420, 1.0),
        "accent":     (0.120, 0.360, 0.820, 1.0),
        "bad":        (0.780, 0.100, 0.070, 1.0),
        "outline":    (0.220, 0.230, 0.260),
    },
    "flat": {
        "background": (0.970, 0.970, 0.975),
        "body":       (0.090, 0.095, 0.110, 1.0),
        "body_bad":   (0.520, 0.080, 0.060, 1.0),
        "ground":     (0.700, 0.715, 0.740, 1.0),
        "text":       (0.130, 0.140, 0.170, 1.0),
        "dim":        (0.360, 0.380, 0.420, 1.0),
        "accent":     (0.120, 0.360, 0.820, 1.0),
        "bad":        (0.780, 0.100, 0.070, 1.0),
        "outline":    (0.220, 0.230, 0.260),
    },
}


def log(msg=""):
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Arguments
#
# Hand-rolled, the way `build_gub.parse_args` is, and for the same reason: Blender
# hands over whatever follows `--` and the wrapper adds a separator of its own, so
# bare `--` is skipped rather than counted.
# ---------------------------------------------------------------------------

USAGE = """usage: preview_clips.py -- FILE [FILE ...] [options]

  FILE                  an .fbx, absolute or relative to assets/source/ (or to
                        the repo root, or to where you are standing)

  --out PATH            where the PNG goes (default out/preview_<first clip>.png)
  --title TEXT          the heading on the sheet
  --mode lit|flat       lit clay (default) or a true silhouette
  --focus S[,S,...]     override the detected release; one value for every clip,
                        or one per clip in the order given
  --pre S / --post S    how far either side of the release the sheet reaches
                        (default: the largest window inside every clip)
  --burst N             frames in the dense burst (default %d)
  --burst-span S        seconds the burst covers (default %.2f)
  --context N           context frames outside the burst (default %d)
  --align focus|first|mean   which moment of each clip is made to face front
  --azimuth DEG         0 dead front, 90 a side view, + toward the throwing side
                        (default %.0f)
  --elevation DEG       camera height (default %.0f, or %.0f when a compass is drawn)
  --yaw / --no-yaw      force the floor compass on or off
  --scale PX            pixels per metre (default %d)
""" % (BURST, BURST_SPAN, CONTEXT, AZIMUTH, ELEVATION, ELEVATION_YAW, SCALE)


class Options(object):
    def __init__(self):
        self.files = []
        self.out = None
        self.title = None
        self.mode = "lit"
        self.focus = None
        self.pre = None
        self.post = None
        self.burst = BURST
        self.burst_span = BURST_SPAN
        self.context = CONTEXT
        self.align = "focus"
        self.azimuth = AZIMUTH
        self.elevation = None
        self.yaw = None
        self.scale = SCALE


def resolve_source(name):
    """An `.fbx` named however somebody had it on their clipboard.

    Three spellings all reach the same file and all three get pasted: the path
    the auditor prints (`2_Spear_Suite/SpearThrow.fbx`, relative to
    `assets/source/`), the path git prints (relative to the repo), and whatever
    the shell completed. Trying all of them costs nothing and saves the "not a
    file" round trip that otherwise happens once per person per day.
    """
    for candidate in (name,
                      os.path.join(SOURCE_ROOT, name),
                      os.path.join(REPO, name),
                      os.path.join(os.getcwd(), name)):
        if os.path.isfile(candidate):
            return os.path.abspath(candidate)
    raise SystemExit("no such .fbx: %s\n       looked in assets/source/, in the "
                     "repo root and where you are standing." % name)


def parse_args(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    opts = Options()
    i = 0
    while i < len(argv):
        arg = argv[i]
        nxt = argv[i + 1] if i + 1 < len(argv) else None

        def need(what):
            if nxt is None:
                raise SystemExit("%s wants a value\n\n%s" % (what, USAGE))
            return nxt

        if arg == "--":
            i += 1
        elif arg in ("-h", "--help"):
            # Printed and exited 0, not raised: a `SystemExit(str)` is exit code
            # 1, and `preview_clips.sh` would then tell somebody who asked for
            # the help text that Blender had failed.
            log(USAGE)
            sys.exit(0)
        elif arg == "--out":
            opts.out, i = need(arg), i + 2
        elif arg == "--title":
            opts.title, i = need(arg), i + 2
        elif arg == "--mode":
            opts.mode, i = need(arg), i + 2
            if opts.mode not in PALETTE:
                raise SystemExit("--mode is lit or flat, not %r" % opts.mode)
        elif arg == "--focus":
            opts.focus = [float(v) for v in need(arg).split(",")]
            i += 2
        elif arg == "--pre":
            opts.pre, i = float(need(arg)), i + 2
        elif arg == "--post":
            opts.post, i = float(need(arg)), i + 2
        elif arg == "--burst":
            opts.burst, i = int(need(arg)), i + 2
        elif arg == "--burst-span":
            opts.burst_span, i = float(need(arg)), i + 2
        elif arg == "--context":
            opts.context, i = int(need(arg)), i + 2
        elif arg == "--align":
            opts.align, i = need(arg), i + 2
            if opts.align not in ("focus", "first", "mean"):
                raise SystemExit("--align is focus, first or mean, not %r" % opts.align)
        elif arg == "--azimuth":
            opts.azimuth, i = float(need(arg)), i + 2
        elif arg == "--elevation":
            opts.elevation, i = float(need(arg)), i + 2
        elif arg == "--scale":
            opts.scale, i = int(need(arg)), i + 2
        elif arg == "--yaw":
            opts.yaw, i = True, i + 1
        elif arg == "--no-yaw":
            opts.yaw, i = False, i + 1
        elif arg.startswith("-"):
            raise SystemExit("unknown option %r\n\n%s" % (arg, USAGE))
        else:
            opts.files.append(arg)
            i += 1

    if not opts.files:
        raise SystemExit(USAGE)
    opts.files = [resolve_source(f) for f in opts.files]
    if opts.focus is not None and len(opts.focus) not in (1, len(opts.files)):
        raise SystemExit("--focus wants one value or one per clip (%d given for "
                         "%d clips)" % (len(opts.focus), len(opts.files)))
    return opts


# ---------------------------------------------------------------------------
# One clip, corrected the way the build corrects it
# ---------------------------------------------------------------------------

def shortname(path):
    """How a file is named on the sheet and in the log: pack/file, if it has one."""
    for root in (SOURCE_ROOT, REPO):
        if os.path.abspath(path).startswith(os.path.abspath(root) + os.sep):
            return os.path.relpath(path, root).replace("\\", "/")
    return os.path.basename(path)


def scale_armature(arm, actions, reference):
    """`scale_to_height` for a file that has no mesh to measure.

    The build scales by the mesh's own height, and a skinless file has no mesh —
    so the hip span stands in for it, which is the substitution
    `audit_source_packs.audit_file` already makes to report a skinless clip's
    travel in metres (`metres = ref["factor"] * ratio`). Same arithmetic, same
    reference body, so a skeleton row and a skinned row on one sheet are drawn at
    one scale. Everything else is `scale_to_height`'s tail: bake the transform
    into the rest data, put the object back at identity, and multiply every
    location fcurve by hand, because Blender does not.
    """
    left = arm.data.bones[pipeline.HIP_JOINTS[0]].head_local
    right = arm.data.bones[pipeline.HIP_JOINTS[1]].head_local
    ratio = reference["span"] / (left - right).length
    matrix = Matrix.Scale(reference["factor"] * ratio, 4) @ arm.matrix_world
    scale = matrix.to_scale().x
    arm.data.transform(matrix)
    arm.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    curves = 0
    for action in actions.values():
        for fcurve in pipeline.iter_fcurves(action):
            if not fcurve.data_path.endswith(".location"):
                continue
            for kp in fcurve.keyframe_points:
                kp.co.y *= scale
                kp.handle_left.y *= scale
                kp.handle_right.y *= scale
            fcurve.update()
            curves += 1
    log("  no mesh in this file: scaled by the hip span instead (ratio %.4f, "
        "%.6f in armature units), %d location fcurves" % (ratio, scale, curves))
    return scale


def import_corrected(path, name, reference):
    """Import one FBX and run the build stages that make it comparable.

    Returns (armature, mesh, action, ...), with `mesh` None for a file that was
    downloaded Without Skin — see `skeleton_snapshot`. Which stages run, and which
    deliberately do not, is the fourth section of the module docstring; the point
    of calling `build_gub`'s own functions rather than reimplementing them is that
    a sheet that disagrees with a build is worse than no sheet.
    """
    before_objects = set(bpy.data.objects.keys())
    before_actions = set(bpy.data.actions.keys())
    bpy.ops.import_scene.fbx(filepath=path, use_anim=True)
    objects = [bpy.data.objects[n] for n in bpy.data.objects.keys()
               if n not in before_objects]
    actions = [bpy.data.actions[n] for n in bpy.data.actions.keys()
               if n not in before_actions]
    arms = [o for o in objects if o.type == 'ARMATURE']
    meshes = [o for o in objects if o.type == 'MESH']
    if len(arms) != 1 or len(actions) != 1 or len(meshes) > 1:
        # A missing *mesh* is the one shape this carries on through, because it
        # is the commonest thing wrong with a hand-downloaded pack and the file it
        # is wrong with is usually the file somebody most wants to look at. The
        # auditor has already said why, in the vocabulary of the Mixamo download
        # dialog; anything else here is beyond what a picture can rescue.
        raise SystemExit("%s: expected 1 armature, at most 1 mesh and 1 action, "
                         "got %d/%d/%d — see the audit above."
                         % (name, len(arms), len(meshes), len(actions)))
    arm, action = arms[0], actions[0]
    mesh = meshes[0] if meshes else None
    table = {name: action}

    if mesh is None:
        # `strip_bone_prefix` takes the skinned *pair*, because normally there are
        # vertex groups carrying the same names. A file with no skin has no vertex
        # groups to fix, and an empty stand-in is how that is said to a function
        # whose contract is a pair — it reports "0 vertex groups fixed", which is
        # true.
        empty = bpy.data.objects.new("no-skin", bpy.data.meshes.new("no-skin"))
        pipeline.strip_bone_prefix(arm, empty, table)
        bpy.data.objects.remove(empty)
        scale_armature(arm, table, reference)
    else:
        pipeline.strip_bone_prefix(arm, mesh, table)
        pipeline.scale_to_height(arm, mesh, table)

    # A synthetic declaration, carrying only what the two stages below read: the
    # name for their error messages and `rise_kept=None`, which is `rise() == 1.0`
    # — the vertical left exactly as authored. Nothing here is written anywhere
    # and no clip becomes declared by it.
    declaration = pipeline.Clip(os.path.basename(path), name, False, 0.0)
    return arm, mesh, action, declaration, table


def hip_yaws(arm, action):
    """(times, yaw relative to the rest pose, unwrapped) for the hip line.

    Unwrapped on purpose: `GreatSwordHighSpinAttack` finishes 4.9° from where it
    started and has turned through 364.9° to get there, and the second number is
    the one somebody choosing the clip needs. `wrap_pi` on each *step* rather than
    on each value is what keeps the winding.
    """
    frames, tracks = pipeline.sample_bones(arm, action, pipeline.HIP_JOINTS)
    left, right = (tracks[pipeline.HIP_JOINTS[0]], tracks[pipeline.HIP_JOINTS[1]])
    rest = pipeline.rest_facing(arm)
    raw = [math.atan2(right[i].y - left[i].y, right[i].x - left[i].x)
           for i in range(len(frames))]
    out = [pipeline.wrap_pi(raw[0] - rest)]
    for i in range(1, len(raw)):
        out.append(out[-1] + pipeline.wrap_pi(raw[i] - raw[i - 1]))
    times = [(f - frames[0]) / float(FPS) for f in frames]
    return times, out


def hand_tracks(arm, action):
    """{hand: [position relative to the hips, per frame]}, plus the times.

    Relative to the hips rather than to the world, because a clip that travels
    2.892 m carries its hand along at the body's speed and would peak wherever the
    *body* is quickest. Everything step 4 of `docs/PLAN_COMBAT.md` measures is
    hip-relative for that reason.
    """
    bones = (pipeline.HIPS,) + HANDS
    frames, tracks = pipeline.sample_bones(arm, action, bones)
    hips = tracks[pipeline.HIPS]
    rel = dict((h, [tracks[h][i] - hips[i] for i in range(len(frames))])
               for h in HANDS)
    return [(f - frames[0]) / float(FPS) for f in frames], rel


# How far either side of the peak "the neighbourhood" reaches, when the peak is
# being asked whether it is a spike or a plateau. 0.25 s is about a third of a
# throw's whole delivery on these clips and comfortably wider than the burst.
NEIGHBOURHOOD = 0.25


def find_focus(times, rel):
    """The interesting moment: peak hip-relative hand speed, and which hand.

    A 3-frame central difference rather than a forward one. At 60 fps a single
    frame step is 17 ms of a motion that is being retargeted onto a body with
    different proportions, and the raw first difference has 1-frame spikes in it
    that move the answer by a frame or two; the central difference costs nothing
    and lands on the same time the plan's own coarse sampling found.

    The fourth number is the one step 4 of `docs/PLAN_COMBAT.md` is actually
    arguing about, and a bare peak does not carry it. That step's case for
    `SpearThrowLonger` is not that its hand is faster — measured here the two
    peaks are 9.81 and 9.88 m/s, which is nothing — it is that the peak is *a
    sharp isolated spike rather than a broad plateau*, and "a spike is what a
    visible release is made of". So the peak is divided by the mean speed over
    the quarter-second either side of it. A plateau scores near 1; a spike scores
    high; and the number is measured off the clip rather than asserted about it.
    """
    best = None
    for hand, points in rel.items():
        speeds = [0.0] * len(points)
        for i in range(1, len(points) - 1):
            speeds[i] = (points[i + 1] - points[i - 1]).length * FPS * 0.5
        peak = max(range(len(speeds)), key=lambda i: speeds[i])
        span = int(round(NEIGHBOURHOOD * FPS))
        near = [speeds[i] for i in range(max(1, peak - span),
                                         min(len(speeds) - 1, peak + span + 1))
                if abs(i - peak) > 1]
        sharp = speeds[peak] / (sum(near) / len(near)) if near else 0.0
        if best is None or speeds[peak] > best[1]:
            best = (hand, speeds[peak], times[peak], sharp)
    return best  # (hand, m/s, seconds, peak / its own neighbourhood)


# ---------------------------------------------------------------------------
# The columns
# ---------------------------------------------------------------------------

def choose_offsets(opts, clips):
    """The shared list of offsets from each clip's own release, in seconds.

    Shared, so column N is the same moment of every clip and the sheet can be
    read down as well as across. Snapped to whole 60 fps frames, so every cell is
    an authored key rather than an interpolation. And bounded by the *shortest*
    reach of any clip in the sheet unless told otherwise, so no column is ever a
    real pose in one row and a blank in another.
    """
    pre = opts.pre if opts.pre is not None else min(c["focus"] for c in clips)
    post = (opts.post if opts.post is not None
            else min(c["length"] - c["focus"] for c in clips))
    pre, post = max(pre, 0.0), max(post, 0.0)

    half = opts.burst_span * 0.5
    burst = []
    if opts.burst > 0:
        step = opts.burst_span / max(opts.burst - 1, 1)
        burst = [-half + step * i for i in range(opts.burst)]
        burst = [o for o in burst if -pre - 1e-6 <= o <= post + 1e-6]

    context = []
    if opts.context > 0:
        step = (pre + post) / max(opts.context - 1, 1)
        for i in range(opts.context):
            o = -pre + step * i
            # Dropped rather than kept: a context frame 20 ms from a burst frame
            # is a duplicate column that costs width and says nothing.
            if burst and -half - 1e-6 <= o <= half + 1e-6:
                continue
            context.append(o)

    frame = 1.0 / FPS
    offsets = sorted(round(o / frame) * frame for o in burst + context)
    # Snapping can collide two neighbours onto one frame.
    unique = []
    for o in offsets:
        if not unique or abs(o - unique[-1]) > frame * 0.5:
            unique.append(o)
    return unique, pre, post


# ---------------------------------------------------------------------------
# Scene furniture
# ---------------------------------------------------------------------------

def add(obj, colour):
    bpy.context.scene.collection.objects.link(obj)
    obj.color = colour
    return obj


def text(body, size, colour, location, rotation, align_x='CENTER', align_y='CENTER'):
    curve = bpy.data.curves.new("label", type='FONT')
    curve.body = body
    curve.size = size
    curve.align_x = align_x
    curve.align_y = align_y
    obj = bpy.data.objects.new("label", curve)
    obj.location = location
    obj.rotation_euler = rotation
    return add(obj, colour)


def bar(centre, size, colour):
    mesh = bpy.data.meshes.new("bar")
    sx, sy, sz = (s * 0.5 for s in size)
    verts = [(x * sx, y * sy, z * sz)
             for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("bar", mesh)
    obj.location = centre
    return add(obj, colour)


def compass(centre, yaw, colour):
    """A ring with an arrow in it, flat on the floor, pointing where the body points.

    The ring is what makes the arrow readable: seen from 24° a bare arrow is a
    short line whose length says as much as its direction does, and a ring gives
    the eye the circle the arrow is a radius of. Drawn as one mesh rather than
    two objects, so it is one colour and one draw.

    `yaw` is what `hip_yaws` returns — the hip line's angle relative to the rest
    pose, unwrapped — and the rest pose looks along -Y, so a yaw of zero must draw
    an arrow along -Y. Rotating (0,-1) by yaw gives (sin yaw, -cos yaw), and the
    template below has its nose at local +Y, so the template is turned by
    `yaw + pi`. Getting that constant wrong is the one way this can be worse than
    useless: an arrow that is confidently 90° off the body it sits under.
    """
    verts, faces = [], []
    outer, inner, steps = 0.78, 0.66, 44
    for i in range(steps):
        a = 2.0 * math.pi * i / steps
        verts.append((math.cos(a) * outer, math.sin(a) * outer, 0.0))
        verts.append((math.cos(a) * inner, math.sin(a) * inner, 0.0))
    for i in range(steps):
        j = (i + 1) % steps
        faces.append((i * 2, j * 2, j * 2 + 1, i * 2 + 1))
    base = len(verts)
    a = yaw + math.pi
    nose, wing, tail = 0.60, 0.26, -0.34
    for dx, dy in ((0.0, nose), (-wing, tail), (0.0, tail * 0.45), (wing, tail)):
        verts.append((dx * math.cos(a) - dy * math.sin(a),
                      dx * math.sin(a) + dy * math.cos(a), 0.0))
    faces.append((base, base + 1, base + 2))
    faces.append((base, base + 2, base + 3))
    mesh = bpy.data.meshes.new("compass")
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("compass", mesh)
    obj.location = centre
    return add(obj, colour)


# How thick a bone is drawn when a file has no skin and its skeleton is all there
# is to show, and how much of its own length a short bone is allowed to be. 2 cm
# reads at 160 px/m; the taper is what stops the 49-bone Mixamo hand — fifteen
# bones of two to four centimetres apiece — from rendering as one cube where the
# fist should be.
BONE_THICKNESS = 0.02
BONE_TAPER = 0.22


def skeleton_snapshot(arm, frame, location, colour):
    """One frame of an armature that has no mesh, drawn as bars between joints.

    A Mixamo *pack* download ships the skin in one file and the rest as skeleton
    and animation only, so most of `assets/source/_rejected/` — including step
    9's fallback, `Great Sword Pack/GreatSwordAttack.fbx` — has no mesh at all.
    Refusing to draw those would make this tool useless on the one folder that is
    entirely candidates-not-taken, and step 9's actual question ("is this an
    in-place swing or a spinning advance?") is a gross-motion question a stick
    figure answers perfectly well.

    What it must not do is *pretend*. A skinless file has no bind matrices, so
    Blender rebuilds a different rest pose — bone heads up to a quarter of a
    metre out, rolls tens of degrees off, measured at 1.39 against the 1e-5
    `assert_same_character` allows — and putting the Gub's mesh on it would draw a
    confident, wrong body. Bars between the joints it actually has are the honest
    picture: the limb the file describes, at the proportions the file describes,
    with the row shouting in red that it would not build.

    The whole skeleton is one mesh so it is one object, one colour and one draw.
    """
    scene = bpy.context.scene
    scene.frame_set(frame)
    graph = bpy.context.evaluated_depsgraph_get()
    posed = arm.evaluated_get(graph)
    world = posed.matrix_world
    up = Vector((0.0, 0.0, 1.0))
    verts, faces = [], []
    for bone in posed.pose.bones:
        head, tail = world @ bone.head, world @ bone.tail
        along = tail - head
        if along.length < 1e-6:
            continue
        axis = along.normalized()
        across = axis.cross(up)
        if across.length < 1e-4:
            across = axis.cross(Vector((0.0, 1.0, 0.0)))
        across.normalize()
        other = axis.cross(across)
        base = len(verts)
        thick = min(BONE_THICKNESS, along.length * BONE_TAPER)
        for sx, sy, t in ((-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0),
                          (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
            point = (head + along * t
                     + across * (sx * thick)
                     + other * (sy * thick))
            verts.append((point.x, point.y, point.z))
        for face in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                     (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            faces.append(tuple(base + i for i in face))
    mesh = bpy.data.meshes.new("skeleton")
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("skeleton", mesh)
    obj.location = location
    return add(obj, colour)


def snapshot(mesh_obj, frame, location, colour):
    """A static copy of the deformed mesh at one frame.

    This is what makes the whole sheet one render instead of thirty-six. Blender
    evaluates one frame at a time for the whole scene, so thirty-six posed Gubs
    cannot coexist as armatures — but they can as thirty-six frozen meshes, and
    `new_from_object` off the evaluated depsgraph is the armature modifier
    already applied. 8814 verts apiece; the spear sheet is 317k verts and
    Workbench does not notice.
    """
    bpy.context.scene.frame_set(frame)
    graph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh_obj.evaluated_get(graph)
    baked = bpy.data.meshes.new_from_object(evaluated, depsgraph=graph)
    obj = bpy.data.objects.new("pose", baked)
    obj.matrix_world = Matrix.Translation(location) @ mesh_obj.matrix_world
    return add(obj, colour)


# ---------------------------------------------------------------------------
# The sheet
# ---------------------------------------------------------------------------

def audit_all(paths):
    """Every file through `audit_source_packs.audit_file`, before anything renders.

    It imports each file into an emptied scene of its own, which is why this is a
    pass on its own and why it comes first: it would wipe the sheet out from under
    the renderer otherwise. The cost is that each FBX is opened twice (measured:
    2.1 s apiece). That is the price of the numbers on the sheet being the same
    numbers `tools/audit_source_packs.py` prints rather than a second opinion.
    """
    log("-- measuring, with audit_source_packs.audit_file")
    reference = auditor.read_reference()
    rows = []
    for path in paths:
        row = auditor.audit_file(path, reference)
        row["file"] = shortname(path)
        rows.append(row)
        log("  %-46s %-4s %6s  %6s s  travel %6s m  speed %6s m/s"
            % (row["file"], "no" if row.get("skinless") else "yes",
               row.get("frames", "-"),
               "%.3f" % row["seconds"] if "seconds" in row else "-",
               "%.3f" % row["travel"] if "travel" in row else "-",
               "%.3f" % row["speed"] if "speed" in row else "-"))
        for problem in row["problems"]:
            log("      WOULD FAIL THE BUILD: %s" % problem.split("\n")[0])
    return reference, rows


def prepare(opts, audits, reference):
    """Import, correct and measure every clip into the one scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0

    log()
    log("-- importing and correcting, with build_gub's own stages")
    clips = []
    for index, path in enumerate(opts.files):
        name = shortname(path)
        log("  %s" % name)
        arm, mesh, action, declaration, table = import_corrected(
            path, name, reference)
        first, last = pipeline.action_frame_span(action)

        times, rel = hand_tracks(arm, action)
        hand, peak, at, sharp = find_focus(times, rel)
        if opts.focus is not None:
            at = opts.focus[index if len(opts.focus) > 1 else 0]
            log("    focus overridden to %.3f s (detected %.3f s)" % (at, times[-1]))
        log("    peak hip-relative hand speed %.2f m/s (%s) at %.3f s, "
            "%.2fx its own neighbourhood" % (peak, hand, at, sharp))

        yaw_times, yaws = hip_yaws(arm, action)
        index_at = min(len(yaws) - 1, int(round(at * FPS)))
        turn = max(abs(y - yaws[index_at]) for y in yaws)
        net = yaws[-1] - yaws[0]
        log("    turns through %.1f° net, furthest %.1f° from the release pose"
            % (math.degrees(net), math.degrees(turn)))

        # Facing, using the build's own correction, at whichever moment the sheet
        # is being read down. `--align focus` is the default because the release
        # is the column everyone is looking at; `--align first` is what to ask for
        # when the question is "where does this clip start".
        moment = {"focus": at, "first": 0.0,
                  "mean": pipeline.LOOP_MEAN}[opts.align]
        pipeline.align_facing(arm, table, {name: moment})
        pipeline.lock_root_motion(action, declaration)

        clips.append({
            "name": name, "path": path, "arm": arm, "mesh": mesh,
            "action": action, "first": first, "last": last,
            "length": (last - first) / float(FPS),
            "focus": at, "hand": hand, "peak": peak, "sharp": sharp,
            "yaws": yaws, "turn": turn, "net": net,
            "rel": rel, "times": times,
            "audit": audits[index],
        })
    return clips


# How far the shift search below is allowed to slide one row against another
# before it gives up. A twelfth of a second: enough to absorb the frame or two
# that two exports of one motion disagree by, and far too little to make two
# genuinely different throws line up.
SHIFT_LIMIT = 0.12


def divergence(clips, offsets):
    """Each row against row one: how far apart the hands are, relative to the hips.

    This is the measurement `docs/PLAN_COMBAT.md` step 4 uses to say that
    `2_Spear_Suite/SpearThrow` is `GUB_2/Throw` re-downloaded rather than a second
    candidate — a gap that *barely varies* is the same motion shifted by an
    export, not a different animation. Both hands, relative to the hips, sampled
    at the sheet's own column offsets so that what the number says and what the
    picture shows are the same comparison.

    It is minimised over a small shift because it has to be. The release detector
    lands on 1.633 s in `GUB_2/Throw` and 1.617 s in `SpearThrow` — one frame
    apart, on two exports of one motion — and comparing frame N of one against
    frame N+1 of the other charges a 3 cm offset up to 8 cm of "difference" that
    is really just a frame. Sliding until they agree best, and then reporting the
    residual, separates "the same thing, offset" from "a different thing".
    """
    if len(clips) < 2:
        return
    base = clips[0]
    steps = range(-int(round(SHIFT_LIMIT * FPS)), int(round(SHIFT_LIMIT * FPS)) + 1)
    for clip in clips[1:]:
        best = None
        for step in steps:
            gaps = []
            for offset in offsets:
                ia = int(round((base["focus"] + offset) * FPS))
                ib = int(round((clip["focus"] + offset) * FPS)) + step
                ia = min(len(base["times"]) - 1, max(0, ia))
                ib = min(len(clip["times"]) - 1, max(0, ib))
                for hand in HANDS:
                    gaps.append((base["rel"][hand][ia] - clip["rel"][hand][ib]).length)
            mean = sum(gaps) / len(gaps)
            if best is None or mean < best[0]:
                best = (mean, min(gaps), max(gaps), step / float(FPS))
        clip["diverge"] = best


def row_label(clip):
    """The block of text at the left of a row: what it is, and every number.

    Order is deliberate. The name, then the verdict if there is one, then the
    measurements, then how it compares to row one — so a red row announces itself
    before anybody has read a figure off it.
    """
    audit = clip["audit"]
    lines = [clip["name"]]
    bad = bool(audit["problems"])
    if audit.get("skinless"):
        lines.append("WOULD FAIL: no mesh — downloaded Without Skin")
    elif bad:
        lines.append("WOULD FAIL THE BUILD:")
        for problem in audit["problems"][:2]:
            lines.append("  " + problem.split("\n")[0][:52])
    lines.append("%.3f s, %d frames" % (clip["length"], clip["last"] - clip["first"] + 1))
    lines.append("travels %.3f m end to end (%.3f m/s), peaks %.3f m from the start"
                 % (audit.get("travel", 0.0), audit.get("speed", 0.0),
                    audit.get("peak", 0.0)))
    lines.append("%s peaks %.2f m/s at %.3f s, %.2fx its neighbourhood"
                 % (clip["hand"].replace("Hand", " hand").lower().strip(),
                    clip["peak"], clip["focus"], clip["sharp"]))
    if abs(clip["net"]) > YAW_TRIGGER:
        lines.append("turns %.1f° net" % math.degrees(clip["net"]))
    if "diverge" in clip:
        mean, lowest, worst, shift = clip["diverge"]
        same = worst < SAME_MOTION and (worst - lowest) < SAME_MOTION_SPREAD
        lines.append("vs row 1: %.3f m mean, %.3f to %.3f m%s"
                     % (mean, lowest, worst,
                        "" if abs(shift) < 1e-6 else
                        " (best at a %+.3f s shift)" % shift))
        if same:
            lines.append("SAME MOTION AS ROW 1 - the gap varies by %.0f mm"
                         % ((worst - lowest) * 1000.0))
    return "\n".join(lines), bad


def build_sheet(opts, clips, offsets, draw_yaw):
    """Lay every cell out and point a camera at it. Returns the frame, in metres.

    The sheet is built in the camera's own axes rather than in world X and Z:
    columns march along `right`, which is horizontal and perpendicular to the
    view at any azimuth, so twelve columns are twelve evenly spaced columns
    whether the camera is dead front or three-quarters on. Rows stack in world Z,
    which under an orthographic camera is straight up the screen and — unlike a
    screen-space up — keeps each row's floor a real horizontal plane that a foot
    can be seen to touch.
    """
    palette = PALETTE[opts.mode]
    scene = bpy.context.scene

    azimuth = math.radians(opts.azimuth)
    elevation = math.radians(opts.elevation)
    # The rest pose looks along -Y and its right hand is toward -X
    # (`report_rest_pose` in build_gub measures both: the foot points -Y, which
    # is +Z in Godot, and `rest_facing` puts the left-hip -> right-hip line at
    # -176°). Positive azimuth therefore swings the camera toward -X, which is
    # the throwing side.
    towards_camera = Vector((-math.sin(azimuth) * math.cos(elevation),
                             -math.cos(azimuth) * math.cos(elevation),
                             math.sin(elevation))).normalized()
    forward = -towards_camera
    right = forward.cross(Vector((0.0, 0.0, 1.0))).normalized()

    ncols, nrows = len(offsets), len(clips)
    width = GUTTER + COL_PITCH * ncols + MARGIN
    height = HEADER + COLHEAD + CELL_TOP + ROW_PITCH * (nrows - 1) + FOOT
    left = -width * 0.5 + GUTTER
    top = height * 0.5

    def floor_of(row):
        return top - HEADER - COLHEAD - CELL_TOP - ROW_PITCH * row

    def place(col, row):
        return (right * (left + COL_PITCH * (col + 0.5))
                + Vector((0.0, 0.0, floor_of(row))))

    log()
    log("-- staging %d columns x %d rows, %.2f x %.2f m of frame"
        % (ncols, nrows, width, height))

    cam_data = bpy.data.cameras.new("sheet")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = width
    cam_data.sensor_fit = 'HORIZONTAL'
    cam_data.clip_start = 1.0
    cam_data.clip_end = 400.0
    cam = bpy.data.objects.new("sheet", cam_data)
    # Far enough back that nothing is behind the near plane; the projection is
    # parallel, so the distance changes nothing else.
    cam.location = towards_camera * 120.0
    cam.rotation_euler = forward.to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    # Every label is a flat text object turned to face the lens. One rotation
    # serves all of them, because the projection is orthographic and they
    # therefore all face it from wherever they stand.
    label_rot = cam.rotation_euler
    bar_yaw = math.atan2(right.y, right.x)

    for row, clip in enumerate(clips):
        base = place(0, row)
        bad = bool(clip["audit"]["problems"])
        body = palette["body_bad"] if bad else palette["body"]

        # The floor, as a bar rather than a plane: the camera is orthographic and
        # nearly level, so a plane at this row's height is edge-on and invisible,
        # while a 2 cm bar is a few pixels of unambiguous "this is where the
        # ground is". Laid along the row rather than along world X — at any
        # azimuth but zero the two are different lines and the second one runs
        # off diagonally — and pushed away from the camera so a foot draws over
        # it and a hovering foot leaves it showing underneath. The same argument
        # `tools/preview_anim.gd` makes, on a sheet that has one floor per row.
        floor = bar(base + forward * 0.9 + right * (COL_PITCH * (ncols - 1) * 0.5),
                    (COL_PITCH * ncols + 0.4, 0.02, 0.02), palette["ground"])
        floor.rotation_euler = (0.0, 0.0, bar_yaw)

        block, _ = row_label(clip)
        text(block, 0.13, palette["bad"] if bad else palette["text"],
             base + right * (-COL_PITCH * 0.5 - 0.30)
             + Vector((0.0, 0.0, CELL_TOP)),
             label_rot, align_x='RIGHT', align_y='TOP')

        for col, offset in enumerate(offsets):
            when = clip["focus"] + offset
            frame = clip["first"] + int(round(when * FPS))
            at = place(col, row)
            if frame < clip["first"] or frame > clip["last"]:
                # Only reachable when `--pre`/`--post` were given by hand: the
                # fitted default cannot reach past the end of any clip in the
                # sheet. Marked rather than left blank, so an empty cell is never
                # mistaken for a pose that happens to be featureless.
                text("(before the clip)" if frame < clip["first"]
                     else "(after the clip)", 0.11, palette["dim"],
                     at + Vector((0.0, 0.0, 0.9)), label_rot)
                continue

            pipeline.use_action(clip["arm"], clip["action"])
            if clip["mesh"] is None:
                skeleton_snapshot(clip["arm"], frame, at, body)
            else:
                snapshot(clip["mesh"], frame, at, body)

            stamp = "%.3f s" % ((frame - clip["first"]) / float(FPS))
            if draw_yaw:
                index = min(len(clip["yaws"]) - 1, frame - clip["first"])
                yaw = clip["yaws"][index]
                compass(at + forward * 0.25, yaw, palette["accent"])
                stamp += "    %+.0f" % math.degrees(yaw) + DEGREE
            text(stamp, 0.12,
                 palette["text"] if offset == 0.0 else palette["dim"],
                 at + Vector((0.0, 0.0, CELL_TOP - 0.16)), label_rot)

    # Every posed cell is a frozen copy, so the source meshes are still standing
    # at the origin in the middle of the sheet. They cannot be deleted — the
    # snapshots were taken off them — so they are hidden once the last one has
    # been taken.
    for clip in clips:
        if clip["mesh"] is not None:
            clip["mesh"].hide_render = True
        clip["arm"].hide_render = True

    # The column headers: seconds from each clip's own release, with the release
    # itself named rather than numbered.
    for col, offset in enumerate(offsets):
        at = place(col, 0)
        release = abs(offset) < 1e-6
        text("release" if release else "%+.2f" % offset,
             0.16 if release else 0.13,
             palette["text"] if release else palette["dim"],
             Vector((at.x, at.y, top - HEADER - 0.20)), label_rot)

    title = opts.title or ("%d clips, aligned on the release" % len(clips))
    subtitle = ("%s render, %.0f%s azimuth / %.0f%s elevation, orthographic  -  "
                "columns are seconds from each clip's own release  -  "
                "burst of %d over %.2f s  -  nothing here is declared or built"
                % (opts.mode, opts.azimuth, DEGREE, opts.elevation, DEGREE,
                   opts.burst, opts.burst_span))
    anchor = right * (-width * 0.5 + 0.35)
    text(title, 0.34, palette["text"],
         anchor + Vector((0.0, 0.0, top - 0.55)), label_rot, align_x='LEFT')
    text(subtitle, 0.145, palette["dim"],
         anchor + Vector((0.0, 0.0, top - 1.00)), label_rot, align_x='LEFT')

    return width, height


def render(opts, width, height):
    scene = bpy.context.scene
    palette = PALETTE[opts.mode]

    scene.render.engine = 'BLENDER_WORKBENCH'
    shading = scene.display.shading
    shading.color_type = 'OBJECT'
    shading.background_type = 'VIEWPORT'
    shading.background_color = palette["background"]
    if opts.mode == "lit":
        shading.light = 'STUDIO'
        shading.show_specular_highlight = False
        # Cavity is the whole reason the lit mode can answer "is that knee in
        # front of the other one": it darkens screen-space creases, so a limb
        # crossing the torso gets an edge where a diffuse shade alone gives none.
        shading.show_cavity = True
        shading.cavity_type = 'BOTH'
        shading.curvature_ridge_factor = 1.0
        shading.curvature_valley_factor = 1.0
        shading.cavity_ridge_factor = 1.4
        shading.cavity_valley_factor = 1.4
        shading.show_object_outline = True
        shading.object_outline_color = palette["outline"]
    else:
        # FLAT light with one colour per object is a true silhouette: no shading
        # at all, so the body is a solid shape and only its edge carries meaning.
        # No outline, because an outline would be the thing the mode exists to
        # remove.
        shading.light = 'FLAT'
        shading.show_cavity = False
        shading.show_object_outline = False
    scene.display.render_aa = '16'
    # A diagram, not a photograph: the view transform is put back to Standard so
    # the colours above are the colours that land in the PNG. Blender's default
    # (AgX) is a film response built to roll highlights off, and it turns the
    # flat mode's 0.97 background into a flat mid-grey — which halves the
    # contrast of the one mode whose entire job is a shape against a ground.
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'

    px = min(opts.scale, int(MAX_WIDTH / width))
    scene.render.resolution_x = int(round(width * px))
    scene.render.resolution_y = int(round(height * px))
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.film_transparent = False
    scene.render.filepath = opts.out

    os.makedirs(os.path.dirname(opts.out), exist_ok=True)
    log()
    log("-- rendering %dx%d px, Workbench %s"
        % (scene.render.resolution_x, scene.render.resolution_y,
           shading.light.lower()))
    bpy.ops.render.render(write_still=True)


def main():
    opts = parse_args(sys.argv)
    if opts.out is None:
        stem = os.path.splitext(os.path.basename(opts.files[0]))[0]
        opts.out = os.path.join(OUT_DIR, "preview_%s.png" % stem)
    opts.out = os.path.abspath(opts.out)

    reference, audits = audit_all(opts.files)
    clips = prepare(opts, audits, reference)

    draw_yaw = (opts.yaw if opts.yaw is not None
                else any(abs(c["net"]) > YAW_TRIGGER for c in clips))
    if opts.elevation is None:
        opts.elevation = ELEVATION_YAW if draw_yaw else ELEVATION

    offsets, pre, post = choose_offsets(opts, clips)
    divergence(clips, offsets)
    for clip in clips[1:]:
        mean, lowest, worst, shift = clip["diverge"]
        log("  %s against row 1: %.3f m mean, %.3f to %.3f m, best at %+.3f s"
            % (clip["name"], mean, lowest, worst, shift))

    log()
    log("-- columns: %d offsets from each clip's own release, %+.3f to %+.3f s"
        % (len(offsets), offsets[0], offsets[-1]))
    log("  %s" % "  ".join("%+.3f" % o for o in offsets))
    if opts.pre is None or opts.post is None:
        log("  span fitted to the shortest reach of any clip in the sheet "
            "(%.3f s before, %.3f s after)" % (pre, post))
    log("  floor compass: %s" % ("on — a clip here nets more than %.0f° of turn"
                                 % math.degrees(YAW_TRIGGER) if draw_yaw
                                 else "off — nothing here nets that much turn"))

    width, height = build_sheet(opts, clips, offsets, draw_yaw)
    render(opts, width, height)

    log()
    log("  wrote %s" % opts.out)
    log("  nothing was declared, nothing was built, art/generated/ is untouched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
