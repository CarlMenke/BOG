class_name CaptureRig
extends Node3D
## The capture performance: the letter a Bog is pulling out of the air and down
## into its pouch.
##
## The owner, in full, because every number below is one clause of it: *"when
## the bog first captures the letter, it will be above their right hand, bigger
## and floating kinda high; their right hand will be up in the air, as if it's
## pulling the letter down; there is a small woolen loot pouch in the user's
## left hand, down by their hip, maybe a little up and out; as the time
## progresses the letter gets smaller and slowly moves down into the pouch;
## when it hits 0, a short small gold array of sunburst, along with a sound."*
## And the reason it exists at all: *"players might incorrectly assume you can
## punch, so make it so they are actually doing something with their hands —
## capturing."*
##
## **A timed hold only.** A Capture B·O·G carry is the same row in `MatchState`
## with `ends_at = INF` — nothing is counting down, the card is being *run*
## somewhere — so a carry keeps the card in the fist it has had since D-035 and
## this rig stays hidden. What distinguishes the two is
## `MatchState.letter_hold_is_timed`, asked here and asked in the same breath
## by `BogCombat._refresh_hand` and `BogAnimator`, so the three cannot disagree
## about which performance a Bog is in the middle of.
##
## **On every peer, for every Bog.** `Bog._build_capture_rig` adds one to every
## body the moment it is equipped, and this node never asks who is local: a
## capture is ten seconds of standing in the open, and the whole of what it
## buys the rest of the lobby is that they can see it happening from across a
## clearing. A rig that only ran on the capturing player's own machine would be
## the vulnerability with its tell removed.
##
## **The letter floats, it is not pinned.** It rides a top-level pivot in world
## space between two anchors read off the hands each frame, which is what lets
## the Bog keep running, jumping and turning through a capture with the card
## trailing it rather than welded to a wrist. `HeldGear` holds the *other* card
## — the one in the fist for a CTF carry — and these two are deliberately the
## only two homes a letter has on a body (D-098).
##
## One concern, one home: the descent, the steal's rise, the burst and the
## chime are all the same performance seen at four moments, so they are one
## node rather than four listeners scattered over the HUD, the combat node and
## the pickup.

## Where the letter starts: above the raised right hand, in metres.
##
## `hand_transform().origin` is the wrist, and the clip has the arm up, so this
## puts the card about a head above the fingertips — *"above their right hand,
## bigger and floating kinda high"*, with the gap that makes the arm read as
## pulling it down rather than holding it.
const HAND_LIFT := 0.55

## How big the card is at each end of the descent, as a multiple of the card on
## the ground (`Pickup.build_card` is 1.0).
##
## The range is the clock. A player glancing at a Bog has to be able to tell
## how far along a capture is without reading the HUD, and the one property
## that survives being seen at thirty metres through trees is *size*: 1.6 is
## unmistakably bigger than a dropped card and 0.25 is a spark going into a
## sack. Colour cannot do this job — every letter is the same gold — and
## position cannot do it alone, because a Bog may be facing any way.
const SCALE_FROM := 1.6
const SCALE_TO := 0.25

## The float. Amplitude in metres and the sine's rate in radians a second,
## faded out by the fraction so the card is restless at the top and dead still
## as it enters the pouch — the settling is half of what makes the ending read
## as an arrival.
##
## Slower and shallower than `Pickup.BOB_SPEED`/`BOB_HEIGHT` on the ground
## (2.2 and 0.11), on purpose: a card lying in the grass is bobbing to be
## *found* and this one has already been found.
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.6

## How fast the card turns on its own axis, in radians a second, faded out by
## the fraction like the bob. A spin says "not yet yours"; a card that has
## stopped turning is one that has been taken.
const SPIN_SPEED := 1.1

## The light riding the card, and how much of it the descent spends.
##
## `HeldGear.CARD_LIGHT_ENERGY`'s twin and the same 1.8 for the same reason: at
## range a gold card on a gold Bog is a smudge and what carries is that the
## body is *lit*. The fade is only 70% rather than to nothing, because the last
## thing the light does is put a rim on the pouch the letter is entering.
const LIGHT_ENERGY := 1.8
const LIGHT_DIM := 0.7
const LIGHT_RANGE := 4.0

## The steal (D-092), which is the same performance run backwards: the card
## comes *up* out of somebody's vault into the raised hand while the clock
## fills. How high above the vault it starts, and how much bigger it gets on
## the way — it grows rather than shrinks, because a steal ends with the thief
## holding it up and not with it put away.
const STEAL_RISE := 0.6
const STEAL_SCALE_FROM := 1.0
const STEAL_SCALE_TO := 1.3

var _bog: Bog
## The card's own pivot, `top_level` so it lives in world space and is not
## dragged about by the body it belongs to. Built once per letter and kept,
## because a capture is ten seconds long and nothing about it is frequent.
var _pivot: Node3D
var _light: OmniLight3D
var _letter: int = 0
var _spin: float = 0.0
var _clock: float = 0.0

## Whether last frame's hold was a timed one. Read at the moment a bank lands,
## because the row is already gone by then and the burst has two homes: the
## pouch, for a capture that just finished, and the raised hand, for a CTF
## carry run into a vault.
var _was_timed: bool = false

## The steal in progress on this Bog, or letter 0 for none. Held rather than
## re-derived because `steal_progress` is the only place the vault, the letter
## and the fraction arrive together.
var _steal_letter: int = 0
var _steal_from: int = -1
var _steal_done: float = 0.0


func _ready() -> void:
	_bog = get_parent() as Bog
	if _bog == null:
		push_error("CaptureRig expects to be a child of a Bog")
		return
	# World space, like every other thing in this game built from a world point
	# (`WardFlash`, `SpearTrail`): the two anchors are read off bones in global
	# metres and a rig that inherited the body's transform would apply them
	# twice.
	top_level = true
	transform = Transform3D.IDENTITY

	MatchState.letter_banked.connect(_on_letter_banked)
	MatchState.steal_progress.connect(_on_steal_progress)
	MatchState.letter_stolen.connect(_on_letter_stolen)


func _process(delta: float) -> void:
	if _bog == null or _bog.held_gear == null:
		return
	_clock += delta
	var peer := _bog.peer_id
	var timed := MatchState.letter_hold_is_timed(peer)
	if timed:
		_run_capture(peer, delta)
	elif _steal_letter != 0:
		_run_steal(delta)
	else:
		_put_away()
	_was_timed = timed


## The descent. Everything in it is a function of one replicated number, which
## is the whole reason this reads the same on eight machines: nobody predicts a
## hold locally (`BogCombat.is_holding_letter` says why), so every peer is
## drawing the same fraction of the same clock.
func _run_capture(peer: int, delta: float) -> void:
	_ensure_card(MatchState.letter_hold_letter(peer))
	if _pivot == null:
		return
	var f := clampf(MatchState.letter_hold_fraction(peer), 0.0, 1.0)
	# Smoothstepped rather than linear, and it is the one easing in this file
	# that is about the *feel* rather than the read: a card that sets off the
	# instant the clock starts reads as falling, and the thing being drawn is a
	# Bog pulling something down against its will.
	var eased := smoothstep(0.0, 1.0, f)
	var at: Vector3 = _hand_anchor().lerp(_bog.held_gear.pouch_mouth_global(), eased)
	at.y += BOB_HEIGHT * (1.0 - f) * sin(BOB_SPEED * _clock)
	_place(at, lerpf(SCALE_FROM, SCALE_TO, eased), SPIN_SPEED * (1.0 - f), delta)
	_light.light_energy = LIGHT_ENERGY * (1.0 - LIGHT_DIM * f)


## The steal's rise, off `steal_progress`'s own fraction.
##
## A **ghost** in the sense that it is drawn from a card that is still in
## somebody's vault — the letter has not moved and will not until the steal
## completes. That is honest rather than a cheat: what the thief is doing is
## dragging it out, and what everybody else needs to see is how nearly they
## have managed it.
func _run_steal(delta: float) -> void:
	_ensure_card(_steal_letter)
	if _pivot == null:
		return
	var layout := MatchState.capture_layout()
	var from := Vector3.ZERO
	if layout != null and _steal_from >= 0 and _steal_from < layout.vaults.size():
		from = layout.vaults[_steal_from]
	var done := clampf(_steal_done, 0.0, 1.0)
	var at := (from + Vector3.UP * STEAL_RISE).lerp(_hand_anchor(), done)
	# No bob and a full-rate spin for the whole rise. The capture's bob fades
	# out because it is settling into a pouch; a steal ends in the air, so
	# there is nothing for it to settle into and a card that went still
	# half-way up would read as one that had got stuck.
	_place(at, lerpf(STEAL_SCALE_FROM, STEAL_SCALE_TO, done), SPIN_SPEED, delta)
	_light.light_energy = LIGHT_ENERGY


## Where the raised hand's letter sits, in world metres. The top of the
## capture's arc and the top of the steal's, which is deliberate: the two
## performances are the same arm doing the same thing in two directions, and a
## thief who has just pulled a card out of a vault is holding it exactly where
## a capturer is about to start pulling one down from.
func _hand_anchor() -> Vector3:
	return _bog.held_gear.hand_transform().origin + Vector3.UP * HAND_LIFT


func _place(at: Vector3, size: float, spin: float, delta: float) -> void:
	_spin = wrapf(_spin + spin * delta, 0.0, TAU)
	_pivot.visible = true
	_pivot.global_position = at
	# Upright by construction, and that is the difference from the card in the
	# fist. `HeldGear._process` has to take the orientation back off the wrist
	# every frame because its card hangs off a bone; this pivot is `top_level`
	# and inherits nothing, so a yaw about world up is all there is and the
	# letter can never be tipped onto its face.
	_pivot.global_basis = Basis(Vector3.UP, _spin).scaled(Vector3.ONE * size)
	_light.global_position = at


## Where the floating letter is right now, in world metres, or `Vector3.INF`
## when there is none up. For `tools/preview_capture.tscn`, which reads the
## descent off a running Bog rather than recomputing it — a tool that did the
## arithmetic again would be measuring its own copy of this file.
func letter_global() -> Vector3:
	if _pivot == null or not _pivot.visible:
		return Vector3.INF
	return _pivot.global_position


## How big the card is drawn right now, as the multiple of a ground card that
## `SCALE_FROM`/`SCALE_TO` interpolate. 0.0 when nothing is up.
func letter_size() -> float:
	if _pivot == null or not _pivot.visible:
		return 0.0
	return _pivot.global_basis.get_scale().y


func _put_away() -> void:
	if _pivot != null:
		_pivot.visible = false
	if _light != null:
		_light.light_energy = 0.0


## Build the card for `letter`, or keep the one already up.
##
## Freed and rebuilt rather than kept and re-lettered, exactly as
## `HeldGear.set_letter` is and for its reason: the glyph is baked into the
## mesh, so there is no cheaper way to change it, and a letter changes at most
## three times in a match.
func _ensure_card(letter: int) -> void:
	if letter == _letter and _pivot != null:
		return
	_letter = letter
	if _pivot != null:
		_pivot.queue_free()
		_pivot = null
	if letter == 0:
		return
	_pivot = Pickup.build_card(letter)
	_pivot.top_level = true
	add_child(_pivot)
	# Start it facing the way the Bog is, so the first frame of a capture shows
	# the glyph to the person capturing rather than to whoever happens to be
	# behind them. After that the spin owns it.
	_spin = _bog.body_yaw

	if _light == null:
		# A sibling of the card and never a child of it, which is the trap
		# `HeldGear.set_letter` had to divide its range back out of: a light
		# parented to the pivot would inherit the 1.6 -> 0.25 scale and its
		# reach would shrink with the glyph, which is the one part of this a
		# player would never notice had changed and the part that carries at
		# range.
		_light = OmniLight3D.new()
		_light.name = "CaptureGlow"
		_light.light_color = Pickup.LETTER_COLOUR
		_light.omni_range = LIGHT_RANGE
		_light.shadow_enabled = false
		add_child(_light)


## The payout. Fired on every peer from a replicated signal, so the burst and
## the chime are an event the lobby saw.
##
## **Two places it can go off**, and the flag was cached a frame ago because
## the row that would answer the question is erased by the time this arrives: a
## timed capture ends at the pouch, which is where the letter was last seen
## going; a CTF carry ends at the raised hand, because the card was in the fist
## the whole way and there is no pouch on that Bog.
func _on_letter_banked(peer_id: int, _letter_bit: int) -> void:
	if _bog == null or peer_id != _bog.peer_id or _bog.held_gear == null:
		return
	var at: Vector3 = _bog.held_gear.pouch_mouth_global() if _was_timed \
		else _bog.held_gear.hand_transform().origin
	_burst(at)


## A steal's progress, or its end. `letter == 0` is `MatchState` saying the
## steal was interrupted — the thief moved, died or was beaten to it — and the
## ghost goes away without a burst, because nothing was taken.
func _on_steal_progress(peer_id: int, letter: int, from_team: int, done: float) -> void:
	if _bog == null or peer_id != _bog.peer_id:
		return
	_steal_letter = letter
	_steal_from = from_team
	_steal_done = done
	if letter == 0:
		_put_away()


func _on_letter_stolen(peer_id: int, _letter_bit: int, _from_team: int) -> void:
	if _bog == null or peer_id != _bog.peer_id or _bog.held_gear == null:
		return
	_burst(_hand_anchor())
	_steal_letter = 0
	_steal_done = 0.0
	_put_away()


func _burst(at: Vector3) -> void:
	Sunburst.fire(_burst_root(), at)
	AudioDirector.play_3d(AudioDirector.LETTER_CAPTURED, at)


## Where a burst is parented. `MatchState._spawn_root`'s idiom, and it matters
## here for one reason: a burst hung off the Bog would be taken away with the
## body the frame somebody died on the one they banked.
func _burst_root() -> Node:
	var root := get_tree().get_first_node_in_group("spawned_items")
	return root if root != null else get_tree().current_scene
