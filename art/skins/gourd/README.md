# gourd — a recolour, baked

A pumpkin: orange ribbed skin with green stalks for antennae.
From `assets/source/skins/GOURD/GOURD.glb`, the BOG sculpt retextured by Tripo on
that prompt and downloaded with the texture embedded. This batch came back
*regenerated* rather than repainted — 9 124 vertices in Tripo's own UV layout,
not the body's 15 872 — so the paint could not be worn as it was.
Baked by `python tools/bake_skin.py GOURD` (which `extract_skins.py` calls on its
own for such a download): the body's vertices are registered onto the download's
surface and every texel of the body's layout takes its colour from the nearest
point of the download's paint. Fit 2.5 mm mean, 6.9 mm at the 95th percentile.
