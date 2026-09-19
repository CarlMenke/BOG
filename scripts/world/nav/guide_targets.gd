class_name GuideTargets
extends RefCounted
## What the guide line should be pointing at, right now, for me.
##
## Kept apart from the drawing on purpose. "Where is the letter" is a question
## about the match and it is answered by reading `MatchState` and `Net`;
## "what does a dashed ribbon look like from here" is a question about a camera
## and a mesh. One file each (D-098), and this one is the half a harness can
## call and assert on without a viewport.
##
## It reads the match and never writes it. The guide line is a drawing on one
## screen (D-010): two clients disagreeing about which letter to point at is a
## difference nobody can see and no rule can feel (D-007).
##
## The rules, in the owner's order:
##
##   - Nothing at all outside B·O·G, outside PLAYING, or while you are dead. A
##     line over a kill-limit match is a promise of a rule that is not there.
##   - **Capturing a letter?** Nothing. You are standing still with your arm in
##     the air for four seconds; a line telling you to go somewhere is telling
##     you to throw the capture away.
##   - **Carrying one** (a Capture card, which has no clock)? One target: your
##     own vault, in ally blue. Everything else on the map is a distraction
##     from the thing you are holding.
##   - Otherwise: every loose card that is not already banked for your team,
##     gold; and everybody carrying one, red if they are not yours and blue if
##     they are — go kill them, or go cover them.

## `{pos: Vector3, colour: Color, kind: String, key: String}`. `key` is what
## keeps a line's smoothing and its fade attached to the same target between
## frames, which matters because targets walk about.
const KIND_LOOSE := "loose"
const KIND_ENEMY := "enemy"
const KIND_ALLY := "ally"
const KIND_VAULT := "vault"


static func resolve() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not MatchConfig.is_bog(Net.config.win_condition):
		return out
	if MatchState.phase != MatchState.Phase.PLAYING:
		return out

	var me := Net.local_id()
	if not MatchState.is_alive(me):
		return out
	var my_team := Net.player_team(me)

	# A timed hold is a capture in progress: stand still, say nothing.
	if MatchState.letter_hold_is_timed(me):
		return out

	# A hold with no clock is a Capture carry. Home is the only target.
	if MatchState.is_holding_letter(me):
		var layout := MatchState.capture_layout()
		if layout != null and my_team >= 0 and my_team < layout.vaults.size():
			out.append({
				"pos": layout.vaults[my_team],
				"colour": UIPalette.GUIDE_ALLY,
				"kind": KIND_VAULT,
				"key": "vault:%d" % my_team,
			})
		return out

	for pickup: Pickup in MatchState.loose_letter_pickups():
		if not is_instance_valid(pickup) or pickup.is_taken():
			continue
		# A card standing in my own vault is already home. Pointing at it would
		# read as "go and fetch the thing you have won".
		if my_team != MatchConfig.TEAM_NONE and MatchState.banked_team_of(pickup.letter) == my_team:
			continue
		out.append({
			"pos": pickup.global_position,
			"colour": UIPalette.GUIDE_LOOSE,
			"kind": KIND_LOOSE,
			"key": "loose:%d" % pickup.letter,
		})

	for peer_id: int in MatchState.letter_carriers():
		if peer_id == me or not MatchState.is_alive(peer_id):
			continue
		var bog := MatchState.bogs.get(peer_id) as Bog
		if bog == null or not is_instance_valid(bog):
			continue
		# `TEAM_NONE` on both sides is free-for-all, where everybody carrying a
		# letter is somebody to kill.
		var their_team := Net.player_team(peer_id)
		var friendly := my_team != MatchConfig.TEAM_NONE and their_team == my_team
		out.append({
			"pos": bog.global_position,
			"colour": UIPalette.GUIDE_ALLY if friendly else UIPalette.GUIDE_ENEMY,
			"kind": KIND_ALLY if friendly else KIND_ENEMY,
			"key": "peer:%d" % peer_id,
		})
	return out
