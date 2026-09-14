# Sourced, not run. Puts the path to a Blender 5-or-newer binary in $BLENDER_BIN.
#
#   BLENDER_TAG=build_elder . "$(dirname "$0")/find_blender.sh"
#
# This lived inside `tools/build_gub.sh` until `tools/build_elder.sh` needed the
# same answer. It is the same argument `tools/find_godot.sh` makes at the top of
# itself: a search for where somebody installed a big application has to stay in
# step with reality, and two copies of it will not. `$BLENDER_TAG` is only the
# prefix on the messages, so each caller still sounds like itself.
#
# Sourcing matters: on failure this calls `exit 2`, which ends the *caller*. That
# is deliberate — neither build script has anything to do without Blender.
#
# Inputs:  $BLENDER (optional override).
# Outputs: $BLENDER_BIN, $BLENDER_VERSION.

BLENDER_TAG="${BLENDER_TAG:-blender}"

# An explicit setting is a claim, not a hint: if it is wrong, say so rather than
# searching on and running a different Blender than the one that was asked for.
if [ -n "${BLENDER:-}" ] && { [ ! -x "$BLENDER" ] || [ -d "$BLENDER" ]; }; then
    echo "$BLENDER_TAG: BLENDER is set to something that is not an executable:"
    echo "       $BLENDER"
    exit 2
fi

# Every plausible place, in order. Blender is on PATH on no machine this has run
# on; Windows installs it per minor version under Program Files, so the glob is
# sorted and the newest match wins; and `$HOME` is not the Windows profile under
# every bash on Windows, which is the mistake `tools/find_godot.sh` documents.
blender_candidates() {
    [ -n "${BLENDER:-}" ] && printf '%s\n' "$BLENDER"
    command -v blender 2>/dev/null

    printf '%s\n' /Applications/Blender.app/Contents/MacOS/Blender
    printf '%s\n' "$HOME"/Applications/Blender.app/Contents/MacOS/Blender

    # Newest first: `Blender 5.2` sorts after `Blender 4.2`, and the version
    # check below only settles whether a candidate is new *enough*.
    local dir
    for dir in "/c/Program Files" "/mnt/c/Program Files" \
               "${PROGRAMFILES:+$(cygpath -u "$PROGRAMFILES" 2>/dev/null)}"; do
        [ -n "$dir" ] || continue
        printf '%s\n' "$dir"/Blender\ Foundation/Blender\ */blender.exe | sort -Vr
    done
}

# Blender prints its version and exits. The FBX importer and the layered-action
# API these scripts use are 4.4-and-later shapes (`action.fcurves` is gone), so
# an older Blender fails deep inside the script with an AttributeError instead of
# here with an explanation.
BLENDER_BIN=""
BLENDER_REJECTED=""
while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] && [ ! -d "$candidate" ] || continue
    BLENDER_VERSION="$("$candidate" --version 2>/dev/null | head -n 1)"
    case "$BLENDER_VERSION" in
        "Blender "[5-9].*|"Blender "[1-9][0-9]*.*) BLENDER_BIN="$candidate"; break ;;
        *) BLENDER_REJECTED="$BLENDER_REJECTED
       $candidate (reports ${BLENDER_VERSION:-nothing})" ;;
    esac
done < <(blender_candidates)

if [ -z "$BLENDER_BIN" ] && [ -n "${BLENDER:-}" ]; then
    # A binary asked for by name is honoured even at the wrong version.
    BLENDER_BIN="$BLENDER"
    BLENDER_VERSION="$("$BLENDER_BIN" --version 2>/dev/null | head -n 1)"
fi

if [ -z "$BLENDER_BIN" ]; then
    echo "$BLENDER_TAG: cannot find Blender 5 or newer. Looked on PATH, in"
    echo "       /Applications, and under 'Program Files/Blender Foundation'."
    if [ -n "$BLENDER_REJECTED" ]; then
        echo "$BLENDER_TAG: these exist but are too old:$BLENDER_REJECTED"
        echo "       Blender 4.3 and earlier have unlayered actions, and these"
        echo "       scripts read action.layers[].strips[].channelbags[]."
    fi
    echo "       Set BLENDER=/path/to/blender and try again."
    exit 2
fi

echo "$BLENDER_TAG: $BLENDER_BIN ($BLENDER_VERSION)"
