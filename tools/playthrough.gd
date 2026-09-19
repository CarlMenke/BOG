extends Node
## Drives the whole game once, from the main menu to the results screen, and
## asserts something real at every stop. Development tool, not shipped. Runs
## headless in a handful of seconds.
##
##   Godot --headless --path . tools/playthrough.tscn
##
## Every other harness in this folder looks at one seam. `match_rules` scores a
## match that has no island under it, `combat_range` throws a spear in a room
## with no lobby in front of it, `ui_range` photographs screens that were never
## navigated to. Each of those was worth writing and none of them would notice
## if the menu stopped handing off to the lobby, if `request_match_start` never
## reached the arena, or if the results screen sat behind the HUD it is supposed
## to replace. Those are joins between parts, they are exactly where the bugs
## that survive a code review live, and until this file existed nothing had ever
## walked across all of them in one go.
##
## So this is the *whole* path, in order, through the real shipping scenes and
## the real autoloads:
##
##   main menu -> host -> lobby -> start -> arena builds -> warmup -> match
##   plays -> kill limit trips -> results screen
##
## The only things faked are the things that cannot exist on one machine: the
## session has no socket (`Net.start_offline`, D-011) and the other players are
## roster entries with nobody behind them. Everything else is the code that
## ships. Nothing here reaches past a public API except where a comment says
## otherwise and why.
##
## Like `tools/match_rules.gd`, this runs as a *scene* rather than as a
## `--script` main loop: a script main loop is compiled before the autoloads are
## registered, so it cannot so much as name `Net` or `MatchState` without
## failing to parse (D-015).
##
## Pass a `MapCatalog` id after a `--` to play the whole thing on that map:
##
##   Godot --headless --path . tools/playthrough.tscn -- rust
##
## Everything above is the same run either way — the point is that the *joins*
## do not care which map is loading, and the only way to know that is to walk
## them again with a different one underneath. A static map takes a different
## branch in `arena.gd` and brings its own environment, lights, collision and
## spawns (D-030, D-031), so a few extra checks in `_stage_arena` look at
## whichever of the two actually happened.

## Peer ids for the stand-in players. ENet hands out ids at random across the
## whole positive int range, so no band is truly safe; what these have to avoid
## is the *other* harnesses, since a shared id would make two testbeds
## impossible to tell apart in a log. `ui_range` owns the 700s, `combat_range`
## the 900s, `BogBackdrop` the 8100s. This takes the 500s.
const FAKE_BASE := 500

## The stand-ins. The first of them does all the killing and therefore wins, so
## the winner's name is a fixed, known string — the *local* player's name is
## whatever was last typed into a name box and persisted into Godot's user-data
## directory, which is shared by every checkout of this project, so it cannot be
## asserted on. (`tools/smoke_test.sh` learned the same lesson about the killer
## name in the combat range.)
const FAKE_NAMES := ["Pipwick", "Thistle", "Mossback", "Bramblewick"]

## Warmup is shortened from the shipping default of five seconds. It is not
## skipped: the point is to watch the phase actually pass through WARMUP on its
## way to PLAYING, which is the transition the HUD's opening countdown hangs off.
const WARMUP_TIME := 0.5
## Spawn protection off, respawn delay to nothing. Both are deliberate and both
## are set the way a host sets them — through `Net.update_config`. Protection in
## particular has to go: it defaults to two seconds, a protected Bog correctly
## refuses to die, and leaving it on simply makes the kill loop spin until it
## gives up. That cost an hour in `match_rules` and the note is repeated here
## because the symptom (scoring looks broken) points nowhere near the cause.
const SPAWN_PROTECTION := 0.0
const RESPAWN_DELAY := 0.0

## How many physics ticks a newly spawned Bog gets to land on its pad before
## "is it standing on the map" is asked. Deliberately **not** one of the
## wall-clock budgets below: see `_settle_on_floor`.
const SETTLE_TICKS := 30

## Wall-clock budgets. Generous, because they exist to turn a hang into a
## legible failure rather than to measure anything.
const SCENE_TIMEOUT := 30.0
## The island build is 2-6 seconds of blocking work inside `arena.gd::_ready`,
## and a cold import or a loaded machine can make that a good deal worse. This
## is the one wait that must never be a fixed frame count.
const ARENA_TIMEOUT := 120.0
const PHASE_TIMEOUT := 30.0
const KILL_TIMEOUT := 60.0

## The shipping script whose row eviction decides whether a match can survive
## six deaths. See `_kill_feed_hazard`.
const KILL_FEED_SCRIPT := "res://scripts/ui/kill_feed.gd"

var _checks: int = 0
var _failures: int = 0
## Every phase `MatchState` announced, in order. Recorded from the signal rather
## than sampled per frame: the frame straight after a three-second island build
## carries a three-second delta, which is long enough for WARMUP to open and
## close between two of our own looks at it.
var _phases: Array[int] = []
## The summary `match_finished` carried, captured the way the results screen
## captures it.
var _summary: Dictionary = {}
## The last path `SceneFlow` finished a transition to.
##
## This is *not* the same thing as "the scene is in the tree", and the
## difference cost an afternoon. `SceneFlow.go_to` swaps the scene, then spends
## another 0.3 s fading back in, and refuses a second transition for the whole
## of that window. So a harness that notices the lobby the moment
## `current_scene` changes and immediately presses Start gets a
## `go_to_arena()` that returns without doing anything, and then waits two
## minutes for an arena that was never asked for. Waiting on `scene_ready` —
## which is emitted after the fade, with the busy flag already cleared — is
## waiting for the same moment a player would have pressed the button in.
var _scene_ready_path: String = ""
## Which map to play on. Taken from the command line rather than hard-coded so
## the shipping run and the static-map run are one file: two copies of this
## would drift, and the second copy is the one nobody would maintain.
var _map: String = MapCatalog.DEFAULT


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if MapCatalog.is_valid(arg):
			_map = arg
		else:
			# Loud rather than silently falling back to the island: a typo in a
			# smoke-test line would otherwise pass, having tested nothing it was
			# added to test.
			print("  FAIL  '%s' is not a map id; known ids are %s"
				% [arg, ", ".join(MapCatalog.ids())])
			_failures += 1
			_checks += 1
	print("playthrough: starting on map '%s'" % _map)
	# Cap the loop to the physics rate, exactly as `tools/snapshot.gd` does and
	# for a sharper version of the same reason (D-012).
	#
	# Headless has no vsync, so the loop free-runs at several thousand frames a
	# second, and a corpse does not survive that. Run `ragdoll_stability.tscn`
	# uncapped headless and it FAILs: bodies still moving at 71 m/s when they
	# should be at rest, having peaked at 119. Run the same scene with the rate
	# pinned and it settles at 0.06 m/s and passes. This harness kills fifteen
	# Bogs, so it would be building fifteen of those. Capping is not tidiness
	# here, it is the difference between simulating the game and simulating a
	# different game that happens to share its code.
	Engine.max_fps = int(ProjectSettings.get_setting(
		"physics/common/physics_ticks_per_second", 60))
	# Step out of the current-scene slot before anything calls
	# `change_scene_to_file`. `SceneTree` frees whatever is sitting in that slot
	# when the scene changes, and this harness has to outlive every screen it
	# drives — without this line the first transition, menu to lobby, deletes
	# the thing doing the driving and the run ends in silence rather than in a
	# failure. The node stays a child of `root` either way; only the pointer
	# that marks it as "the scene" is cleared.
	get_tree().current_scene = null

	SceneFlow.scene_ready.connect(func(path: String) -> void: _scene_ready_path = path)
	MatchState.phase_changed.connect(func(phase: int) -> void: _phases.append(phase))
	MatchState.match_finished.connect(func(summary: Dictionary) -> void:
		_summary = summary.duplicate(true), CONNECT_ONE_SHOT)

	# Each stage returns false when it could not reach the next one, and the run
	# stops there. Carrying on past a missing lobby would only produce a page of
	# consequential failures with the real one at the top.
	var ok := await _stage_menu()
	if ok:
		ok = await _stage_host()
	if ok:
		ok = await _stage_lobby()
	if ok:
		ok = await _stage_arena()
	if ok:
		ok = await _stage_warmup()
	# A practice map is a different end to the same walk (D-112). Everything up
	# to here is identical — menu, session, lobby, arena, warmup — and then
	# there is nothing to win and no results screen to open, so the kill loop
	# and the table it produces are replaced rather than added to. Running
	# `_stage_match` on the range would wait out `KILL_TIMEOUT` for a limit
	# `_check_win` has been told to ignore.
	# The feel round's combat, once and on the island only. Everything it
	# measures is about two Bogs standing on a floor and has nothing to do with
	# which floor, so running it on all six maps would be five copies of one
	# answer at five times the cost — and the default run is the one the gate
	# reads a `combat` verdict out of.
	if ok and _map == MapCatalog.DEFAULT:
		ok = await _stage_combat()
	if ok and MapCatalog.is_practice(_map):
		ok = await _stage_practice()
	else:
		if ok:
			ok = await _stage_match()
		if ok:
			ok = await _stage_results()

	print("playthrough: %d checks, %d failures" % [_checks, _failures])
	print("playthrough: %s" % ("PASS" if _failures == 0 else "FAIL"))
	await _teardown()
	get_tree().quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ stages ---

## The first screen anyone sees, loaded through the same `SceneFlow` call the
## game boots with rather than by hand, so the fade and the scene swap are the
## ones that ship.
func _stage_menu() -> bool:
	await SceneFlow.go_to_menu()
	if not _require("the menu is the current scene",
			_scene_path() == SceneFlow.MENU):
		return false
	# Not just "a scene loaded": the menu without its Host button is a menu
	# nobody can leave, and a renamed unique node would sail past a path check.
	var menu := get_tree().current_scene
	if not _require("the menu has a Host button",
			menu.get_node_or_null("%HostButton") is Button):
		return false
	print("playthrough: menu ok")
	return true


## Host. `Net.start_offline()` opens a real session with no socket — peer 1,
## `is_server()` true, every `is_host` branch and every `@rpc` downstream taking
## exactly the path it takes when hosting for real (D-011). The Host button
## itself calls `Net.host_lobby`, which binds a port; a test that opens a
## listening socket is a test that fails on a machine already running the game,
## and worse, one that raises a firewall prompt in CI.
##
## Everything after the session opening is the real button path: `start_offline`
## emits `joined_lobby`, the menu is listening, and the menu is what calls
## `SceneFlow.go_to_lobby()`. That handoff is one of the joins this file exists
## to watch, so it is deliberately not short-circuited here.
func _stage_host() -> bool:
	Net.start_offline()
	if not _require("the session is open", Net.in_session):
		return false
	_check("the local peer is the host", Net.is_host, true)
	_check("the local peer is 1", Net.local_id(), 1)

	# Stand-ins written straight into the roster, exactly as `ui_range` does.
	# `MatchState` spawns a Bog for each without ever asking whether there is a
	# client behind one, so these become remote Bogs to this peer.
	for i in FAKE_NAMES.size():
		Net.players[FAKE_BASE + i] = {
			"name": FAKE_NAMES[i], "team": 0, "ready": true,
		}
	Net.roster_changed.emit()

	# Match settings are pushed the way the lobby's settings panel pushes them,
	# rather than by poking `Net.config`: `update_config` is the host-side API,
	# it re-clamps everything on the way in, and using it means this harness
	# also proves that path still works.
	var settings := Net.config.duplicate_config()
	settings.warmup_time = WARMUP_TIME
	settings.spawn_protection = SPAWN_PROTECTION
	settings.respawn_delay = RESPAWN_DELAY
	# The map goes through the same host-side call as everything else, which
	# means it also goes through `_clamp_all` — so an id the catalog does not
	# know would come back as the island here rather than at the arena, and the
	# check below is what notices.
	settings.map = _map
	Net.update_config(settings)
	_check("warmup was shortened", Net.config.warmup_time, WARMUP_TIME)
	_check("the map survived the config", Net.config.map, _map)

	print("playthrough: session ok (offline host, peer 1, %d players, seed %d)" % [
		Net.player_count(), Net.config.map_seed])
	return true


## The lobby, arrived at by the menu's own `joined_lobby` handler.
func _stage_lobby() -> bool:
	if not await _await_until("the lobby scene", SCENE_TIMEOUT,
			func() -> bool: return _scene_ready_path == SceneFlow.LOBBY):
		return false
	if not _require("the lobby is the current scene",
			_scene_path() == SceneFlow.LOBBY):
		return false
	var lobby := get_tree().current_scene
	# The roster the lobby *drew*, not the one `Net` holds. Reading the label is
	# the only way to tell "the lobby is showing the five people who are here"
	# from "the lobby loaded and rendered an empty room", which is precisely the
	# failure D-015 was written about.
	var count_label := lobby.get_node_or_null("%PlayerCount") as Label
	if not _require("the lobby has its player count", count_label != null):
		return false
	_check("the lobby drew the whole roster", count_label.text,
		"%d / %d" % [Net.player_count(), Net.config.max_players])
	# Aborting rather than merely counting this one: `request_match_start`
	# silently does nothing when the gate is shut, and the next stage would then
	# spend two minutes waiting for an arena nobody asked for.
	if not _require("the host may start", Net.can_start_match()):
		return false

	# The map picker, read off the control for the same reason the roster is
	# read off the label. A map that is in `MapCatalog` and not in the lobby's
	# dropdown is a map only a config file can choose, and nothing else here
	# would notice — `arena.gd` reads the catalog directly and would build it
	# perfectly for a player who has no way to ask for it.
	var row := lobby.find_child("MapRow", true, false)
	if _require("the lobby has a map row", row != null):
		# A carousel of baked screenshots since D-162, so the two questions are
		# asked of the panel rather than of an `OptionButton`: `map_choices` is
		# read off the tiles a player can press and `map_showing` off the name
		# under the picture. Both are still the *drawn* answer, which is the
		# whole reason this check reads controls instead of `Net.config`.
		var panel := lobby.find_child("MatchSettings", true, false) as MatchSettingsPanel
		if _require("the map row has a picker", panel != null):
			var listed := panel.map_choices()
			_check("the picker lists every map in the catalog",
				", ".join(listed), ", ".join(MapCatalog.display_names()))
			_check("the picker is showing the map this match will build",
				panel.map_showing(),
				String(MapCatalog.get_entry(_map)["display_name"]))
			var thumb := row.find_child("MapThumb", true, false) as TextureRect
			_check("the carousel has a picture of this map",
				thumb != null and thumb.texture != null, true)
			print("playthrough: the lobby offers %s" % ", ".join(listed))

	# And the seed row, which is the one control whose *absence* is the feature:
	# a static map has no seed, and the lobby hides the row rather than greying
	# it out (D-030).
	var seed_row := lobby.find_child("MapSeedRow", true, false) as Control
	if seed_row != null:
		_check("the seed row is shown only for a generated map",
			seed_row.visible, MapCatalog.is_procedural(_map))

	print("playthrough: lobby ok (%d players, host can start)" % Net.player_count())
	return true


## Start the match and wait for the island. `request_match_start` emits
## `match_start_requested`; the lobby is listening and calls
## `SceneFlow.go_to_arena()`, which is the second join this file exists to watch.
func _stage_arena() -> bool:
	_scene_ready_path = ""
	var started := Time.get_ticks_msec()
	Net.request_match_start()
	if not _require("the match was accepted as started", Net.match_running):
		return false
	if not await _await_until("the arena scene",
			ARENA_TIMEOUT, func() -> bool: return get_tree().current_scene is Arena):
		return false
	var elapsed := Time.get_ticks_msec() - started

	var arena := get_tree().current_scene as Arena
	_check("the arena laid out its spawn ring", arena.spawn_points.size(),
		Arena.SPAWN_COUNT)
	# A spawn point at the origin is the shape `_solve_spawn` fails into, and
	# every Bog standing on the same pad is a spawn ring that never ran.
	var distinct := {}
	for spawn: Transform3D in arena.spawn_points:
		distinct[spawn.origin.snapped(Vector3.ONE * 0.01)] = true
	_check("the spawn pads are in different places", distinct.size(),
		arena.spawn_points.size())

	# Bogs are the proof that `register_arena` actually happened: nothing else
	# spawns them, and an arena that builds beautifully and never hands over is
	# a black screen with a nice island in it.
	_check("a Bog exists for every player", MatchState.bogs.size(),
		Net.player_count())
	for peer_id: int in Net.peer_ids():
		var bog: Bog = MatchState.bogs.get(peer_id)
		if not _require("peer %d has a Bog in the tree" % peer_id,
				is_instance_valid(bog) and bog.is_inside_tree()):
			return false

	# The arena instances the HUD itself, and every match before that wiring
	# existed ran with no crosshair, no score and no way to open the pause menu.
	if not _require("the arena instanced the HUD", _find_hud() != null):
		return false

	# The letter call across the top of the screen (D-093). Checked here rather
	# than in a preview scene for the reason this file exists at all: every
	# integration defect this project has had was something wired into a testbed
	# and into nothing else, and a banner that works in isolation and is absent
	# from the real HUD is exactly that shape. So: it is in the shipped scene,
	# and driving it puts a row on screen.
	var hud := _find_hud()
	var call_strip := hud.get_node_or_null("%LetterCall") as LetterCall
	if not _require("the HUD carries the letter call", call_strip != null):
		return false
	call_strip.picked_up("Pipwick", "B", Color.WHITE)
	_check("a pickup puts a line on screen", call_strip.get_child_count(), 1)
	call_strip.has_them_all("Pipwick", Color.WHITE)
	_check("and the full set adds another", call_strip.get_child_count(), 2)
	# Two is the cap, so a third call pushes the oldest off rather than stacking
	# down over the map.
	call_strip.picked_up("Mossfoot", "G", Color.WHITE)
	_check("a third call trims the oldest", call_strip.get_child_count(),
		LetterCall.MAX_ROWS)
	# A theft is the one event that takes a letter *off* a team (D-092), so it
	# names the robbed side rather than only the thief.
	call_strip.clear()
	call_strip.stolen("Thistle", "U", 1, Color.WHITE)
	var stolen_row := call_strip.get_child(0) as Label
	_check("a steal names the thief and the robbed team",
		stolen_row != null and stolen_row.text == "THISTLE STOLE A U FROM TEAM 2", true)
	call_strip.clear()
	_check("and the strip can be cleared", call_strip.get_child_count(), 0)

	# The steal bar (D-094), which is the other half of putting stealing on a
	# clock: the timer only buys the defender time if something tells them to
	# come. Driven through the HUD's own handler rather than the track's setter,
	# so what is proved is the *wiring* — that the signal reaches the widget —
	# and not merely that the widget has a method.
	var track := hud.get_node_or_null("%Letters") as LetterTrack
	if not _require("the HUD carries the letter track", track != null):
		return false
	var me := Net.local_id()
	hud._on_steal_progress(me, MatchState.LETTER_B, 1, 0.5)
	_check("a steal of mine draws a bar", track._steal_letter, MatchState.LETTER_B)
	_check("and reads as mine, not as a robbery", track._steal_defending, false)
	hud._on_steal_progress(me, 0, MatchConfig.TEAM_NONE, 0.0)
	_check("stepping off clears it", track._steal_letter, 0)
	# Somebody else robbing a team this player is not on draws nothing at all.
	hud._on_steal_progress(FAKE_BASE, MatchState.LETTER_G, 99, 0.5)
	_check("a robbery of a team I am not on is not my business",
		track._steal_letter, 0)

	if not _stage_map(arena):
		return false

	print("playthrough: arena built in %d ms, %d spawns, %d bogs" % [
		elapsed, arena.spawn_points.size(), MatchState.bogs.size()])
	return true


## Whichever of `arena.gd`'s two branches this map takes, taken properly.
##
## The generated branch and the static one produce the same handover and the
## rest of this file cannot tell them apart, which is the point — but each one
## has a way of half-working that the other does not. A procedural map with no
## `IslandGenerator` is a map with no height oracle; a static map that loaded
## and then quietly failed to build collision is a map every Bog falls through,
## and it looks exactly like a map that loaded fine until somebody walks on it.
func _stage_map(arena: Arena) -> bool:
	var entry := MapCatalog.get_entry(_map)
	if int(entry["kind"]) != MapCatalog.Kind.STATIC:
		_check("the island was generated", arena.island != null, true)
		_check("the island brought its own floor", MatchState.void_height,
			MatchState.VOID_HEIGHT)
		return true

	# Named `Map` by `arena.gd`, not by the .tscn — that renaming is the
	# contract, so it is what this looks for.
	var map := arena.get_node_or_null("Map") as StaticMap
	if not _require("the static map is in the tree as `Map`", map != null):
		return false
	# The scene brings its own lighting, and `arena.gd` must not have built the
	# island's night over the top of it (D-009, D-030).
	_check("the map brought an Environment",
		map.get_node_or_null("Environment") is WorldEnvironment, true)
	_check("the map brought a Sun",
		map.get_node_or_null("Sun") is DirectionalLight3D, true)
	_check("no moon was hung over a static map",
		arena.get_node_or_null("Moon"), null)
	_check("nothing generated ran", arena.island, null)

	# The floor, on the layer everything else looks for. This is the check that
	# would have caught a map that renders perfectly and cannot be stood on.
	var body := map.get_node_or_null("Collision") as StaticBody3D
	if not _require("the map built a collision body", body != null):
		return false
	_check("collision is on the world layer", body.collision_layer,
		StaticMap.LAYER_WORLD)
	# Not 1000, which is what this was until Twin Quarry. The number is here to
	# catch a map whose `.glb` did not import — a map that built a collision body
	# out of nothing — and a table-built map has no `.glb` to fail: the quarry is
	# 632 triangles of big stone slabs and is meant to be. `tools/preview_map.gd`
	# is where a per-map floor belongs, and it already takes one (`min_triangles=`).
	_check("the map has geometry in it", map.triangles > 300, true)
	_check("the map has collision shapes", body.get_child_count() > 0, true)
	_check("the match took the map's void height", MatchState.void_height,
		map.void_height)

	print("playthrough: static map '%s' — %d triangles, %d shapes, void at %.1f m" % [
		_map, map.triangles, map.shapes, map.void_height])
	return true


## Warmup, waited out rather than skipped, because the phase machine only ever
## reaches PLAYING through it.
func _stage_warmup() -> bool:
	var started := Time.get_ticks_msec()
	if not await _await_until("phase PLAYING", PHASE_TIMEOUT,
			func() -> bool: return MatchState.phase == MatchState.Phase.PLAYING):
		return false
	_check("the match warmed up before it played",
		_phases.has(MatchState.Phase.WARMUP), true)
	_check("WARMUP came before PLAYING",
		_phases.find(MatchState.Phase.WARMUP) < _phases.find(MatchState.Phase.PLAYING),
		true)

	# The floor holds. Warmup is the first stretch of the run in which anything
	# has had time to fall, and this is the *local* Bog deliberately: it is the
	# only one that simulates — the stand-ins are remote, so they run no gravity
	# and would sit happily in mid-air over a map with no collision in it at all.
	#
	# Worth its own check because the failure is silent. A map whose collision
	# never got built does not crash and does not print anything: every Bog
	# falls, passes the void height, is killed, respawns, falls again, and the
	# match plays out and reaches a results screen with the score looking
	# roughly right. On Rust the collision is built at load from world-space
	# triangles (D-031), which is a good deal more that can go wrong than
	# "the terrain mesh has a shape under it".
	#
	# **Settled on the floor, not on the floor at t=0.** `is_on_floor()` is a
	# fact about the last `move_and_slide`, and a Bog that has not had one yet
	# reports false however good the collision under it is: `revive_at` places
	# it a few centimetres clear of the pad and the first physics tick is what
	# drops it the rest of the way. Which tick this line lands on depends
	# entirely on how long the warmup was — Lantern Wharf's is 0.4 s and hid
	# this for four maps, and the practice range's is zero, so PLAYING arrives
	# on the same frame the Bogs were created and the assertion was reading a
	# body mid-spawn. Nothing about the map was wrong; the question was asked
	# too early.
	var mine: Bog = MatchState.bogs.get(Net.local_id())
	var settled := -1
	if _require("the local Bog is in the world", is_instance_valid(mine)):
		settled = await _settle_on_floor(mine)
		_check("the local Bog is standing on the map", mine.is_on_floor(), true)
		_check("the local Bog has not fallen through it",
			mine.global_position.y > MatchState.void_height + 1.0, true)

	print("playthrough: phase PLAYING after %.1f s, local Bog on the floor at %.2f m after %d tick(s)" % [
		float(Time.get_ticks_msec() - started) * 0.001,
		mine.global_position.y if is_instance_valid(mine) else NAN, settled])
	_check_capture_layout()
	return true


## Give a freshly spawned Bog the physics ticks it needs to land, and return how
## many it took. Bounded, so a map with no collision under the pads still fails
## rather than hanging.
##
## **Physics ticks, not wall clock**, and that is the whole point of it not
## being an `_await_until`. Every other wait in this file is a deadline in
## seconds, which is right for "has the island finished building" — a question
## about a blocking main thread. This one is about how many times the body has
## been simulated, and a wall clock answers that only on an idle machine. The
## gate runs six playthroughs and a dozen Godot processes, sometimes beside
## another agent's, and a second of real time can be two ticks or two hundred.
## Counting the thing the question is actually about makes the check immune to
## load.
##
## Thirty ticks is half a second of simulation — twenty times the one or two a
## spawn pad actually needs, and still nothing next to the timeouts around it.
## A Bog that has not found the floor by then is not slow, it is falling, and
## the assertion that follows says so.
func _settle_on_floor(bog: Bog) -> int:
	for tick in SETTLE_TICKS:
		if not is_instance_valid(bog) or bog.is_on_floor():
			return tick
		await get_tree().physics_frame
	return SETTLE_TICKS


## Capture B·O·G's bases and letters on this map, as the match would place them
## (D-051). Checked on every map in every playthrough whatever the win
## condition, because the layout is planned for every arena and the physics has
## stepped by now: two bases for two teams, on distinct pads well apart, each
## with pads of its own to spawn on, and three letter points that are on a real
## floor with a Bog's head room, outside both bases and apart from each other.
## Lantern Wharf declares its own bases and letters (D-056) and every other map
## is on the fallback, so this is both checks: that the fallback is playable on
## every map it can be picked on, and that a declared layout is sound.
func _check_capture_layout() -> void:
	var failures_before := _failures
	var layout := MatchState.capture_layout()
	if not _require("the arena planned a capture layout", layout != null):
		return
	var arena := get_tree().current_scene as Arena
	var space := arena.get_world_3d().direct_space_state
	_check("capture: one base per team", layout.bases.size(), Net.config.team_count)
	if layout.bases.size() < 2:
		return
	var apart := Vector2(layout.bases[0].x, layout.bases[0].z).distance_to(
		Vector2(layout.bases[1].x, layout.bases[1].z))
	_check("capture: the bases are well apart (%.1f m)" % apart,
		apart > layout.base_radius * 4.0, true)
	for team in layout.bases.size():
		_check("capture: team %d has pads to spawn on" % (team + 1),
			layout.pad_team.has(team), true)
		_check("capture: team %d's base stands on a floor" % (team + 1),
			_floor_under(space, layout.bases[team]), true)
	var letters := layout.settle_letters(space)
	_check("capture: three letter points", letters.size(), 3)
	for i in letters.size():
		var point := letters[i]
		var glyph := MatchState.letter_name(MatchState.LETTERS[i])
		_check("capture: %s is on a floor" % glyph, _floor_under(space, point), true)
		_check("capture: a Bog fits where %s is" % glyph,
			CaptureLayout.has_headroom(space, point), true)
		for team in layout.bases.size():
			_check("capture: %s is outside team %d's base" % [glyph, team + 1],
				layout.in_base(team, point), false)
		for j in range(i + 1, letters.size()):
			_check("capture: %s and %s are apart" % [glyph,
				MatchState.letter_name(MatchState.LETTERS[j])],
				point.distance_to(letters[j]) > 3.0, true)
	# Declared or fallback, said in the line, so the gate can tell a map that
	# states its own objectives (D-056) from one the fallback is standing in for.
	print("playthrough: capture layout on '%s' — %s bases %s, %s letters %s" % [_map,
		"declared" if layout.bases_declared else "fallback",
		", ".join(layout.bases.map(func(v: Vector3) -> String: return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z])),
		"declared" if layout.letters_declared else "fallback",
		", ".join(letters.map(func(v: Vector3) -> String: return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]))])
	if _failures == failures_before:
		print("playthrough: capture layout PASS")


func _floor_under(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6)
	ray.collision_mask = 1
	return not space.intersect_ray(ray).is_empty()


## The feel round's combat: fists, the emote and the sword chain, in the real
## arena with two real Bogs on a real floor.
##
## It is a stage of `playthrough` rather than a mode of `combat_range` for the
## reason `_stage_practice` is one: every claim here is about two bodies, the
## host's geometry and `MatchState.report_damage` acting together, and the
## honest place to make it is the arena the game actually builds. It is also the
## cheapest place — everything it needs is already standing up by the time the
## warmup ends.
##
## The victim is one of the stand-in players, moved rather than spawned: a fake
## peer's Bog is not simulated on this machine (nobody owns it), so it holds
## exactly where it is put and every distance below is the distance that was
## asked for.
func _stage_combat() -> bool:
	var failures_before := _failures
	var mine: Bog = MatchState.bogs.get(Net.local_id())
	var other: Bog = MatchState.bogs.get(FAKE_BASE)
	if not _require("combat: both Bogs are in the world",
			is_instance_valid(mine) and is_instance_valid(other)):
		return false
	var combat := mine.get_node_or_null("Combat") as BogCombat
	if not _require("combat: the local Bog has a Combat node", combat != null):
		return false
	# Every hit the host decides, in order, as [amount, cause]. One listener for
	# the whole stage: what each attack is worth is the only thing being
	# measured and `hit_landed` is the one door all of it comes through.
	var hits: Array = []
	MatchState.hit_landed.connect(func(_attacker: int, _victim: int, amount: float,
		cause: int, _point: Vector3, _bone: String) -> void:
			hits.append([amount, cause]))

	# ------------------------------------------------------ hands out (H) ---
	mine.weapon = Loadout.Weapon.SPEAR
	combat.refresh_hand()
	mine.sync_holstered = false
	var armed_speed := mine.target_speed()
	_check("combat: an armed Bog has its spear", combat.has_spear(), true)
	combat.toggle_holster()
	_check("combat: H puts the weapon away", combat.is_holstered(), true)
	_check("combat: a holstered Bog has no spear", combat.has_spear(), false)
	_check("combat: a holstered Bog has no bow", combat.has_bow(), false)
	_check("combat: a holstered Bog has no sword", combat.has_sword(), false)
	var fists_speed := mine.target_speed()
	# The number, not the flag: 1.10 exactly, out of `target_speed` itself, so a
	# scale applied somewhere other than the one place every stance comes out of
	# would fail here rather than be discovered in a match.
	_check("combat: a holstered Bog walks %.2fx as fast (%.3f / %.3f)"
		% [Bog.FISTS_SPEED_SCALE, fists_speed, armed_speed],
		is_equal_approx(fists_speed, armed_speed * Bog.FISTS_SPEED_SCALE), true)
	await get_tree().process_frame
	_check("combat: a holstered Bog's fists are empty",
		mine.held_gear.is_carried(), false)
	_verdict("fists", failures_before,
		"hands out: %.2f m/s against %.2f armed, both fists empty, no weapon gate open"
			% [fists_speed, armed_speed])

	# ---------------------------------------------------------- the punch ---
	var punch_mark := _failures
	# In front, inside the reach and well inside the arc — and the *view* put on
	# the body first, because a punch squares the body to the crosshair as it
	# starts (D-178). This Bog has been stood up and turned by hand and its rig
	# is still looking wherever the lobby left it, so a dummy placed off
	# `facing()` alone is a dummy the fist would turn away from before it
	# landed. One frame for the basis to cross from `_process` into the Bog.
	var rig := mine.get_node_or_null("CameraRig") as BogCamera
	if rig != null:
		rig.set_view(mine.body_yaw, 0.0)
		await get_tree().process_frame
	var forward := mine.facing()
	_place(other, mine.global_position + forward * 1.1, mine.body_yaw + PI)
	other.set_health(Bog.MAX_HEALTH)
	hits.clear()
	combat.try_punch()
	if not await _await_until("the punch to land", PHASE_TIMEOUT,
			func() -> bool: return not hits.is_empty()):
		return false
	_check("combat: a punch deals %d" % int(BogCombat.PUNCH_DAMAGE),
		hits[0][0], BogCombat.PUNCH_DAMAGE)
	_check("combat: a punch is its own cause", hits[0][1], int(Bog.Cause.FIST))
	_check("combat: the punched Bog took it",
		other.health, Bog.MAX_HEALTH - BogCombat.PUNCH_DAMAGE)
	# The range's stats panel counts weapons, and a fist is not one.
	_check("combat: the range counts nothing for a fist",
		RangeStats.weapon_for(Bog.Cause.FIST), "")

	# The same distance, the other way round the compass. `PUNCH_ARC` is 50
	# degrees either side, so a Bog standing behind the puncher is inside the
	# reach and outside the punch — which is the whole of "a punch can miss".
	_place(other, mine.global_position - forward * 1.1, mine.body_yaw)
	var before_behind := other.health
	hits.clear()
	await _await_until("the punch to recharge", PHASE_TIMEOUT,
		func() -> bool: return combat.punch_cooldown() <= 0.0)
	combat.try_punch()
	await _await_frames(30)
	_check("combat: a punch behind you hits nobody", hits.size(), 0)
	_check("combat: and takes nothing off them", other.health, before_behind)
	_verdict("punch", punch_mark,
		"a punch took %d at %.1f m inside %d degrees and nothing at the same range behind"
			% [int(BogCombat.PUNCH_DAMAGE), BogCombat.PUNCH_REACH,
				int(BogCombat.PUNCH_ARC)])

	# --------------------------------------------- the emote empties both ---
	var emote_mark := _failures
	combat.toggle_holster()
	_check("combat: H puts the weapon back", combat.is_holstered(), false)
	await get_tree().process_frame
	_check("combat: and the spear is back in the fist",
		mine.held_gear.is_carried(), true)
	combat.toggle_emote()
	_check("combat: Y starts the dance", combat.is_emoting(), true)
	await get_tree().process_frame
	_check("combat: a dancing Bog's hands are empty",
		mine.held_gear.is_carried(), false)
	combat.toggle_emote()
	_check("combat: Y ends it", combat.is_emoting(), false)
	await get_tree().process_frame
	_check("combat: and the spear comes back", mine.held_gear.is_carried(), true)

	# ------------------------------------ the holster is refused mid-draw ---
	mine.weapon = Loadout.Weapon.BOW
	combat.refresh_hand()
	combat.try_draw_bow()
	# A frame, because `is_drawing()` answers off the field `_tick_draw` puts on
	# the body and the point of asking it that way is that a remote Bog gets the
	# same answer (D-065).
	await get_tree().process_frame
	_check("combat: the bow is drawing", mine.is_drawing(), true)
	combat.toggle_holster()
	_check("combat: a drawing Bog may not put its bow away",
		combat.is_holstered(), false)
	combat.clear_weapon_state()
	combat.refresh_hand()
	_verdict("emote", emote_mark,
		"the dancer's hands empty and fill again, and a drawing Bog is refused the holster")

	# ----------------------------------------------------- the slash chain ---
	var sword_mark := _failures
	mine.weapon = Loadout.Weapon.SWORD
	combat.refresh_hand()
	_place(other, mine.global_position + forward * 1.5, mine.body_yaw + PI)
	other.set_health(Bog.MAX_HEALTH)
	mine.velocity = Vector3.ZERO
	hits.clear()
	var launches: Array[String] = []
	combat.weapon_launched.connect(func(weapon: String) -> void:
		launches.append(weapon))

	_check("combat: a standing sword Bog may attack", combat.has_sword(), true)
	combat.try_sword_attack()
	_check("combat: a standing click does not spin", mine.is_spinning(), false)
	_check("combat: it slashes", combat.is_slashing(), true)
	if not await _await_until("the first slash to connect", PHASE_TIMEOUT,
			func() -> bool: return not hits.is_empty()):
		return false
	_check("combat: a slash deals %d" % int(BogCombat.SLASH_DAMAGE),
		hits[0][0], BogCombat.SLASH_DAMAGE)
	_check("combat: the slashed Bog is still alive",
		MatchState.is_alive(other.peer_id), true)
	# The second click, the moment the first blade has passed — which is the
	# window the chain is actually taken in, and asking for it by the state
	# rather than by a frame count is what keeps this from being a timing race.
	_check("combat: the great sword is still in the fists between slashes",
		mine.held_gear.has_sword(), true)
	combat.try_sword_attack()
	_check("combat: the second click chains", combat.is_slashing(), true)
	if not await _await_until("the second slash to connect", PHASE_TIMEOUT,
			func() -> bool: return hits.size() >= 2):
		return false
	_check("combat: the second slash deals %d too" % int(BogCombat.SLASH_DAMAGE),
		hits[1][0], BogCombat.SLASH_DAMAGE)
	_check("combat: two slashes kill", MatchState.is_alive(other.peer_id), false)
	# And a third, with nobody in front of it: what is being counted is the
	# chain's arithmetic, so the victim is deliberately out of the picture.
	launches.clear()
	combat.try_sword_attack()
	_check("combat: the third click chains", combat.is_slashing(), true)
	if not await _await_until("the third slash to be accepted", PHASE_TIMEOUT,
			func() -> bool: return launches.size() >= 1):
		return false
	# And a fourth, which `SLASH_MAX` refuses. Proved by what the chain *did*
	# rather than by a flag read on the click: the third slash's blade is still
	# out on this tick, so "is it slashing" cannot tell a refused fourth from
	# the third still running. A slash that was accepted would land and emit,
	# so counting the launches to the far side of the chain is the one reading
	# that separates them.
	combat.try_sword_attack()
	if not await _await_until("the chain to close", PHASE_TIMEOUT,
			func() -> bool: return not combat.in_chain()):
		return false
	_check("combat: a fourth click is refused — three slashes and no more",
		launches.size(), 1)
	_check("combat: the chain spends the recharge",
		combat.sword_cooldown() > 0.0, true)

	# ----------------------------------------------------- the sprint spin ---
	# The same button at speed. The velocity is written rather than run up to,
	# because what is being measured is the *gate* — `ground_speed()` read at
	# the click — and a run-up across an island is a test of the island.
	await _await_until("the sword to come back", PHASE_TIMEOUT,
		func() -> bool: return combat.has_sword())
	var revived: Bog = MatchState.bogs.get(FAKE_BASE)
	revived.set_health(Bog.MAX_HEALTH)
	hits.clear()
	mine.velocity = forward * Bog.RUN_SPEED
	combat.try_sword_attack()
	_check("combat: a click at sprint speed spins", mine.is_spinning(), true)
	# The spin is aimed by the blade, not by the body (D-068): `SwordSpin`
	# turns the skeleton through a revolution, and at the `hit` marker the
	# blade is read off the bone attachment, roughly a hundred degrees off the
	# body's own facing (`combat_range -- sword` rehearses a swing at nobody to
	# find out where). The body is also travelling, across whatever the island
	# puts in the way. So the victim is stood one metre down the blade's own
	# direction on every physics tick until the release — the same reading
	# `_blade_direction` makes, taken off `held_gear.sword_blade()` — inside
	# the reach, outside the two capsules touching, and at the attacker's own
	# height so the sight line is the sight line and not the terrain's. What is
	# being measured is the gate and the damage, not the lane.
	var spin_deadline := Time.get_ticks_msec() + int(PHASE_TIMEOUT * 1000.0)
	while hits.is_empty() and Time.get_ticks_msec() < spin_deadline:
		var blade := forward
		if mine.held_gear != null:
			var tip: Vector3 = mine.held_gear.sword_blade()[0]
			var flat := Vector3(tip.x - mine.global_position.x, 0.0,
				tip.z - mine.global_position.z)
			if flat.length_squared() > 0.0001:
				blade = flat.normalized()
		_place(revived, mine.global_position + blade * 1.0,
			Bog.yaw_towards(-blade))
		await get_tree().physics_frame
	_checks += 1
	if hits.is_empty():
		_failures += 1
		print("  FAIL  timed out after %.0f s waiting for the spin to connect"
			% PHASE_TIMEOUT)
		return false
	_check("combat: the spin still kills outright",
		hits[0][0], BogCombat.SWORD_DAMAGE)
	_verdict("sword", sword_mark,
		("%d + %d killed at %.2f m reach, three slashes chained and a fourth was"
			+ " refused, and a click at %.1f m/s spun for %d")
			% [int(BogCombat.SLASH_DAMAGE), int(BogCombat.SLASH_DAMAGE),
				combat.slash_reach(), Bog.RUN_SPEED, int(BogCombat.SWORD_DAMAGE)])

	if _failures == failures_before:
		print("playthrough: combat PASS")
	return true


## One line per part of the combat stage, with the numbers it actually measured
## in it, and a PASS the gate can name. Four verdicts out of one stage for the
## reason `combat_range`'s modes print four out of one run: they fail for
## different reasons and a single line would say which one only by omission.
func _verdict(part: String, failures_before: int, measured: String) -> void:
	print("playthrough: %s — combat %s %s" % [measured, part,
		"PASS" if _failures == failures_before else "FAIL"])


## Stand a Bog somewhere, facing a way, without it being a respawn: the
## transform and the two replicated fields that publish it, which is what
## `RangeDummies.drive_to` does for the same reason.
func _place(body: Bog, spot: Vector3, yaw: float) -> void:
	body.global_position = spot
	body.body_yaw = yaw
	body.sync_position = spot
	body.sync_yaw = yaw
	body.velocity = Vector3.ZERO
	body.sync_velocity = Vector3.ZERO
	body.sync_grounded = true


func _await_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


## The practice range, in place of a match and a results screen (D-112).
##
## Everything unit 1 of the range built, walked once in the real arena: the
## rules a practice map turns off, a dummy spawned, driven, hit, killed and
## brought back to its station, the roster filter that keeps it off every screen
## derived from the roster, and a map-placed pickup claimed.
##
## It is a stage of `playthrough` rather than a harness of its own because every
## one of those things is a claim about the *game* — `MatchState`, `Net` and the
## arena together — and the only honest place to make it is the arena the game
## actually builds, after the same menu, session and lobby every other map goes
## through.
func _stage_practice() -> bool:
	var failures_before := _failures

	# ---------------------------------------------- the rules practice ends ---
	_check("practice: the map says it is practice", Net.config.is_practice(), true)
	_check("practice: there is no clock", Net.config.effective_time_limit(), 0)
	_check("practice: the clock is not running", MatchState.time_left, 0.0)
	_check("practice: there is no spawn protection",
		Net.config.effective_spawn_protection(), 0.0)
	_check("practice: the respawn is a second",
		Net.config.effective_respawn_delay(), MatchConfig.PRACTICE_RESPAWN)
	# The dials themselves are untouched — read past, not overwritten — so the
	# host's lobby settings survive a trip to the range (the whole argument for
	# `effective_*` existing rather than a mutation).
	_check("practice: the host's own time limit was not overwritten",
		Net.config.time_limit > 0, true)

	# ------------------------------------------------------------ the map ---
	var arena := get_tree().current_scene as Arena
	var map := arena.get_node_or_null("Map") as StaticMap
	if not _require("practice: the range is in the tree as `Map`", map != null):
		return false
	var dummies := map.get_node_or_null("Dummies") as RangeDummies
	if not _require("practice: the range brought a RangeDummies node",
			dummies != null):
		return false
	_check("practice: the range's dummies are reachable as the singleton",
		RangeDummies.instance == dummies, true)
	print("playthrough: the range brought a RangeDummies node")

	# ---------------------------------------------------------- a dummy ---
	# Somewhere on the slab, clear of the pads, facing back down the range.
	var station := Transform3D(Basis(Vector3.UP, PI), Vector3(4.0, 0.12, -12.0))
	# The ordinal this spawn will wear, read *before* it happens. The map itself
	# now stands twenty-three dummies on its own marks the moment the director
	# lands, so this one is "Dummy 24" on Highsun Grounds and "Dummy 1" on a
	# bare fixture; what is being asserted is that the registry numbers them in
	# order, not that this test got there first.
	var ordinal := dummies.ids().size() + 1
	var id := dummies.spawn(station, "stand")
	if not _require("practice: spawning a dummy returned an id", id >= Net.BOT_BASE):
		return false
	if not await _await_until("the dummy's body", SCENE_TIMEOUT,
			func() -> bool: return MatchState.bogs.has(id)):
		return false
	var dummy: Bog = MatchState.bogs[id]
	_check("practice: the dummy stands at its station",
		dummy.global_position.distance_to(station.origin) < 0.5, true)
	_check("practice: the dummy is named", Net.player_name(id), "Dummy %d" % ordinal)

	# **The authority claim, asserted rather than assumed.** This is the one
	# thing in the unit that could be quietly wrong and still look right on the
	# host's own screen: the host would see a dummy move and nobody else would.
	var sync := dummy.get_node_or_null("Sync")
	if _require("practice: the dummy has a Sync node", sync != null):
		_check("practice: the dummy's transform is published by the host",
			sync.get_multiplayer_authority(), 1)
	_check("practice: the dummy's body still belongs to nobody real",
		dummy.get_multiplayer_authority(), id)
	_check("practice: the dummy reads no keyboard", dummy.reads_local_input, false)

	# It moves, and it says so on the wire. `drive_to` is the one writer every
	# brain in unit 3 goes through, so proving it here is proving all of them.
	var moved := station.origin + Vector3(0.0, 0.0, 3.0)
	dummies.drive_to(dummy, moved, 0.0, Vector3(0.0, 0.0, 6.0), true)
	_check("practice: driving the dummy moved its body",
		dummy.global_position.distance_to(moved) < 0.01, true)
	_check("practice: driving the dummy moved what replicates",
		dummy.sync_position.distance_to(moved) < 0.01, true)
	_check("practice: a driven dummy is on the ground", dummy.sync_grounded, true)

	# ------------------------------------------------------ the filters ---
	_check("practice: the roster has the dummy", Net.players.has(id), true)
	_check("practice: the dummy is a dummy", Net.is_dummy(id), true)
	_check("practice: the dummy is not a person", Net.human_ids().has(id), false)
	_check("practice: the dummy is not counted as a player",
		Net.player_count(), Net.human_ids().size())
	_check("practice: the dummy is not in the ranking",
		MatchState.ranking().has(id), false)
	_check("practice: the local player still is",
		MatchState.ranking().has(Net.local_id()), true)
	print("playthrough: dummies are hidden from every roster screen")

	# ------------------------------------------------- hit, die, come back ---
	var hits: Array = []
	MatchState.hit_landed.connect(func(attacker: int, victim: int, amount: float,
		cause: int, _point: Vector3, _bone: String) -> void:
			hits.append([attacker, victim, amount, cause]))
	var before := dummy.health
	MatchState.report_damage(id, Net.local_id(), 40.0, Bog.Cause.SPEAR,
		dummy.global_position, Vector3.FORWARD, "")
	_check("practice: hit_landed fired once", hits.size(), 1)
	if hits.size() == 1:
		_check("practice: hit_landed named the attacker", hits[0][0], Net.local_id())
		_check("practice: hit_landed named the victim", hits[0][1], id)
		_check("practice: hit_landed carried the damage dealt", hits[0][2], 40.0)
	_check("practice: the dummy took the hit", dummy.health, before - 40.0)

	# ------------------------------------------- every weapon draws a mark ---
	# The hitmarker is drawn by one handler off one signal, and the four weapons
	# reach it by one road: `bog_combat` and `spear_projectile` each end their
	# impact in `MatchState.report_damage`, which is the only thing that emits
	# `hit_landed`. So what is worth asserting is that the road is open for each
	# `Cause` and that the HUD's own handler paints when it arrives — not that
	# four impacts can be staged, which would be a test of four hit tests.
	#
	# The crosshair is asked whether it is *processing*, because `strike` is what
	# turns its per-frame fade back on: switch it off, report the hit, and a
	# crosshair that is running again has been struck within that call. Each of
	# the four is knocked back off first, so the second weapon cannot pass on
	# the first one's mark.
	var hud := _find_hud()
	var crosshair: Crosshair = null
	if hud != null:
		crosshair = hud.get_node_or_null("%Crosshair") as Crosshair
	if _require("practice: the HUD is up with a crosshair in it", crosshair != null):
		for weapon: Array in [
			["a spear", Bog.Cause.SPEAR], ["an arrow", Bog.Cause.ARROW],
			["a sword swing", Bog.Cause.SWORD], ["a lightning strike", Bog.Cause.LIGHTNING],
		]:
			var what := String(weapon[0])
			var cause: Bog.Cause = weapon[1]
			hits.clear()
			crosshair.set_process(false)
			MatchState.report_damage(id, Net.local_id(), 5.0, cause,
				dummy.global_position, Vector3.FORWARD, "")
			_check("practice: %s reports one landed hit" % what, hits.size(), 1)
			if hits.size() == 1:
				_check("practice: %s names the attacker" % what,
					hits[0][0], Net.local_id())
				_check("practice: %s carries its own cause" % what, hits[0][3], cause)
			_check("practice: %s marks the crosshair" % what,
				crosshair.is_processing(), true)
		print("playthrough: spear, arrow, sword and lightning each flash the mark")

	# And the overkill: a body's worth into what is left reports what was left,
	# not the hundred that was asked for. The number a range counts.
	hits.clear()
	var remaining := dummy.health
	MatchState.report_kill(id, Net.local_id(), Bog.Cause.SPEAR,
		dummy.global_position, Vector3.FORWARD, "")
	_check("practice: the killing hit was announced too", hits.size(), 1)
	if hits.size() == 1:
		_check("practice: a killing hit reports what it actually took",
			hits[0][2], remaining)
	_check("practice: the dummy died", MatchState.is_alive(id), false)

	# Back at its station — not on a spawn pad, which is what an anchor is for.
	if not await _await_until("the dummy to come back", PHASE_TIMEOUT,
			func() -> bool: return MatchState.is_alive(id)):
		return false
	var home: Bog = MatchState.bogs[id]
	_check("practice: the dummy respawned at its station",
		home.global_position.distance_to(station.origin) < 0.5, true)
	var nearest_pad := INF
	for pad: Transform3D in MatchState.capture_layout().bases.map(
			func(v: Vector3) -> Transform3D: return Transform3D(Basis.IDENTITY, v)):
		nearest_pad = minf(nearest_pad, pad.origin.distance_to(home.global_position))
	_check("practice: and not at a base", nearest_pad > 5.0, true)
	# Nothing was won by any of that.
	_check("practice: killing a dummy ended nothing",
		MatchState.phase, MatchState.Phase.PLAYING)

	# ------------------------------------------------------ a placed item ---
	var mine: Bog = MatchState.bogs.get(Net.local_id())
	if not _require("practice: the local Bog is in the world",
			is_instance_valid(mine)):
		return false
	var spot := mine.global_position
	var taken: Array = []
	MatchState.pickup_taken.connect(func(pid: int, kind: int, by: int) -> void:
		taken.append([pid, kind, by]))
	var item := MatchState.place_pickup(Pickup.Kind.SHIELD, spot, true)
	_check("practice: placing a pickup returned an id", item > 0, true)
	# Straight through the host's own door, exactly as the overlap does: the
	# Bog is standing on it, and `claim_pickup` is the one place a drop is
	# awarded whether the trigger was an Area3D or a well's own bookkeeping.
	MatchState.claim_pickup(item, Net.local_id())
	_check("practice: the placed pickup was claimed", taken.size(), 1)
	if taken.size() == 1:
		_check("practice: pickup_taken named the item", taken[0][0], item)
		_check("practice: pickup_taken named the kind", taken[0][1],
			int(Pickup.Kind.SHIELD))
		_check("practice: pickup_taken named the collector", taken[0][2],
			Net.local_id())
	print("playthrough: a placed pickup was claimed")

	if _failures == failures_before:
		print("playthrough: practice PASS")
	return true


## Play the match out. Kills go through `MatchState.report_kill`, which is
## host-only and is the single place a death is decided — the same call the
## spear makes when it lands, and the same one `match_rules` drives.
##
## One kill per frame, with the frame in between doing the work: the host's
## `_process` runs `_tick_respawns`, which is what brings the victim back. So
## this is not a bare scoring loop — every swing is a whole death-and-respawn
## cycle through `_apply_death`, `BogRagdoll.spawn_from` and `_do_respawn`, and
## the match takes the kill limit's worth of them to end.
func _stage_match() -> bool:
	var killer := FAKE_BASE
	# The local player is in the rotation on purpose: dying is the only way to
	# reach `local_death`, and with it the HUD's respawn banner.
	var victims: Array[int] = [1, FAKE_BASE + 1, FAKE_BASE + 2, FAKE_BASE + 3]
	var limit := Net.config.kill_limit
	var respawned := 0
	var swing := 0
	var deaths := 0
	# Room for a refused kill or two without letting a stuck loop run forever.
	var max_swings := limit * 4 + 40
	var deadline := Time.get_ticks_msec() + int(KILL_TIMEOUT * 1000.0)
	# How many deaths this build can be asked for before the HUD wedges. Normally
	# there is no such number.
	var hazard := _kill_feed_hazard()
	var budget := KillFeed.MAX_ROWS if not hazard.is_empty() else max_swings

	while MatchState.phase == MatchState.Phase.PLAYING and swing < max_swings:
		if Time.get_ticks_msec() > deadline or deaths >= budget:
			break
		var victim: int = victims[swing % victims.size()]
		swing += 1
		if not MatchState.is_alive(victim):
			await get_tree().process_frame
			continue
		var bog: Bog = MatchState.bogs.get(victim)
		var point := bog.global_position if is_instance_valid(bog) else Vector3.ZERO
		# A blow with real speed in it, not a unit vector: the corpse's flight is
		# scaled by it, so a zero-length one would leave the ragdoll path
		# exercised but never actually pushed.
		MatchState.report_kill(victim, killer, Bog.Cause.SPEAR,
			point, Vector3.FORWARD * 18.0, "mixamorig_Spine1")
		deaths += 1
		await get_tree().process_frame
		if MatchState.is_alive(victim):
			respawned += 1

	if deaths >= budget and not hazard.is_empty():
		_checks += 1
		_failures += 1
		print("  FAIL  %s" % hazard)
		print("playthrough: stopped after %d deaths; %d kills scored, %d respawns" % [
			deaths, MatchState.kills(killer), respawned])
		return false

	_check("the killer reached the limit", MatchState.kills(killer), limit)
	_check("the dead came back", respawned > 0, true)
	if not _require("the match ended",
			MatchState.phase == MatchState.Phase.POST_MATCH):
		return false
	if not _require("match_finished carried a summary", not _summary.is_empty()):
		return false
	_check("the reason", _summary.get("reason"), "limit")
	var ranking: Array = _summary.get("ranking", [])
	if not _require("the summary has a ranking", not ranking.is_empty()):
		return false
	_check("the winner leads the ranking", int(ranking[0]), killer)
	_check("everyone is in the ranking", ranking.size(), Net.player_count())
	# A kill after the whistle must not count, here as in `match_rules` — this
	# is the one place it can be checked with a real Bog on the far end.
	MatchState.report_kill(victims[0], killer, Bog.Cause.SPEAR,
		Vector3.ZERO, Vector3.FORWARD, "mixamorig_Spine1")
	_check("no scoring after the match ends", MatchState.kills(killer), limit)

	print("playthrough: match finished — reason \"%s\", winner %s" % [
		_summary.get("reason", "?"), Net.player_name(int(ranking[0]))])
	return true


## The results screen. It is not a scene change — `hud.gd` instances
## `results_screen.tscn` as part of itself and reveals it from
## `_on_match_finished` — so this is a search of the live arena tree rather than
## a path check.
func _stage_results() -> bool:
	var hud := _find_hud()
	if not _require("the HUD is still in the tree", hud != null):
		return false
	var results := _find_first(hud, func(node: Node) -> bool: return node is ResultsScreen)
	if not _require("the HUD carries a results screen", results != null):
		return false
	var screen := results as ResultsScreen
	if not await _await_until("the results screen to open", SCENE_TIMEOUT,
			func() -> bool: return screen.visible):
		return false

	# One row per player, filled from the summary rather than from live state.
	var rows := screen.get_node_or_null("%Rows") as Container
	if not _require("the results screen has a table", rows != null):
		return false
	_check("a row per player", rows.get_child_count(),
		(_summary.get("ranking", []) as Array).size())

	var headline := screen.get_node_or_null("%Headline") as Label
	if not _require("the results screen has a headline", headline != null):
		return false
	var winner := Net.player_name(int((_summary.get("ranking", []) as Array)[0]))
	_check("the headline names the winner", headline.text.contains(winner), true)
	_check("the headline explains why it ended",
		(screen.get_node_or_null("%Subtitle") as Label).text,
		"The kill limit was reached.")

	# The gameplay HUD gets out of the way rather than sitting behind the table.
	var hud_root := hud.get_node_or_null("Root") as Control
	_check("the gameplay HUD stood down", hud_root != null and not hud_root.visible,
		true)

	print("playthrough: results ok (%d rows, headline \"%s\")" % [
		rows.get_child_count(), headline.text])
	return true


# ------------------------------------------------------------------ hazard ---

## Empty if this build can be asked for more deaths than the kill feed holds
## rows; otherwise the reason it cannot, ready to print.
##
## `KillFeed.add_kill` evicts its oldest row like this:
##
##     while get_child_count() > MAX_ROWS:
##         get_child(get_child_count() - 1).queue_free()
##
## `queue_free` does not remove the child. It schedules the deletion for the end
## of the frame, and the frame never ends, because the loop's condition is
## unchanged by it. So the *sixth* death in any match — MAX_ROWS is five — never
## returns from `report_kill`: the process pins a core at 100% and commits
## memory until something kills it. This harness found it on its first complete
## run, at exactly the sixth kill, having spent an afternoon looking for the
## fault in the ragdoll and the physics broadphase first, because the symptom is
## a hang and a runaway allocation rather than an error.
##
## The check has to be made against the *source*, which is not a thing a test
## should ever be pleased about. There is no alternative here: nothing can
## survive making that call, and from outside a fixed feed and a broken one are
## identical right up until the fatal row arrives. Rewriting the eviction so it
## removes the child before freeing it — two more lines — makes this return
## empty and the run carries straight on to the kill limit.
##
## Delete this function and its caller along with the bug.
func _kill_feed_hazard() -> String:
	var source := FileAccess.get_file_as_string(KILL_FEED_SCRIPT)
	if source.is_empty():
		return ""
	var at := source.find("while get_child_count() > MAX_ROWS:")
	if at < 0:
		return ""  # evicted some other way; nothing here can judge it
	# The body of that loop, generously bounded. A `remove_child` in it means
	# the child is gone before the next test of the condition, which is all the
	# loop needs to terminate.
	if source.substr(at, 240).contains("remove_child"):
		return ""
	return ("%s evicts rows with a bare queue_free() inside "
		+ "`while get_child_count() > MAX_ROWS`, which never terminates — the "
		+ "%dth death in any match hangs the process. Refusing to make the call. "
		+ "Fix: remove_child(oldest) before oldest.queue_free().") % [
			KILL_FEED_SCRIPT, KillFeed.MAX_ROWS + 1]


# ----------------------------------------------------------------- harness ---

## Free what the match left behind before quitting. Godot reports anything still
## alive at exit as a leak, and a harness that prints PASS above a wall of
## warnings teaches people to ignore warnings. A couple of dozen are reported
## regardless and always will be — they are the `preload` constants on the item
## and audio scripts, alive for as long as the scripts are, and `match_rules`
## carries the same note and the same tail of warnings.
##
## The session is deliberately *not* closed. `Net.leave_lobby` nulls the
## multiplayer peer, and every Bog still in the tree — the arena's, or the lobby
## backdrop's if the run stopped early — then calls `multiplayer.get_unique_id()`
## from `Bog.is_local()` on every frame of every `_process` it has, which buries
## the verdict under several hundred engine errors. Quitting is enough; the
## engine frees the tree on the way out.
func _teardown() -> void:
	MatchState.reset()
	for i in 4:
		await get_tree().process_frame


func _scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


## Spin frames until `ready` says yes. Wall clock rather than a frame count: the
## island build is one blocking frame of unknown length, so counting frames here
## would be counting the wrong thing entirely (D-012 makes the same point about
## the snapshot tool's warmup).
func _await_until(what: String, timeout: float, ready: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not bool(ready.call()):
		if Time.get_ticks_msec() > deadline:
			_checks += 1
			_failures += 1
			print("  FAIL  timed out after %.0f s waiting for %s" % [timeout, what])
			return false
		await get_tree().process_frame
	return true


func _check(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		return
	_failures += 1
	print("  FAIL  %s: got %s, wanted %s" % [what, str(got), str(want)])


## A check the rest of the run depends on. Same accounting, but the caller is
## expected to stop.
func _require(what: String, ok: bool) -> bool:
	_check(what, ok, true)
	return ok


func _find_hud() -> HUD:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _find_first(scene, func(node: Node) -> bool: return node is HUD) as HUD


## Depth-first search for the first node the predicate accepts. The HUD and the
## results screen are found this way rather than by path because both are
## instanced scenes whose unique-name (`%`) markers only resolve inside the
## scene that declares them.
func _find_first(from: Node, accepts: Callable) -> Node:
	if bool(accepts.call(from)):
		return from
	for child in from.get_children():
		var hit := _find_first(child, accepts)
		if hit != null:
			return hit
	return null
