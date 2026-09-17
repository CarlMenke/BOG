# example — a recolour

The worked example of a recolour skin (D-100): the body's own texture with
the yellow skin turned 150° round the hue wheel, made by

    "$GODOT" --headless --path . --script tools/make_recolour.gd -- example 150 2048

and worn by `Bog.wear_skin(load("res://art/skins/example/basecolor.png"))`.
At 2048² it is 5.6 MB against the body's 12 MB 4096², which a recolour does
not need. The tint shader finds the yellow skin by hue, so a team colour still
takes on a body wearing this where the hue window still matches, and the
recolour shows where it does not.

    "$GODOT" --path . --resolution 1600x700 --script tools/snapshot.gd -- \
        res://tools/preview_bog.tscn out.png 30 Idle skin=example
