extends RangeBrain
## Stands on its mark and faces you.
##
## The default, the fallback for an unknown name, and nine of the range's
## twenty-three live dummies — every dummy in a throwing lane and every dummy in
## the magnet clump. A still target at a known distance is what a weapon is
## learned against before anything else, and the lanes exist to say "eight,
## fifteen, twenty-two metres" without qualification.
##
## The one thing it does that standing still does not is turn: `look_yaw`
## follows the nearest living human, so a lane dummy is always presenting its
## front. That matters for the bone the hit is reported on and for reading a
## silhouette at 22 m in the dark, and it costs one number a tick.


func drive(bog: Bog, delta: float) -> void:
	_t += delta
	hold(bog)
