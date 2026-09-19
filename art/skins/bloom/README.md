# bloom — a recolour, baked

A sunflower in bloom: yellow-green skin, the flower head across the belly, leafy green limbs.
From `assets/source/skins/BLOOM/BLOOM.glb`, the BOG sculpt retextured by Tripo on
that prompt and downloaded with the texture embedded. This batch came back
*regenerated* rather than repainted — 9 124 vertices in Tripo's own UV layout,
not the body's 15 872 — so the paint could not be worn as it was.
Baked by `python tools/bake_skin.py BLOOM` (which `extract_skins.py` calls on its
own for such a download): the body is registered onto the download whole, then
bone by bone through its own skin weights, then with a smooth pull, and every
texel of the body's layout takes its colour from the nearest points of the
download's paint that face its way. Fit 1.9 mm mean, 5.2 mm at the 95th
percentile.
