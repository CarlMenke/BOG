extends SceneTree
## Where the events in a clip are, read off the clip's own kinematics, so a
## marker is placed from a measurement and then confirmed on a sheet rather
## than typed from a guess (D-097). Development tool, not shipped.
##
##   Godot --headless --path . --script tools/clip_events.gd -- Throw [Run ...]
##   Godot --headless --path . --script tools/clip_events.gd -- Throw --frames
##
## Per clip it proposes, from forward kinematics of the library clip on the
## body at every frame:
##   steps     the frame each toe plants: low, and still in the world the clip
##             was authored in (the hips are locked here, so a planted foot
##             moves backward at exactly the authored speed — D-066's rule)
##   hands     for each hand: the frame it is furthest in front of the hips,
##             every speed peak with its half-peak window (a combo has three),
##             its lowest and highest frame — D-063's rule is that extension
##             picks a release and the speed peak says which side of it
##   hips      lowest, highest, and the first frame back within 90% of the
##             start height after the lowest (a landing's recovery)
##   lift      the last frame a toe is down before both leave the ground
##   lips      the frames the left hand is at head height (a drink)
## `--frames` prints the per-frame table the proposals were read from.

const BODY := "res://art/bog/BOG.fbx"
const LIBRARY := "res://art/generated/bog_clips.res"
const ImportClip := preload("res://tools/import_clip.gd")
const FPS := 30.0
const TOE_DOWN := 0.06
const PLANT_SPEED := 0.6
const PEAK_FRACTION := 0.5

var _skeleton: Skeleton3D
var _forward: Vector3


func _initialize() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	_skeleton = body.find_child("Skeleton3D", true, false)
	var lib := load(LIBRARY) as AnimationLibrary
	var args := OS.get_cmdline_user_args()
	var frames := args.has("--frames")
	var keys: Array = []
	for a in args:
		if not a.begins_with("--"):
			keys.append(a)
	if keys.is_empty():
		keys = Array(lib.get_animation_list())
		keys.sort()

	var rest := ImportClip._positions(null, _skeleton, {}, -1.0)
	var left := rest[_b("LeftUpLeg")] - rest[_b("RightUpLeg")]
	_forward = Vector3(left.x, 0.0, left.z).normalized().cross(Vector3.UP).normalized()

	for key in keys:
		if not lib.has_animation(key):
			print("clip_events: no clip '%s'" % key)
			continue
		_report(key, lib.get_animation(key), frames)
	quit()


func _report(key: String, anim: Animation, frames: bool) -> void:
	var tracks := ImportClip._tracks_by_bone(anim)
	var n := int(round(anim.length * FPS)) + 1
	var travel: Vector3 = anim.get_meta("travel", Vector3.ZERO)
	var drift := travel / anim.length if anim.length > 0.0 else Vector3.ZERO
	var rows := []
	for f in n:
		var t := minf(float(f) / FPS, anim.length)
		var p := ImportClip._positions(anim, _skeleton, tracks, t)
		var hips := p[_b("Hips")]
		rows.append({
			"t": t, "hips": hips.y, "head": p[_b("Head")],
			"ltoe": p[_b("LeftToe_End")], "rtoe": p[_b("RightToe_End")],
			"rhand": p[_b("RightHand")], "lhand": p[_b("LeftHand")],
			"rfwd": (p[_b("RightHand")] - hips).dot(_forward),
			"lfwd": (p[_b("LeftHand")] - hips).dot(_forward),
		})
	for f in n:
		var prev: Dictionary = rows[maxi(f - 1, 0)]
		var next: Dictionary = rows[mini(f + 1, n - 1)]
		var dt := float(mini(f + 1, n - 1) - maxi(f - 1, 0)) / FPS
		for part in ["rhand", "lhand", "ltoe", "rtoe"]:
			var v: Vector3 = (next[part] - prev[part]) / dt if dt > 0.0 else Vector3.ZERO
			# A foot's speed in the authored world: what it does on the locked
			# hips, plus the travel the lock took away.
			rows[f][part + "_speed"] = (v + drift).length() if part.ends_with("toe") else v.length()

	print("\n== %s  (%.3f s, %d frames, %s, %.2f m/s)" % [key, anim.length, n,
		"loop" if anim.loop_mode != Animation.LOOP_NONE else "once", drift.length()])
	if frames:
		print("   f     t   hips  ltoe ltspd  rtoe rtspd   rfwd rspd  r.y   lfwd lspd  l.y")
		for f in n:
			var r: Dictionary = rows[f]
			print("%4d %5.2f  %5.3f %5.3f %5.2f %5.3f %5.2f  %5.2f %4.1f %5.2f  %5.2f %4.1f %5.2f" % [
				f, r.t, r.hips, r.ltoe.y, r.ltoe_speed, r.rtoe.y, r.rtoe_speed,
				r.rfwd, r.rhand_speed, r.rhand.y, r.lfwd, r.lhand_speed, r.lhand.y])

	var steps := []
	for foot in ["ltoe", "rtoe"]:
		var down := false
		for f in n:
			var planted: bool = rows[f][foot].y < TOE_DOWN and rows[f][foot + "_speed"] < PLANT_SPEED
			if planted and not down:
				steps.append("%s %.3f" % ["left" if foot == "ltoe" else "right", rows[f].t])
			down = planted
	print("  steps    %s" % (", ".join(steps) if not steps.is_empty() else "none"))

	for hand in ["rhand", "lhand"]:
		var fwd: String = hand.left(1) + "fwd"
		var best_f := 0
		var low_f := 0
		var high_f := 0
		var peak := 0.0
		for f in n:
			if rows[f][fwd] > rows[best_f][fwd]:
				best_f = f
			if rows[f][hand].y < rows[low_f][hand].y:
				low_f = f
			if rows[f][hand].y > rows[high_f][hand].y:
				high_f = f
			peak = maxf(peak, rows[f][hand + "_speed"])
		var peaks := []
		for f in range(1, n - 1):
			var s: float = rows[f][hand + "_speed"]
			if s >= peak * PEAK_FRACTION and s >= rows[f - 1][hand + "_speed"] and s > rows[f + 1][hand + "_speed"]:
				var open := f
				var close := f
				while open > 0 and rows[open - 1][hand + "_speed"] > s * 0.5:
					open -= 1
				while close < n - 1 and rows[close + 1][hand + "_speed"] > s * 0.5:
					close += 1
				peaks.append("%.3f (%.1f m/s, %.3f-%.3f)" % [rows[f].t, s, rows[open].t, rows[close].t])
		print("  %s hand   forward %.3f (%.2f m)   lowest %.3f (%.2f m)   highest %.3f (%.2f m)" % [
			"right" if hand == "rhand" else "left ", rows[best_f].t, rows[best_f][fwd],
			rows[low_f].t, rows[low_f][hand].y, rows[high_f].t, rows[high_f][hand].y])
		print("             peaks %s" % ", ".join(peaks))

	var low_f := 0
	var high_f := 0
	for f in n:
		if rows[f].hips < rows[low_f].hips:
			low_f = f
		if rows[f].hips > rows[high_f].hips:
			high_f = f
	var recover := -1
	for f in range(low_f, n):
		if rows[f].hips >= rows[0].hips * 0.9:
			recover = f
			break
	print("  hips     lowest %.3f (%.3f m)   highest %.3f (%.3f m)   recovered %s" % [rows[low_f].t, rows[low_f].hips,
		rows[high_f].t, rows[high_f].hips, "%.3f" % rows[recover].t if recover >= 0 else "never"])

	var lift := -1
	for f in n:
		if rows[f].ltoe.y < TOE_DOWN or rows[f].rtoe.y < TOE_DOWN:
			lift = f
		elif lift >= 0:
			break
	if lift >= 0 and lift < n - 1:
		print("  lift     %.3f (last frame a toe is down before both are up)" % rows[lift].t)

	var lips_open := -1
	var lips_close := -1
	for f in n:
		if rows[f].lhand.y > rows[f].head.y - 0.10:
			if lips_open < 0:
				lips_open = f
			lips_close = f
	if lips_open >= 0:
		print("  lips     left hand at head height %.3f-%.3f" % [rows[lips_open].t, rows[lips_close].t])


func _b(short: String) -> int:
	return _skeleton.find_bone("mixamorig_" + short)
