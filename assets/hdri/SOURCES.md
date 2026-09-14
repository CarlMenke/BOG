# Downloaded sky assets

Everything here is CC0 (public domain): no attribution required, commercial use
and redistribution permitted. That is the licence bar this repository holds to —
the same one the Stylized Nature MegaKit's `License_Standard.txt` clears.

| file | what it is | source | licence |
|---|---|---|---|
| `kiara_6_afternoon_2k.hdr` | 2048x1024 equirectangular HDR panorama. A clear afternoon in a dry rocky valley, Kiara Lodge, South Africa; photographed by Greg Zaal, 2018. | Poly Haven — https://polyhaven.com/a/kiara_6_afternoon (`https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kiara_6_afternoon_2k.hdr`) | CC0 |

## Why 2k and not 4k

`resources/config/rust_sky.tres` sets `radiance_size = 3`, which is a 256 px
radiance cubemap, so the ambient and reflection contribution of a 4k dome is
identical to a 2k one — the only thing the extra 19 MB would buy is the
background a player looks at directly, and in Rust that background is a band of
sky above a container wall. Rendered at 1280x720 from every spawn pad, 2k is not
visibly soft in that band. 6.2 MB against 25.8 MB.

## What the numbers in `rust.tscn` and `rust_sky.tres` came from

Measured off this file rather than chosen, so the `Sun`, the sky and the
reflections all agree about where the sun is:

    sun direction   (-0.53784, 0.59423, -0.59801)  in the panorama's own frame
    elevation       36.46 deg
    azimuth         -138.03 deg  (compass atan2(x, z))
    sun energy      82% of the whole sphere's irradiance
    lower hemisphere mean radiance  (0.244, 0.187, 0.108) — the warm ground bounce

`rust_sky.gdshader`'s `sky_yaw` turns the dome by 189.0 degrees, which puts that
sun on the map's own authored azimuth of +51 degrees (`rust.tscn`'s `Sun`), so
the yard keeps the lit and shaded faces it was built with and only the hour
changes.
