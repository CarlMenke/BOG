extends Node
## Bus volumes and fire-and-forget sound playback. Autoloaded as `AudioDirector`.
##
## Gameplay code should never create its own AudioStreamPlayer for a one-shot:
## spear throws, hits and footsteps all fire in bursts, and a fresh node per
## sound means allocation churn plus a real chance of leaking players that never
## finish. Everything short goes through a fixed pool here instead.

## The sound library, preloaded once. Callers name a sound rather than a path,
## so nothing in gameplay code has to know where the files live or hold a
## reference that keeps a stream alive.
##
## Every one of these is synthesised by `tools/make_sfx.py` rather than
## recorded — see the header of that file for why, and re-run it to change one.
const SPEAR_THROW := preload("res://audio/sfx/spear_throw.wav")
const SPEAR_HIT_BODY := preload("res://audio/sfx/spear_hit_body.wav")
const SPEAR_HIT_WORLD := preload("res://audio/sfx/spear_hit_world.wav")
const SPEAR_READY := preload("res://audio/sfx/spear_ready.wav")
## The bow's loose (D-065). Almost none of it is the string: the arrow takes the
## energy and what is heard is the limbs arriving at brace, which is a block of
## wood being hit from the inside. There is no draw sound and that is a decision
## rather than a gap — see `bow_loose` in `tools/make_sfx.py`.
const BOW_LOOSE := preload("res://audio/sfx/bow_loose.wav")
## The great sword, in two halves (D-068).
##
## `SWORD_SWING` is the **one clip in this library that is locked to an
## animation**. It is 1.867 s long because that is `BogAnimator.SWING_SECONDS`,
## it is played on the frame the spin starts rather than on the frame the blade
## lands, and its loudness peaks 1.067 s in because that is
## `SWING_RELEASE_TIME` — where the build measures peak hand speed, which is
## where a sword cuts. Two things follow for callers. It must be fired from
## `_begin_swing`, the one function every peer runs at clip time zero; and it
## must be played at **pitch 1.0**, never through `play_3d_varied`, because a
## 12% pitch spread would slide the peak of the whoosh a tenth of a second off
## the blade and the swing would read as a different swing.
const SWORD_SWING := preload("res://audio/sfx/sword_swing.wav")
const SWORD_HIT_BODY := preload("res://audio/sfx/sword_hit_body.wav")
const SHIELD_DEPLOY := preload("res://audio/sfx/shield_deploy.wav")
const MAGNET_THROW := preload("res://audio/sfx/magnet_throw.wav")
const MAGNET_ARM := preload("res://audio/sfx/magnet_arm.wav")
const MAGNET_FIRE := preload("res://audio/sfx/magnet_fire.wav")
const DEATH := preload("res://audio/sfx/death.wav")
const RESPAWN := preload("res://audio/sfx/respawn.wav")
## The two confirmations of your own aim, and the only 2D clips in the library
## that are not UI: a hit and the hit that finished somebody. `HITMARKER_KILL`
## is the same tick with a short low drop under it, so a kill is heard as the
## end of the string of hits it ends rather than as an unrelated noise.
const HITMARKER := preload("res://audio/sfx/hitmarker.wav")
const HITMARKER_KILL := preload("res://audio/sfx/hitmarker_kill.wav")

## The practice range's two non-Bog targets. They are here rather than in the
## range's own files for the reason everything else here is: a caller names a
## sound and never a path, and a sound that lives somewhere else is a second
## place to look.
##
## `RANGE_GONG` is the only clip in the library played at a pitch the caller
## chooses — `Gong` shifts it by how far the shot came from, which is the thing
## a gong at the spear's flat band exists to teach — so it is written to stay
## clean over about a fifth either side of unity.
const RANGE_BOARD := preload("res://audio/sfx/range_board.wav")
const RANGE_GONG := preload("res://audio/sfx/range_gong.wav")

## The practice range's two furniture sounds: the refill stone filling somebody
## up, and a weapon coming off a rack.
##
## Beside the targets above and for their reason. Both are played in 3D at the
## thing that made them, on every peer — the stone's because the counts it
## changed are already replicated, the rack's because the weapon swap is (D-115)
## — so neither is a cue for one player the way `SPEAR_READY` is.
const REFILL_CHIME := preload("res://audio/sfx/refill_chime.wav")
const RACK_SWAP := preload("res://audio/sfx/rack_swap.wav")

## The range's one remaining control: a parkour timing plate being crossed.
## Here beside the furniture above for its reason.
##
## `RANGE_CHIME` stood beside it and is gone with the stations. It was a struck
## bowl played at `2 ** (step / 12)` — an inharmonic partial stack, so that
## transposing it by a semitone gave the same object struck rather than a
## different note of the same instrument — and the pitch was the *message*:
## which note you heard was which behaviour a station had just stepped its zone
## to. With a zone's behaviour authored in the map and never changing there is
## no step to report, and the stats signboard that replaced the last station
## makes no sound at all: its feedback is the HUD panel going to zero, which is
## what you were looking at when you reset it.
const RANGE_PLATE := preload("res://audio/sfx/range_plate.wav")

## B·O·G's two letter sounds (the letters round), and they are a pair: a
## question and an answer, written to be heard as two halves of one mechanic
## rather than as two events.
##
## `LETTER_APPEARS` is a soft bell played **2D on every machine**, which is the
## only sound in this library outside the hitmarkers that is flat in both ears
## and is not UI. That is the mechanic rather than a convenience: in the
## free-for-all there is exactly one letter out at a time, so where it landed is
## the whole of the game for the next thirty seconds and everybody has to learn
## about it at the same instant — a positional cue would tell the people
## standing near it and nobody else. The guide line is what says *which way*;
## this only says *now*.
##
## `LETTER_CAPTURED` is the chime under the sunburst, played **3D at the pouch**
## the letter just sank into, because that one did happen somewhere and the
## people nearby are the ones who just failed to stop it. Fired by `CaptureRig`
## on every peer off `MatchState.letter_banked`, so it is an event the lobby
## heard and not a private reward on the capturer's machine.
const LETTER_APPEARS := preload("res://audio/sfx/letter_appears.wav")
const LETTER_CAPTURED := preload("res://audio/sfx/letter_captured.wav")
## The Elder's bolt, in two voices rather than one (D-038). The crack is the
## strike and the roll is what follows it half a second later, and they are
## separate clips because the balance between them is what decides whether a
## bolt reads as landing *near you* or as weather somewhere — a number in
## `LightningBolt`, not a re-run of `tools/make_sfx.py`.
const THUNDER_CRACK := preload("res://audio/sfx/thunder_crack.wav")
const THUNDER_ROLL := preload("res://audio/sfx/thunder_roll.wav")

## Ambience beds. These loop seamlessly by construction rather than by
## crossfading — see `looping_noise` in tools/make_sfx.py — so they can be left
## running for a whole match without the loop point ever announcing itself.
const AMBIENT_WIND := preload("res://audio/ambience/ambient_wind.wav")
const AMBIENT_FOREST := preload("res://audio/ambience/ambient_forest.wav")

const BUSES := {
	"volume_master": "Master",
	"volume_music": "Music",
	"volume_sfx": "SFX",
	"volume_ambience": "Ambience",
}

## Enough voices for a busy fight without ever growing at runtime.
const POOL_2D := 12
const POOL_3D := 24

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0


func _ready() -> void:
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 60.0
		p.unit_size = 6.0
		add_child(p)
		_pool_3d.append(p)

	Settings.changed.connect(_on_setting_changed)
	apply_all_volumes()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if BUSES.has(key):
		apply_volume(key)


func apply_all_volumes() -> void:
	for key: String in BUSES:
		apply_volume(key)


func apply_volume(key: String) -> void:
	var bus_index := AudioServer.get_bus_index(BUSES[key])
	if bus_index < 0:
		return
	var linear := clampf(float(Settings.get_value(key)), 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, linear <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear, 0.001)))


## Play a UI or non-positional sound.
func play_2d(stream: AudioStream, bus: String = "SFX", pitch: float = 1.0,
		volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	p.bus = bus
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## Play a sound at a world position. Returns the player so a caller can follow
## it to a moving source if it needs to; most callers should ignore it.
func play_3d(stream: AudioStream, position: Vector3, pitch: float = 1.0,
		volume_db: float = 0.0, bus: String = "SFX") -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	p.bus = bus
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.global_position = position
	p.play()
	return p


## Small random pitch variation so repeated sounds do not machine-gun.
func play_3d_varied(stream: AudioStream, position: Vector3, spread: float = 0.12,
		volume_db: float = 0.0) -> void:
	play_3d(stream, position, randf_range(1.0 - spread, 1.0 + spread), volume_db)
