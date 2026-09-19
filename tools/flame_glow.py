"""The campfire's glow — manufactured from its own base colour, after the textures.

`CAMPFIRE.glb` is a Tripo download, and a Tripo download is one mesh with one
material carrying base colour, a roughness-metallic map and a normal map. Its
flame is *geometry*: a modelled tongue of fire standing in the stones, painted
orange in the base texture and lit by nothing at all. Dropped into the menu as
it arrives it is a traffic cone. Nothing in the file says "this part of me is a
light".

The old menu fire said it the only way a hand-built prop can: two cones with
`SHADING_MODE_UNSHADED` and `emission_energy_multiplier` 2.2 and 3.4, comfortably
over the environment's 1.45 glow threshold (`arena_env.tres`), so the glow pass
bloomed them and nothing else in the glade. That threshold is what makes the
trick work, and it is also what makes it *unavailable* to a downloaded prop: a
baked-in orange sits under 1.0 in linear light, the threshold is 1.45, and no
amount of base colour ever reaches it. A surface only crosses 1.45 by emitting.

So this module gives the flame the one thing the download is missing, and gives
it in the place every other prop in `art/generated` carries it: an emission
texture in the asset. Nothing in GDScript then has to remember that the campfire
is special. Godot's importer reads `emissiveTexture` and
`KHR_materials_emissive_strength` straight into `emission_enabled`,
`emission_texture` and `emission_energy_multiplier` — the same three fields the
cones set by hand, so the fire glows for exactly the reason it used to, off an
asset instead of off a script.

**Why a hue mask rather than a hand-painted map.** Tripo's atlas is a scatter of
unrelated patches; there is no "flame island" to select by UV rectangle, and the
patches move if the model is ever re-downloaded or re-decimated. What does not
move is the paint: on a fire, orange *is* the flame. The mask is therefore a
question asked of the colour — is this texel a saturated, bright
red-through-yellow — and the answer is checked against the geometry rather than
trusted. At the shipping thresholds it lights nothing below 10 cm, twelve per
cent of the 12-24 cm band, sixty-four per cent of 24-36 cm and everything above
that, on a 92 cm model whose stone ring is the bottom quarter. That is the flame
column, found by colour and confirmed by height.

**Why the mask is blurred before it multiplies.** A hard mask is a hard edge,
and the glow pass is the one thing that makes a hard edge obvious: the bloom
stops dead on a texel boundary and the flame reads as cut out with scissors. Two
pixels at 1024 is about a millimetre and a half on the model — enough for the
bloom to fall off the way a flame's does, far too little to leak onto a stone.

**Why it runs after the texture loop and not from the bow's hook.**
`decimate_assets.py` re-copies every image in the *builder's* document by reading
its `bufferView` out of the *source* file. An image appended before that loop
would have its brand-new view index looked up in the wrong document and come
back as whatever bytes happened to live at that index. So this is a second hook
point, after the loop, and that ordering is the whole reason it exists.
"""

import io

import numpy as np
from PIL import Image, ImageFilter

# What counts as flame, asked of the base colour in HSV.
#
# Hue 0..65 degrees, wrapping through red: the fire is painted deep red at its
# base through orange to yellow at the tips, and 65 stops short of the
# yellow-green the moss around the pit is painted in. Saturation 0.62 and value
# 0.68 are what separate flame from *warm stone* — this atlas is full of tan and
# salmon rock faces at hue 25-35, and they sit at half the saturation of the
# paint on the flame. Measured against the geometry, not guessed; see the module
# docstring for where these thresholds land on the model.
HUE_MAX_DEGREES = 65.0
HUE_WRAP_DEGREES = 345.0
SATURATION_MIN = 0.62
VALUE_MIN = 0.68

# Feather on the mask edge, in texels of the emission map.
MASK_BLUR = 2.0

# How hard the flame emits.
#
# The environment's glow threshold is 1.45, so anything under that is a warm
# patch of paint and anything over it blooms. The brightest texels this mask
# keeps sit near 0.95, so 2.6 puts the flame's core at about 2.5 — over the
# threshold with room to spare, and between the old cones' 2.2 and 3.4, which is
# the amount of bloom this menu was framed around.
EMISSIVE_STRENGTH = 2.6

EMISSIVE_EXTENSION = "KHR_materials_emissive_strength"
EMISSIVE_IMAGE = "emissive"
BASECOLOR_IMAGE = "basecolor"


def flame_mask(img):
    """The feathered 0..1 mask of which texels are flame.

    Returns (mask, kept_fraction), the fraction being of the *hard* mask,
    because that is the number with a meaning — how much of the atlas is painted
    fire — where the blurred one only counts the length of its own edges.
    """
    hsv = np.asarray(img.convert("HSV")).astype(np.float32)
    hue = hsv[..., 0] * (360.0 / 255.0)
    sat = hsv[..., 1] / 255.0
    val = hsv[..., 2] / 255.0

    hard = (((hue <= HUE_MAX_DEGREES) | (hue >= HUE_WRAP_DEGREES)) &
            (sat >= SATURATION_MIN) & (val >= VALUE_MIN))
    kept = float(hard.mean())

    blurred = Image.fromarray((hard * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(MASK_BLUR))
    return np.asarray(blurred).astype(np.float32) / 255.0, kept


def emission_png(basecolor_bytes, log):
    """The base colour with everything that is not flame painted black."""
    img = Image.open(io.BytesIO(basecolor_bytes)).convert("RGB")
    mask, kept = flame_mask(img)
    rgb = np.asarray(img).astype(np.float32)
    out = np.clip(rgb * mask[..., None], 0.0, 255.0).astype(np.uint8)

    log("  glow mask: %.1f%% of %dx%d texels kept (hue <= %.0f deg or >= %.0f, "
        "saturation >= %.2f, value >= %.2f), edge feathered %.0f px"
        % (100.0 * kept, img.size[0], img.size[1], HUE_MAX_DEGREES,
           HUE_WRAP_DEGREES, SATURATION_MIN, VALUE_MIN, MASK_BLUR))

    buf = io.BytesIO()
    Image.fromarray(out).save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def add_emission(builder, textures, log):
    """Attach an emission map to material 0, cut out of its own base colour.

    `textures` is `{image name: bytes}` for the images the decimator has just
    written into `builder`, so the mask is cut out of the *shipping* texture at
    the *shipping* resolution rather than out of the 4096-square source: what
    glows is exactly what is on screen, downscaling and all.
    """
    basecolor = textures.get(BASECOLOR_IMAGE)
    if basecolor is None:
        raise SystemExit("flame_glow: no image named %r in the built file "
                         "(have: %s)" % (BASECOLOR_IMAGE, ", ".join(sorted(textures))))

    doc = builder.doc
    material = doc["materials"][0]
    base_texture = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    sampler = doc["textures"][base_texture].get("sampler")

    data = emission_png(basecolor, log)
    doc["images"].append({
        "name": EMISSIVE_IMAGE,
        "mimeType": "image/png",
        "bufferView": builder.add_view(data),
    })
    image_index = len(doc["images"]) - 1

    texture = {"source": image_index}
    if sampler is not None:
        # The base colour's own sampler, so the two maps wrap and filter
        # identically. A mask that tiled differently from the paint it was cut
        # out of would glow off the edge of its own flame.
        texture["sampler"] = sampler
    doc["textures"].append(texture)
    texture_index = len(doc["textures"]) - 1

    material["emissiveTexture"] = {"index": texture_index}
    material["emissiveFactor"] = [1.0, 1.0, 1.0]
    material.setdefault("extensions", {})[EMISSIVE_EXTENSION] = {
        "emissiveStrength": EMISSIVE_STRENGTH,
    }
    used = doc.setdefault("extensionsUsed", [])
    if EMISSIVE_EXTENSION not in used:
        used.append(EMISSIVE_EXTENSION)

    log("  emission: image %d %r, texture %d on material %r, strength %.1f "
        "(Godot imports that as emission_energy_multiplier)"
        % (image_index, EMISSIVE_IMAGE, texture_index,
           material.get("name", "?"), EMISSIVE_STRENGTH))
