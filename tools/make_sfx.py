"""Synthesise the game's sound effects from scratch.

There is no sound library for this project and no budget for one, so the effects
are generated rather than recorded. That is not a compromise for a game that
looks like this: a Bog is a cartoon, and short synthetic hits — a filtered noise
whoosh, a low thud, a struck-glass chime — read as deliberate stylisation where
a mismatched library sample would read as an accident.

Generating them also means they are diffable, tunable from a single number, and
reproducible on any machine, which is the same argument made for the mesh
pipeline in D-003 and the ragdoll in D-006.

Everything is written as 16-bit mono 44.1 kHz WAV. Godot imports .wav without
any extra configuration, and every clip here is well under a second, so the size
saved by encoding to Ogg would be measured in kilobytes and cost the ability to
loop them sample-exactly.

Usage:  python tools/make_sfx.py
"""

import os
import struct
import wave

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "audio", "sfx")
AMBIENCE_DIR = os.path.join(REPO, "audio", "ambience")

RATE = 44100
## Ambience beds are all low-frequency wash with nothing above a few kHz, so
## half the sample rate costs nothing audible and halves the file.
AMBIENCE_RATE = 22050


def envelope(n, attack, decay, curve=2.0):
    """Amplitude envelope over `n` samples.

    `attack` and `decay` are fractions of the whole clip. The decay is raised to
    `curve` so it falls away fast at first and then tails off, which is what
    makes a hit sound struck rather than faded.
    """
    out = np.ones(n)
    a = max(1, int(n * attack))
    d = max(1, int(n * decay))
    out[:a] = np.linspace(0.0, 1.0, a)
    out[n - d:] = np.linspace(1.0, 0.0, d) ** curve
    return out


def noise(n, seed):
    """Reproducible white noise. A fixed seed keeps re-runs byte-identical."""
    return np.random.default_rng(seed).uniform(-1.0, 1.0, n)


def lowpass(signal, cutoff_hz):
    """One-pole low-pass. Crude, and exactly right for taking the fizz off
    noise without pulling in scipy for four sound effects."""
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff_hz / RATE)
    out = np.empty_like(signal)
    state = 0.0
    for i in range(len(signal)):
        state += alpha * (signal[i] - state)
        out[i] = state
    return out


def sweep(n, start_hz, end_hz, curve=1.0):
    """A sine whose pitch glides from `start_hz` to `end_hz`."""
    t = np.linspace(0.0, 1.0, n)
    freq = start_hz + (end_hz - start_hz) * (t ** curve)
    # Integrate frequency to get phase, or the sweep detunes as it goes.
    phase = np.cumsum(2.0 * np.pi * freq / RATE)
    return np.sin(phase)


def seconds(duration):
    return int(RATE * duration)


def normalise(signal, peak=0.85):
    """Scale to a fixed peak so no clip is wildly louder than its neighbours."""
    high = np.max(np.abs(signal))
    if high < 1e-9:
        return signal
    return signal / high * peak


def write(name, signal, directory=None, rate=RATE, peak=0.85):
    directory = directory or OUT_DIR
    if not os.path.isdir(directory):
        os.makedirs(directory)
    data = np.clip(normalise(signal, peak), -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    path = os.path.join(directory, "%s.wav" % name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())
    print("  %-18s %5.2fs  %5d KB" % (name, len(data) / rate, os.path.getsize(path) // 1024))


# --------------------------------------------------------------- ambience ---

def looping_noise(n, low_hz, high_hz, seed):
    """Noise that loops perfectly, band-limited between two frequencies.

    Built in the frequency domain rather than filtered in the time domain. Every
    component is an exact whole number of cycles across the buffer, so the last
    sample runs into the first with no discontinuity — which is the entire
    problem with looping an ambience bed. Crossfading the ends of ordinary noise
    hides the seam; this one has no seam to hide.
    """
    rng = np.random.default_rng(seed)
    spectrum = np.zeros(n // 2 + 1, dtype=complex)
    freqs = np.fft.rfftfreq(n, 1.0 / AMBIENCE_RATE)
    band = (freqs >= low_hz) & (freqs <= high_hz)
    # 1/f inside the band: white noise sounds like static, pink like weather.
    magnitude = np.zeros_like(freqs)
    magnitude[band] = 1.0 / np.maximum(freqs[band], 1.0)
    phase = rng.uniform(0.0, 2.0 * np.pi, len(freqs))
    spectrum = magnitude * np.exp(1j * phase)
    return np.fft.irfft(spectrum, n)


def looping_swell(n, cycles, depth=0.45):
    """A slow amplitude drift that also closes its own loop, because it is built
    from whole numbers of cycles across the buffer."""
    t = np.linspace(0.0, 2.0 * np.pi, n, endpoint=False)
    return 1.0 - depth + depth * (0.5 + 0.5 * np.sin(cycles * t))


def ambient_wind():
    """The bed under everything: air moving through a lot of leaves."""
    n = int(AMBIENCE_RATE * 12.0)
    body = looping_noise(n, 40.0, 900.0, 11)
    # A brighter layer that swells on a different period, so the two never line
    # up and the loop does not announce itself every twelve seconds.
    body += 0.35 * looping_noise(n, 700.0, 4200.0, 12) * looping_swell(n, 3)
    return body * looping_swell(n, 2, 0.5)


def ambient_forest():
    """Night in the hollow. Low drone, a slow shimmer above it, and no events —
    anything that reads as a distinct sound would repeat on the loop and become
    the only thing anyone can hear."""
    n = int(AMBIENCE_RATE * 16.0)
    t = np.linspace(0.0, n / AMBIENCE_RATE, n, endpoint=False)
    bed = 0.7 * looping_noise(n, 30.0, 500.0, 21) * looping_swell(n, 2, 0.35)
    shimmer = 0.5 * looping_noise(n, 2000.0, 7000.0, 22) * looping_swell(n, 5, 0.6)
    # Two quiet drones a fifth apart, at exact whole cycles across the buffer.
    drone = np.zeros(n)
    for cycles, gain in [(round(55.0 * n / AMBIENCE_RATE), 0.30),
                         (round(82.5 * n / AMBIENCE_RATE), 0.18)]:
        drone += gain * np.sin(2.0 * np.pi * cycles * t / (n / AMBIENCE_RATE))
    return bed + shimmer + drone * 0.35


AMBIENCE = {
    "ambient_wind": ambient_wind,
    "ambient_forest": ambient_forest,
}


# ----------------------------------------------------------------- effects ---

def spear_throw():
    """Air moving past a stick: noise, low-passed, swelling then gone."""
    n = seconds(0.32)
    body = lowpass(noise(n, 1), 1800.0)
    # A second, brighter layer swept downward gives the whoosh a direction.
    body += 0.4 * lowpass(noise(n, 2), 5200.0) * np.linspace(1.0, 0.2, n)
    return body * envelope(n, 0.22, 0.7, 2.2)


def spear_hit_body():
    """A wet, low thud. Almost all of this is the 90 Hz thump; the noise on top
    is just enough transient to stop it sounding like a drum machine."""
    n = seconds(0.26)
    thump = sweep(n, 150.0, 62.0, 0.5) * envelope(n, 0.005, 0.9, 2.6)
    slap = lowpass(noise(n, 3), 900.0) * envelope(n, 0.002, 0.35, 4.0) * 0.55
    return thump + slap


def spear_hit_world():
    """Wood into dirt: shorter and harder than a body hit, with a bit of ring."""
    n = seconds(0.22)
    knock = sweep(n, 420.0, 180.0, 0.6) * envelope(n, 0.003, 0.85, 3.2)
    grit = lowpass(noise(n, 4), 3000.0) * envelope(n, 0.002, 0.25, 5.0) * 0.7
    return knock + grit


def spear_ready():
    """The spear growing back in the hand. Rising, soft, unmistakably 'again'."""
    n = seconds(0.30)
    return sweep(n, 320.0, 780.0, 1.4) * envelope(n, 0.25, 0.6, 1.6) * 0.8


def shield_deploy():
    """A heavy thing driven into the earth: a pitch rise with a thick low body
    under it.

    The sample is unchanged from the mushroom this prop replaced (D-079), on
    D-078's argument. It was written as something organic shoving itself out of
    the ground, and a 90-to-240 Hz swell under a low-passed noise burst
    describes a timber barricade being rammed into soil just as well — the
    swell is the mass and the squelch is the ground taking it. Re-synthesising
    a sound nobody asked to change would be a diff with no argument behind
    it."""
    n = seconds(0.45)
    swell = sweep(n, 90.0, 240.0, 1.8) * envelope(n, 0.12, 0.6, 1.8)
    squelch = lowpass(noise(n, 5), 1400.0) * envelope(n, 0.05, 0.8, 2.0) * 0.45
    return swell + squelch


def magnet_throw():
    """A struck bar, thrown. Three partials at inharmonic ratios — whole number
    ratios sound like a musical note, and a lump of magnetised steel is not one.

    The samples are unchanged from the crystal this prop replaced (D-078): the
    numbers below already describe a struck metal object, because inharmonic
    partials over a fast decay are what glass and steel have in common."""
    n = seconds(0.5)
    t = np.linspace(0.0, n / RATE, n)
    tone = np.zeros(n)
    for freq, gain, decay in [(880.0, 1.0, 7.0), (1490.0, 0.5, 9.0), (2310.0, 0.28, 12.0)]:
        tone += gain * np.sin(2.0 * np.pi * freq * t) * np.exp(-decay * t)
    return tone * envelope(n, 0.002, 0.4, 1.5)


def magnet_arm():
    """The fuse. A rising tone is the one shape everybody already reads as
    'something is about to happen', which is the whole job of this sound."""
    n = seconds(0.5)
    tone = sweep(n, 520.0, 1250.0, 2.2)
    # A shimmer an octave up, fading in, so it brightens as it climbs.
    tone += 0.35 * sweep(n, 1040.0, 2500.0, 2.2) * np.linspace(0.0, 1.0, n)
    return tone * envelope(n, 0.08, 0.25, 1.2)


def magnet_fire():
    """The pull. Downward sweep — everything is being dragged inward — with a
    noise swell riding it."""
    n = seconds(0.7)
    pull = sweep(n, 1400.0, 180.0, 1.6) * envelope(n, 0.02, 0.55, 1.8)
    wind = lowpass(noise(n, 6), 2200.0) * envelope(n, 0.3, 0.5, 1.5) * 0.5
    return pull + wind


## The great sword's swing, in seconds, and the frame the blade actually cuts on
## (D-068). `BogAnimator.SWING_SECONDS` and `SWING_RELEASE_TIME` are the same two
## numbers, and the release is not a feel number at either end: it is where the
## build measures peak hand speed, 6.86 m/s, because a sword cuts where the blade
## is fastest. If the clip or the window ever moves, these move with them, or the
## whoosh will peak somewhere the blade is not.
SWING_SECONDS = 1.867
SWING_RELEASE = 1.067


def bow_loose():
    """A bowstring let go. Almost none of this is the string.

    A drawn bow is a spring with the limbs in it, and the loose is that spring
    unloading in about twenty milliseconds. The arrow takes most of the energy
    and leaves; what is left is the limbs arriving at brace and stopping dead
    against the riser, which is a block of wood being hit from the inside. So the
    loudest layer here is `limb`, and it is low, dry and woody — higher and
    deader than `spear_hit_body`'s flesh at 150 down to 62 Hz, because wood is
    stiffer than a Bog.

    On top of it, in the order the ear gets them:

      click   the nock coming off the string and the shaft dragging over the
              rest. Broadband, a few milliseconds, and the thing that makes this
              read as *released* rather than as a knock on a door.
      string  what is left in the string once the arrow is gone. It falls in
              pitch because the tension it is vibrating under falls with it as
              the limbs come home, and it dies first because the limbs and the
              arrow have already taken what was in it.
      air     the fletching clearing the rest, and deliberately no more than
              that. The arrow is doing up to 60 m/s (D-065) and this clip is
              played at a fixed point in the world, at the bow — by the time the
              limbs have stopped ringing the shaft is metres away and receding,
              so a whoosh of any length here would be a sound in the wrong place.
              A flick of air is a shaft leaving; a whoosh would be a shaft
              hovering in front of the archer.
    """
    n = seconds(0.22)
    limb = sweep(n, 230.0, 96.0, 0.55) * envelope(n, 0.004, 0.92, 2.4)
    click = lowpass(noise(n, 81), 6500.0) * envelope(n, 0.001, 0.98, 14.0) * 1.5
    string = sweep(n, 1180.0, 430.0, 0.8) * envelope(n, 0.001, 0.97, 9.0) * 0.62
    air = lowpass(noise(n, 82), 2600.0) * envelope(n, 0.06, 0.85, 3.0) * 0.55
    return limb + click + string + air


def sword_swing():
    """A two-handed blade going round, built against the clip that swings it.

    This is the one effect in the file whose length is not a choice. It is
    `SWING_SECONDS` long because it is played on the frame the spin starts, on
    every peer, and it has to still be going when the blade lands. Everything in
    it is driven by one curve — `speed`, the blade's own speed across the clip,
    normalised to 1.0 at the cut. It winds up from rest, is fastest at
    `SWING_RELEASE`, and is still travelling at the end, because this clip's
    recovery *is* its advance (D-068): the feet are covering ground through the
    whole of the last third.

    Why a whoosh is three layers of noise and not one. A blade in air is not
    whistling, it is shedding vortices, and it sheds them at roughly the speed
    divided by the width of what is moving — about 0.2*v/d. That one ratio is
    the whole difference between this and `spear_throw`. The flat of a great
    sword is 40-50 mm across and at 6.9 m/s sheds at a few tens of hertz; its
    edge is a couple of millimetres and sheds at several hundred; a thrown shaft
    is 30 mm of round dowel at half the speed and lands in the middle with
    nothing either side of it. So a big blade goes *woom* and a stick goes
    *swish*, and the way to build the first is to put real weight underneath it
    and let the top arrive late.

      wake  the flat's own low shedding, low-passed to almost nothing and
            multiplied back up, which is `thunder_crack`'s trick for
            `thunder_crack`'s reason: a one-pole filter at 90 Hz throws away most
            of white noise's amplitude with its bandwidth. Weighted by the
            gentlest power of the speed, so it is there from the first frames --
            something this heavy is moving air before it is moving fast.
      body  the middle, and the bulk of what is heard.
      edge  the cut. Weighted by a steep power of the speed, so it is absent for
            most of the wind-up and arrives almost entirely in the half second
            around the release.

    Loudness rising as a *power* of speed is not a curve anybody picked either:
    edge noise off a moving body goes as something like the sixth power of it,
    which is far too violent to leave a wind-up audible at all, so these are that
    law flattened rather than invented. Crossfading two fixed cutoffs is also how
    the brightness climbs and falls without a filter that sweeps — `spear_throw`
    already does the one-layer version of the same trick.
    """
    n = seconds(SWING_SECONDS)
    t = np.linspace(0.0, 1.0, n)
    r = SWING_RELEASE / SWING_SECONDS
    rise = np.clip(t / r, 0.0, 1.0) ** 1.35
    fall = 1.0 - 0.85 * np.clip((t - r) / (1.0 - r), 0.0, 1.0) ** 1.1
    speed = rise * fall
    wake = lowpass(noise(n, 84), 90.0) * speed ** 2.0 * 8.0
    body = lowpass(noise(n, 85), 620.0) * speed ** 3.0 * 2.6
    edge = lowpass(noise(n, 86), 3200.0) * speed ** 6.0 * 0.95
    # The speed curve does not reach zero — the blade is still moving when the
    # clip ends — so the last 75 ms are faded rather than cut, or the buffer
    # would end on a step and the step would be a click.
    return (wake + body + edge) * envelope(n, 0.001, 0.04, 1.0)


def sword_hit_body():
    """A metre of steel arriving in a Bog at 6.9 m/s with a whole spinning body
    behind it. Three things separate it from a spear burying itself, and all
    three are the blade rather than the damage.

      edge  the contact. A spear point is a cone that goes in; an edge is a line
            that is already through, so the transient is brighter and shorter
            than `spear_hit_body`'s muffled 900 Hz slap, and is not filtered down
            to a slap at all.
      thud  the momentum, and the reason this reads as *heavy*. Lower and longer
            than the spear's 150 down to 62 Hz, because what is behind a thrown
            stick is a stick and what is behind this is a Bog turning through a
            whole revolution.
      ring  the part a spear cannot do. A blade struck across its length rings in
            the bending modes of a free bar, whose frequencies go as
            1 : 2.76 : 5.40 : 8.93 — the squares of 4.730, 7.853, 10.996 and
            14.137, and emphatically not whole numbers. `magnet_throw` reaches for
            inharmonic partials so that a chime does not sound like a musical
            note; these are the same shape arrived at from the other end,
            because they are simply what a bar does. The fundamental is about
            190 Hz for this blade — 1.05 m of steel about 40 mm deep, bending
            the stiff way, which is the way a cut loads it. It is damped hard,
            and the upper modes hardest, because the blade
            is in meat with two fists on the hilt, and that damping is the
            difference between a sword in a body and a sword on a rock.

    And a tail, which is the last difference: a spear stops in what it hits and
    this does not. The swing goes on turning through the whole of its
    follow-through (D-068), so the impact is followed out rather than ended.
    """
    n = seconds(0.40)
    t = np.linspace(0.0, n / RATE, n)
    edge = lowpass(noise(n, 87), 6500.0) * envelope(n, 0.001, 0.97, 11.0) * 1.25
    thud = sweep(n, 120.0, 44.0, 0.45) * envelope(n, 0.004, 0.94, 2.0) * 1.2
    ring = np.zeros(n)
    for ratio, gain, decay in [(1.0, 1.0, 15.0), (2.756, 0.45, 27.0),
                               (5.404, 0.22, 44.0), (8.933, 0.10, 62.0)]:
        ring += gain * np.sin(2.0 * np.pi * 190.0 * ratio * t) * np.exp(-decay * t)
    tear = lowpass(noise(n, 88), 1600.0) * envelope(n, 0.12, 0.7, 2.2) * 0.5
    return edge + thud + ring * 0.75 + tear


def fist_hit():
    """A bare fist arriving in a Bog (D-124). Until now it borrowed
    `sword_hit_body`, which is a metre of steel, and a punch that sounds like a
    sword is a punch that reads as worth five times what it takes.

    Everything here is the argument that this is the *smallest* impact in the
    library, and the two layers say so in the two ways a body can:

      slap  the knuckles landing. Mid-band and nothing else — the top is a
            weapon on stone and the bottom is already in the thump — so it is
            `range_plate`'s band-split noise at a tenth of its brightness, and
            gone in twenty milliseconds. It is what makes this read as skin
            rather than as anything with an edge on it.
      thump the mass behind it, and there is very little: one arm, where the
            spear has a whole shaft's flight and the sword a Bog turning
            through a revolution. So it runs 205 down to 105 Hz where
            `spear_hit_body` runs 150 down to 62 — it starts higher and, more
            to the point, it *ends* higher, because a light thing stopping in
            flesh never reaches the bottom a heavy one does. And it is 0.16 s
            against that clip's 0.26.

    No ring and no tail, which is the whole of the difference from the sword:
    nothing about a fist is stiff enough to ring and nothing about it follows
    through — the arm is back on the 0.5 s cycle. Short for `range_orb`'s
    reason as well as for honesty: `BogCombat.PUNCH_CYCLE` is 0.5 s and five
    punches kill, so this is heard twice a second for as long as a fist fight
    lasts, and anything longer would overlap itself.
    """
    n = seconds(0.16)
    thump = sweep(n, 205.0, 105.0, 0.5) * envelope(n, 0.004, 0.92, 2.8)
    slap = lowpass(noise(n, 91), 2600.0) - lowpass(noise(n, 91), 420.0)
    slap *= envelope(n, 0.002, 0.88, 6.0) * 0.8
    return thump + slap


def death():
    """A Bog expiring. Falling, slightly comic, over quickly."""
    n = seconds(0.55)
    cry = sweep(n, 640.0, 150.0, 1.9) * envelope(n, 0.02, 0.7, 1.7)
    # A little vibrato keeps it from sounding like a test tone.
    t = np.linspace(0.0, n / RATE, n)
    cry *= 1.0 + 0.12 * np.sin(2.0 * np.pi * 11.0 * t)
    return cry


def respawn():
    """Back in the world: bright, rising, and clearly not a death."""
    n = seconds(0.6)
    t = np.linspace(0.0, n / RATE, n)
    tone = np.zeros(n)
    for freq, gain in [(523.0, 1.0), (784.0, 0.7), (1046.0, 0.5)]:
        # Each partial enters a little later, so it blooms rather than blares.
        start = 0.10 * (freq / 523.0 - 1.0)
        gate = (t > start).astype(float)
        tone += gain * np.sin(2.0 * np.pi * freq * t) * gate
    return tone * envelope(n, 0.06, 0.65, 1.8)


def hitmarker():
    """The click that says your spear connected. Must be very short and cut
    through everything else, so it is high and almost pure transient."""
    n = seconds(0.09)
    return sweep(n, 2400.0, 1500.0, 1.0) * envelope(n, 0.002, 0.9, 3.5)


def hitmarker_kill():
    """The same click with a body under it: the sound of a hit that finished
    somebody.

    Deliberately *the tick plus something*, not a different sound. A kill is the
    last hit of a sequence of hits, and a confirmation that shares nothing with
    the one before it reads as a separate event rather than as the end of the
    one you were already hearing. So the tick is the same sweep, at the same
    length, and what marks the kill is what arrives under it a few milliseconds
    later: a short 900 to 500 Hz drop, low enough to be felt as weight rather
    than heard as a second beep, and gone by 0.14 s.

    Lower and a hair longer than `hitmarker`, which is the whole of the
    difference a player has to hear across a firefight.
    """
    n = seconds(0.14)
    tick = np.zeros(n)
    click = seconds(0.09)
    tick[:click] = sweep(click, 2400.0, 1500.0, 1.0) * envelope(click, 0.002, 0.9, 3.5)
    # The body starts 6 ms in, so the tick is still the leading edge: one sound
    # with a thud behind it rather than two sounds in a row.
    start = seconds(0.006)
    body = np.zeros(n)
    drop = n - start
    body[start:] = sweep(drop, 900.0, 500.0, 1.6) * envelope(drop, 0.004, 0.86, 2.2)
    return tick * 0.62 + body * 1.0


def range_board():
    """A shaft going into one of the range's target boards.

    A struck plank, not a struck body: `spear_hit_world` is dirt and this has to
    be wood, or a board at twenty metres is indistinguishable from a miss behind
    it. What makes it read as a plank is the pair of low resonances a flat piece
    of timber on a stake actually has — a fundamental around 180 Hz and a fifth
    above it — under a very short, very dry knock.
    """
    n = seconds(0.26)
    t = np.linspace(0.0, n / RATE, n)
    # The knock itself: a burst of filtered noise, gone in a few milliseconds.
    knock = lowpass(noise(n, 71), 2600.0) * envelope(n, 0.001, 0.94, 5.0)
    # The body of the board ringing under it. Barely any sustain: a board on a
    # stake is damped by the stake, which is the difference between this and the
    # gong below.
    body = np.zeros(n)
    for freq, gain in [(178.0, 1.0), (267.0, 0.45), (455.0, 0.22)]:
        body += gain * np.sin(2.0 * np.pi * freq * t)
    body *= envelope(n, 0.002, 0.88, 2.6)
    return knock * 0.85 + body * 0.6


def range_gong():
    """The gong at 28 m, which is the spear's flat band and the whole reason it
    is standing there.

    The one sound in the game that is allowed a long tail. A gong is a struck
    disc, so the partials are deliberately *not* harmonic — a harmonic series
    rings as a bell or an organ and a gong is neither — and they beat against
    each other, which is what gives bronze its shimmer. Pitch is not baked in:
    `Gong` plays this shifted by how far the shot came from, so the clip has to
    stay clean over roughly a fifth either way.
    """
    n = seconds(2.1)
    t = np.linspace(0.0, n / RATE, n)
    tone = np.zeros(n)
    # Inharmonic, and the ratios are irrational on purpose so nothing lines up
    # and the beating never resolves into a chord.
    for freq, gain, decay in [
        (196.0, 1.00, 1.6),
        (283.0, 0.62, 1.9),
        (409.0, 0.44, 2.3),
        (571.0, 0.30, 2.9),
        (838.0, 0.18, 3.6),
    ]:
        tone += gain * np.sin(2.0 * np.pi * freq * t) * np.exp(-t * decay)
    # The strike. Bright, immediate, and over before the disc has answered.
    strike = lowpass(noise(n, 907), 5200.0) * envelope(n, 0.0008, 0.985, 6.0)
    return tone + strike * 0.5


def range_orb():
    """A glowworm orb bursting.

    Soft rather than percussive — nothing about a drifting light should sound
    like it was hit with a hammer — so the transient is short and dull and what
    carries it is a bright upward shimmer that falls away immediately. It has to
    survive being heard four or five times a minute for as long as somebody is
    practising, which is what rules out anything with an edge on it.
    """
    n = seconds(0.42)
    t = np.linspace(0.0, n / RATE, n)
    pop = lowpass(noise(n, 4211), 1400.0) * envelope(n, 0.002, 0.9, 4.0)
    # Two rising voices a little out of tune with each other, so the burst
    # sparkles instead of whistling.
    shimmer = (sweep(n, 900.0, 2300.0, 0.6) + 0.7 * sweep(n, 1180.0, 3050.0, 0.6))
    shimmer *= np.exp(-t * 9.0)
    return pop * 0.7 + shimmer * 0.55


def refill_chime():
    """The range's refill stone topping somebody up.

    A rising arpeggio on three partials rather than one tone, because what it
    has to say is "you have more than you did" and a single note says only
    "something happened". The voices enter in sequence over the first third and
    ring together after that, so the ear hears a count.

    Deliberately quiet and soft-edged. The stone can be stood on every two
    seconds for as long as somebody feels like standing on it, and any sound
    with a transient on the front becomes unbearable at that rate — which is the
    same argument `range_orb` makes one screen up, for the same reason.
    """
    n = seconds(0.55)
    t = np.linspace(0.0, n / RATE, n)
    out = np.zeros(n)
    # A major triad up, an octave apart at the ends: unambiguously "gained",
    # and the only frankly musical sound in the game, which is what marks it as
    # a piece of the range's furniture rather than an event in a match.
    for i, freq in enumerate([523.3, 659.3, 1046.5]):
        start = int(n * 0.10 * i)
        voice = np.zeros(n)
        m = n - start
        u = np.linspace(0.0, m / RATE, m)
        voice[start:] = np.sin(2.0 * np.pi * freq * u) * np.exp(-u * 5.0)
        out += voice * (0.9 - 0.15 * i)
    # A breath of air under it, so the triad sits on something rather than
    # floating in silence.
    out += lowpass(noise(n, 5501), 900.0) * envelope(n, 0.15, 0.8, 2.0) * 0.18
    return out


def rack_swap():
    """A weapon lifted off the practice range's rack.

    Wood and a little metal, in that order: a dull knock as the old weapon is
    set down on the timber, then a short scrape as the new one comes off it. The
    two are staged rather than mixed, because the sound is describing an
    exchange and an exchange has an order to it.

    Short — 0.28 s — because it fires the instant a Bog crosses the rack's area
    and anything longer would still be playing while the player is already
    aiming with the new weapon.
    """
    n = seconds(0.28)
    t = np.linspace(0.0, n / RATE, n)
    # The knock. A low sweep with the grit of `spear_hit_world` over it, which
    # is the sound in this file that already means "shaft against solid thing".
    knock = sweep(n, 260.0, 150.0, 0.7) * envelope(n, 0.004, 0.55, 3.0)
    knock += lowpass(noise(n, 5502), 2200.0) * envelope(n, 0.003, 0.35, 5.0) * 0.5
    # The scrape, delayed into the second half, band-limited so it is a slide
    # along timber rather than a hiss.
    scrape = np.zeros(n)
    start = int(n * 0.45)
    m = n - start
    u = np.linspace(0.0, m / RATE, m)
    rasp = lowpass(noise(m, 5503), 5200.0) - lowpass(noise(m, 5503), 900.0)
    scrape[start:] = rasp * np.sin(np.pi * np.linspace(0.0, 1.0, m)) * np.exp(-u * 4.0)
    return knock * 0.8 + scrape * 0.55


def range_plate():
    """A foot landing on a parkour timing plate.

    Wood on a hollow box: the plates are timber squares laid on the bog, and
    what the player needs from this is a single unmissable "counted" at the
    start of a run and again at the finish. It is the shortest clip in the
    library at 0.18 s, because it fires the frame a Bog crosses the plate and a
    runner is already two strides past it by the time anything longer ends.

    No pitch, no tone, no ring. A timing plate that sang would be the second
    musical object in the range and would compete with the station chime it
    sits twenty metres from; this one is a knock and nothing else.
    """
    n = seconds(0.18)
    # The board itself: a fast fall from a low thump, which is a plank
    # deflecting rather than a stone being hit.
    body = sweep(n, 220.0, 96.0, 0.8) * envelope(n, 0.003, 0.92, 3.2)
    # The hollow under it — one octave up, quieter and shorter, so the box
    # reads as a box and not as solid ground.
    body += 0.35 * sweep(n, 440.0, 200.0, 0.8) * envelope(n, 0.002, 0.88, 5.0)
    # The contact. Mid-band noise only: the top end is a slap on stone and the
    # bottom is already in the sweep.
    grit = lowpass(noise(n, 5505), 4200.0) - lowpass(noise(n, 5505), 380.0)
    return body + grit * envelope(n, 0.001, 0.75, 6.0) * 0.55


# ---------------------------------------------------------------- letters ---

def letter_appears():
    """A letter dropping into the world (the letters round).

    Played in 2D on every machine the moment a card lands, because in the
    free-for-all there is only ever **one** letter out at a time and the whole
    race turns on everybody learning about it at the same instant. That is what
    rules out everything percussive: a sound that arrives with an edge on it
    reads as something happening *to you* — a hit taken, a spear landing — and
    what this has to say is "look up".

    So it is a bell with the strike taken off. Two partials a twelfth apart,
    the upper one quieter and decaying first, over a 60 ms fade-in: no attack
    transient at all, which is exactly what `range_orb` and `refill_chime`
    argue for one screen up and is doubly right here, where the clip is played
    flat in both ears rather than at a point in the world.

    Inharmonic by a hair (1497 against a true 1494) so the two voices beat very
    slowly against each other — the shimmer that says "struck metal" rather
    than "sine wave", the same trick `range_gong` makes its whole living from.
    """
    n = seconds(0.9)
    t = np.linspace(0.0, n / RATE, n)
    # A twelfth, not an octave: an octave is the same note and reads as one
    # voice, and the point of two is that the ear hears an object.
    low = np.sin(2.0 * np.pi * 498.0 * t) * np.exp(-t * 2.6)
    high = 0.45 * np.sin(2.0 * np.pi * 1497.0 * t) * np.exp(-t * 4.4)
    tone = low + high
    # The breath the bell sits on, and the reason there is one: two clean sines
    # in a forest read as a menu sound. Low-passed to nothing above a whisper.
    air = lowpass(noise(n, 7301), 700.0) * envelope(n, 0.20, 0.75, 2.0) * 0.14
    # 60 ms in and a long fall. The attack is the whole decision.
    return (tone + air) * envelope(n, 0.065, 0.80, 2.2)


def letter_captured():
    """A capture completing — the sunburst's chime (the letters round).

    `letter_appears`'s answer, and deliberately the opposite shape of the same
    material: that one is one bell fading in and this one is three notes
    arriving. A capture is the payout at the end of ten seconds of standing in
    the open with no weapon, and what the ear has to get from it is *finished*,
    which a single tone cannot say — `refill_chime` makes the same argument
    about a count and is why this is an arpeggio rather than a chord.

    Brighter than the appearance by about an octave and shorter by a fifth, so
    the pair read as a question and an answer rather than as two versions of
    one sound. Played in 3D at the pouch, so unlike its sibling it is a thing
    that happened *somewhere* and the people nearby can tell where.

    The shimmer on the tail is what keeps it from sounding like a lift arriving:
    two detuned voices sliding up and dying immediately, `range_orb`'s trick at
    a tenth of its depth.
    """
    n = seconds(0.7)
    t = np.linspace(0.0, n / RATE, n)
    out = np.zeros(n)
    # A major triad up again, an octave above `refill_chime`'s: the same
    # "gained" the range's furniture says, said in the register the letters
    # already own. Each voice enters a twelfth of the clip after the last, so
    # the three are distinct and the whole figure is over in a third of it.
    for i, freq in enumerate([1046.5, 1318.5, 1568.0]):
        start = int(n * 0.085 * i)
        m = n - start
        u = np.linspace(0.0, m / RATE, m)
        voice = np.zeros(n)
        # A quiet second partial per note, so each one is a struck thing rather
        # than a tone generator.
        voice[start:] = (np.sin(2.0 * np.pi * freq * u)
                         + 0.22 * np.sin(2.0 * np.pi * freq * 2.01 * u)) * np.exp(-u * 6.5)
        out += voice * (1.0 - 0.18 * i)
    shimmer = (sweep(n, 1800.0, 4200.0, 0.55) + 0.7 * sweep(n, 2350.0, 5300.0, 0.55))
    out += shimmer * np.exp(-t * 11.0) * 0.16
    # Gentle on the front for its sibling's reason — nothing about a prize
    # should sound like an impact — but a third of the fade, because this one
    # is confirming something that already happened.
    return out * envelope(n, 0.020, 0.72, 2.4)


def thunder_crack():
    """The Elder's bolt landing. The loudest thing in the game, on purpose.

    Thunder heard from a distance is all roll and no edge; thunder heard from
    thirty metres is a rifle crack with the roll arriving underneath it. This is
    the close one, because the bolt comes out of a hand in front of you rather
    than out of the sky (D-038), and it is built as four layers stacked in the
    order the ear receives them:

      snap  broadband noise with almost no attack, gone in a tenth of a second.
            Nothing is filtered off the top — the fizz *is* the crack, and it is
            what makes the sound read as near rather than as weather.
      body  the same noise taken down to a thud, which is the air column
            collapsing. Multiplied back up because a one-pole filter at 190 Hz
            throws away most of white noise's amplitude with its bandwidth.
      boom  a sub-bass drop, the one layer with a pitch, so the sound has a
            bottom on speakers that can reproduce one and a thump on ones that
            cannot.
      roll  a longer band-limited tail, amplitude-modulated by two slow sines
            at frequencies that do not divide into each other, so the tail
            wanders instead of pulsing.
    """
    n = seconds(0.95)
    t = np.linspace(0.0, n / RATE, n)
    snap = noise(n, 71) * envelope(n, 0.0004, 0.99, 7.0)
    body = lowpass(noise(n, 72), 190.0) * envelope(n, 0.004, 0.97, 2.4) * 3.6
    boom = sweep(n, 128.0, 36.0, 1.7) * envelope(n, 0.006, 0.96, 2.6) * 0.8
    roll = lowpass(noise(n, 73), 560.0) * envelope(n, 0.05, 0.92, 1.2) * 2.4
    roll *= 0.55 + 0.3 * np.sin(2.0 * np.pi * 3.1 * t)         + 0.15 * np.sin(2.0 * np.pi * 7.3 * t)
    return snap * 0.95 + body + boom + roll


def thunder_roll():
    """The half-second later half, played as a second voice at the same point.

    Two clips rather than one long one because they are mixed at different
    volumes and the balance between the crack and the roll is the whole
    difference between "a bolt hit near me" and "a storm is somewhere". Keeping
    them apart means that balance is a number in `LightningBolt` rather than a
    re-run of this script.

    All tail: no transient at all, so it can start under a crack that is already
    ringing without adding a second attack to it.
    """
    n = seconds(1.7)
    t = np.linspace(0.0, n / RATE, n)
    rumble = lowpass(noise(n, 74), 240.0) * 4.5
    # Three slow, mutually irrational swells. A single one reads as a tremolo
    # pedal; three read as distance.
    rumble *= 0.5 + 0.24 * np.sin(2.0 * np.pi * 1.7 * t)         + 0.16 * np.sin(2.0 * np.pi * 4.3 * t)         + 0.10 * np.sin(2.0 * np.pi * 9.1 * t + 1.1)
    # A long attack is what keeps it out of the crack's way, and a long decay is
    # what makes it a roll rather than a hit.
    return rumble * envelope(n, 0.18, 0.78, 1.5)


EFFECTS = {
    "spear_throw": spear_throw,
    "spear_hit_body": spear_hit_body,
    "spear_hit_world": spear_hit_world,
    "spear_ready": spear_ready,
    "bow_loose": bow_loose,
    "sword_swing": sword_swing,
    "sword_hit_body": sword_hit_body,
    "fist_hit": fist_hit,
    "shield_deploy": shield_deploy,
    "magnet_throw": magnet_throw,
    "magnet_arm": magnet_arm,
    "magnet_fire": magnet_fire,
    "death": death,
    "respawn": respawn,
    "hitmarker": hitmarker,
    "hitmarker_kill": hitmarker_kill,
    "range_board": range_board,
    "range_gong": range_gong,
    "range_orb": range_orb,
    "refill_chime": refill_chime,
    "rack_swap": rack_swap,
    "range_plate": range_plate,
    "letter_appears": letter_appears,
    "letter_captured": letter_captured,
    "thunder_crack": thunder_crack,
    "thunder_roll": thunder_roll,
}


def main():
    print("writing to audio/sfx/")
    for name in sorted(EFFECTS):
        write(name, EFFECTS[name]())
    print("writing to audio/ambience/")
    for name in sorted(AMBIENCE):
        # Ambience sits under the game rather than on top of it, so it is
        # normalised well below the effects.
        write(name, AMBIENCE[name](), AMBIENCE_DIR, AMBIENCE_RATE, peak=0.55)
    print("done.")


if __name__ == "__main__":
    main()
