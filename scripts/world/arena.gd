class_name Arena
extends Node3D
## The map, whichever one it is — and the scene `SceneFlow.go_to_arena()` loads.
##
## This is the node that closes the loop between the world and the match:
## everything above it in `scripts/game` waits for exactly one call,
## `MatchState.register_arena(players_root, spawn_points)`, and until something
## makes it there is no game. `tools/combat_range.tscn` was the only caller until
## this scene existed, which is why this file keeps to the same contract it does:
## build the world, hand over a node to parent Bogs under and a list of places to
## put them, and then get out of the way.
##
## *Which* map is `Net.config.map`, an id into `MapCatalog`. It rides with the
## roster the way the seed does, so every peer already knows the answer before
## this scene loads, and there is exactly one branch on it here.
##
## **Procedural** (Whisperbloom Hollow) is generated on the spot, in an order
## that is load-bearing:
##
##   1. **terrain**, because everything else asks it how high the ground is;
##   2. **landmarks**, because they are hand-placed and get first refusal on
##      where they stand;
##   3. **spawn points**, which need to dodge the landmarks and then become
##      obstacles themselves;
##   4. **prop scatter**, which fills whatever is left without ever landing on
##      anything from 2 or 3;
##   5. **torches**, from the spots the landmarks asked for;
##   6. **ambience**, which needs to know where the scatter put its trees.
##
## **Static** maps skip all of it. The scene owns its own environment, sun,
## lights and collision, and it states its spawns instead of having them solved
## — so `_build_environment` and the moon must not run for one, or a daylit
## arena gets the island's moonlit night dropped over the top of it (D-009).
## `scripts/world/static_map.gd` is the contract such a scene answers to.
##
## Both branches end the same way: containers built, `spawn_points` filled,
## `MatchState` told where the floor is, `register_arena` called, and then the
## two things that need a finished map — the Capture rings, and the navmesh the
## guide line and the minimap are drawn on (`_build_navigation`).
##
## Nothing here is replicated either way. Every peer builds the same island
## because every peer builds it from `Net.config.map_seed`, which is part of the
## match config and therefore already on every machine before this scene loads
## (D-007); every peer loading a static map loads the same file off disk.

const ENVIRONMENT := "res://resources/config/arena_env.tres"

## D-009: the sky shader draws the moon at `LIGHT0_DIRECTION`, so this
## DirectionalLight3D *is* the moon. Changing where it points moves the moon in
## the sky. The energy is deliberately tiny — it is fill, and the torches are the
## key light.
const MOON_DIRECTION := Vector3(-0.42, 0.38, -0.82)
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY := 0.30

## How many spawn pads to lay out. Eight, matching `MatchConfig.MAX_PLAYERS`, so
## a full lobby never has two Bogs sharing a pad on the opening frame.
const SPAWN_COUNT := MatchConfig.MAX_PLAYERS
## Pads sit at this fraction of the main island's rim radius: far enough out that
## nobody opens the match standing in the hollow with five sightlines on them,
## far enough in that a spawn is never a step from the void.
const SPAWN_RING := 0.66
## A pad must be flatter than this and at least this far inside the rim.
const SPAWN_MAX_SLOPE := 0.32
const SPAWN_RIM_MARGIN := 4.0
## And at least this far from every pad solved before it. Two bearings that both
## have to swing clear of the knoll used to come to rest on the same patch of
## flat ground, 3-5 m apart — one pad in all but name (D-055).
##
## Six metres is as much as the ring has to give. Eight pads evenly spaced on a
## circle at SPAWN_RING of a 23 m rim sit 2·0.66·23·sin(π/8) ≈ 11.6 m from their
## neighbours, but the sweep below may swing a pad 37 degrees either way and
## shift it ±3.8 m in and out to get off the shrine, and two neighbours both
## running from the same landmark close most of that gap between them. Half the
## ideal spacing is the floor that still leaves the search somewhere to go:
## measured over twelve seeds it comes out at 6.2-10.2 m with room to spare,
## while seven metres already runs a bearing out of ground on seed 20263835 —
## the one whose ideal points straight at the knoll (D-151).
const SPAWN_MIN_APART := 6.0
## Bogs are spawned a few centimetres up so the capsule settles onto the ground
## rather than starting the match intersecting it.
const SPAWN_LIFT := 0.12

var island: IslandGenerator
var landmarks: Landmarks
var scatter: PropScatter
var spawn_points: Array[Transform3D] = []

var _players: Node3D
var _items: Node3D


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var entry := MapCatalog.get_entry(Net.config.map)

	# The island's floor first, for both branches: `MatchState` is an autoload,
	# so a static map's shallower void height would otherwise survive into the
	# next match on a different map and start killing people in mid-air.
	MatchState.set_void_height()

	if int(entry["kind"]) == MapCatalog.Kind.STATIC:
		_build_static(entry, started)
	else:
		_build_procedural(entry, started)

	# Capture B·O·G's objectives, if the map states any (D-051). Every map is
	# asked, whatever the condition, and a procedural map states none: its
	# layout is the fallback planned from the spawn ring.
	var static_map := get_node_or_null("Map") as StaticMap
	if static_map != null:
		MatchState.set_capture_map(static_map.base_points(), static_map.letter_points(),
			static_map.base_radius)
	else:
		MatchState.set_capture_map([] as Array[Vector3], [] as Array[Vector3])

	# The handover. Every peer calls this for itself; only the host acts on it,
	# and it is what starts the warmup.
	MatchState.register_arena(_players, spawn_points)
	_build_capture_bases()
	_build_navigation()


# -------------------------------------------------------------- procedural ---

## Whisperbloom Hollow, grown from the seed. The order is the one in the header
## and every step of it depends on the one before it.
func _build_procedural(entry: Dictionary, started: int) -> void:
	var map_seed := Net.config.map_seed

	_build_environment()
	_build_containers()

	island = IslandGenerator.new(map_seed)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	island.build_into(terrain)

	landmarks = Landmarks.new(island, map_seed)
	landmarks.build(self)

	_build_spawn_points()

	scatter = PropScatter.new(island, map_seed, landmarks.keepouts)
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	scatter.scatter(props)

	_build_torches()
	Ambience.build(self, island, scatter.canopy_points, map_seed, scatter.canopy_radii)

	print("arena: %s built from seed %d in %d ms" % [
		entry["display_name"], map_seed, Time.get_ticks_msec() - started])
	print("  %d props (~%dk triangles), %d spawns, %d torches" % [
		scatter.instances, scatter.triangles / 1000, spawn_points.size(),
		$Torches.get_child_count()])
	print("  scatter %s" % scatter.counts)


# ------------------------------------------------------------------ static ---

## A hand-made map: instance it, and take its word for everything.
##
## Nothing generated runs here — no environment, no moon, no terrain, no
## scatter, no ambience. The scene brings its own, which is the point of buying
## one, and `StaticMap` is where the list of what it owes us is written down.
func _build_static(entry: Dictionary, started: int) -> void:
	_build_containers()

	var path := String(entry["scene"])
	var packed := load(path) as PackedScene
	if packed == null:
		# There is no world, and nothing here can make one. Said out loud and
		# then survived rather than crashed on: `register_arena` still runs, so
		# the match reaches a results screen instead of hanging behind a
		# loading card that never goes away.
		push_error("arena: map '%s' names a scene that will not load (%s)"
			% [entry["id"], path])
		return

	var map := packed.instantiate()
	# Renamed rather than left as whatever the designer saved the root as.
	# `Arena/Map` is a path tools can rely on; "it is called what the .tscn is
	# called" is not a contract.
	map.name = "Map"
	add_child(map)

	var static_map := map as StaticMap
	if static_map == null:
		push_error("arena: the root of map '%s' is not a StaticMap, so nothing "
			% entry["id"] + "can say where to spawn or where the void starts")
		return

	# Added to the tree first, deliberately: the markers are read in world
	# space, and `global_transform` on a node outside the tree is a local
	# transform wearing a disguise.
	spawn_points = static_map.spawn_points()
	# The map's own floor. A bought arena stands on the ground rather than
	# floating over 45 m of nothing, and a Bog that steps off one should be dead
	# before the fall gets boring.
	MatchState.set_void_height(static_map.void_height)

	print("arena: %s built from %s in %d ms" % [
		entry["display_name"], path, Time.get_ticks_msec() - started])
	print("  %d spawns; the scene supplies its own environment, lights and collision"
		% spawn_points.size())


# ------------------------------------------------------------- environment ---

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = load(ENVIRONMENT)
	add_child(world)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	# Positioned then aimed at the origin, so `LIGHT0_DIRECTION` inside the sky
	# shader comes out as MOON_DIRECTION exactly and the moon disc is drawn where
	# the moonlight is coming from. Setting a rotation by hand and hoping the two
	# agree is how a moon ends up lighting the island from behind itself.
	moon.position = MOON_DIRECTION.normalized() * 80.0
	moon.look_at(Vector3.ZERO, Vector3.UP)
	moon.light_color = MOON_COLOR
	moon.light_energy = MOON_ENERGY
	moon.light_specular = 0.35
	moon.shadow_enabled = true
	# The island is ~55 m across, so shadows past 90 m are shadows of nothing.
	moon.directional_shadow_max_distance = 90.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.light_volumetric_fog_energy = 0.6


func _build_containers() -> void:
	# `MatchState._create_bog` parents every Bog here.
	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)

	# `BogCombat._spawn_root` finds this by group. Without it every spear,
	# shield and magnet is parented to the scene root and nothing can be swept
	# up between rounds.
	_items = Node3D.new()
	_items.name = "SpawnedItems"
	_items.add_to_group("spawned_items")
	add_child(_items)


# ------------------------------------------------------------------ spawns ---

## Lay out the spawn ring (4.10).
##
## Pads are evenly spaced around the main island rather than placed by hand,
## because the rim outline moves with the seed and eight hand-typed coordinates
## would drift off the island the first time somebody changed it. What *is* hand
## decided is the shape of the ring: even spacing, well inside the rim, off the
## high ground, and never inside a landmark.
##
## Each pad is searched for rather than assumed: the ideal point is tried first,
## then rings of alternates around it. A pad that cannot be solved falls back to
## its ideal position, which is always on land — it may just be steeper than we
## would like, and a slightly awkward spawn beats a missing one.
func _build_spawn_points() -> void:
	var mass := island.landmasses[0]
	var rng := RandomNumberGenerator.new()
	# Offset from the map seed so the ring rotates between maps and the same
	# bearing is not always "the spawn behind the shrine".
	rng.seed = Net.config.map_seed ^ 0x59A70

	var twist := rng.randf_range(0.0, TAU)
	for i in SPAWN_COUNT:
		var bearing := twist + TAU * float(i) / float(SPAWN_COUNT)
		var found := _solve_spawn(mass, bearing)
		var ground := island.surface_point(found.x, found.y) + Vector3.UP * SPAWN_LIFT
		# Facing the middle of the map. A player whose first frame looks out over
		# the void has to turn around before they can read anything.
		var yaw := Bog.yaw_towards(Vector3(-found.x, 0.0, -found.y).normalized())
		spawn_points.append(Transform3D(Basis(Vector3.UP, yaw), ground))

		# Published to the scatter so no tree or boulder grows on a pad and a Bog
		# can see out of its own spawn. Deliberately a *sparse-only* keepout:
		# an earlier version also kept the dense layers off, and every pad came
		# out as a bald circle of bare earth four metres across — which is both
		# ugly and a free map marker showing everyone where the spawns are.
		landmarks.keepouts.append(PropScatter.Keepout.new(found, 3.6, false))


## Search outward from the ideal pad until something passes every rule.
##
## The sweep has to be wide. The spawn ring sits at two thirds of the rim radius
## and the knoll's centre is 11 m out, so the ring runs straight through the
## shrine — the pad whose ideal bearing points at the high ground has to travel a
## long way to get clear of it. A fifth of a radian was not nearly enough: that
## pad ran out of tries and landed on a 32-degree slope inside the shrine's own
## courtyard, and widening it only slightly then put it on the shrine *platform*,
## which is worse. Spawning on the map's commanding position is not a cosmetic
## defect.
##
## So: a full sweep for a pad that satisfies everything; failing that, the
## flattest pad that is at least out of every landmark, accepting a slope we
## would rather not have; and only if even that finds nothing, the roomiest spot
## the sweep saw.
##
## That last tier used to be the ideal position, handed back without asking
## anything of it — which made the separation below a preference rather than a
## rule, since the one path that gives up on every other rule gave up on that one
## too. Nothing on the seeds we ship reaches it, but a pad that lands on top of
## another is the defect this whole search exists to avoid, and a fallback that
## can produce it is not a fallback (D-151). So the crowded candidates are kept
## as they go past, and the one standing furthest from its neighbours is what a
## failed sweep hands back.
func _solve_spawn(mass: IslandGenerator.Landmass, bearing: float) -> Vector2:
	var fallback := Vector2.INF
	var fallback_slope := INF
	var roomiest := Vector2.INF
	var roomiest_gap := -INF
	for swing_step in 13:
		# 0, +0.16, -0.16, +0.32, -0.32 ... out to about 37 degrees either way.
		var swing := 0.16 * float((swing_step + 1) / 2) 			* (1.0 if swing_step % 2 == 0 else -1.0)
		for ring_step in 7:
			# 0, -0.055, +0.055, -0.11 ... — the ideal ring first and alternates
			# either side of it after, as the header says. This used to count
			# 0..6 from the *innermost* ring, which won on nearly every bearing and
			# pulled the whole ring in to 0.5 of the rim: bases 18.8 m apart and
			# two pads 4 m from each other (D-055).
			var offset := (ring_step + 1) / 2 * (1 if ring_step % 2 == 0 else -1)
			var fraction := SPAWN_RING + 0.055 * float(offset)
			var spot := _spawn_candidate(mass, bearing + swing, fraction)
			if not _spawn_is_clear(mass, spot):
				continue
			# Separation is asked here rather than inside `_spawn_is_clear` because
			# it is the one rule whose near misses are worth keeping: a spot that is
			# only too close is still standable ground on the right landmass, and it
			# is what the last tier below falls back on.
			var gap := _pad_gap(spot)
			if gap < SPAWN_MIN_APART:
				if gap > roomiest_gap:
					roomiest_gap = gap
					roomiest = spot
				continue
			var slope := island.slope_at(spot.x, spot.y, 0.8)
			if slope <= SPAWN_MAX_SLOPE:
				return spot
			if slope < fallback_slope:
				fallback_slope = slope
				fallback = spot

	if fallback != Vector2.INF:
		push_warning("arena: spawn at bearing %.2f is steeper than wanted (%.2f)"
			% [bearing, fallback_slope])
		return fallback
	if roomiest != Vector2.INF:
		push_warning("arena: every spawn at bearing %.2f is crowded; taking the "
			% bearing + "roomiest at %.1f m from its neighbour" % roomiest_gap)
		return roomiest
	push_warning("arena: no clear spawn at bearing %.2f; using its ideal position"
		% bearing)
	return _spawn_candidate(mass, bearing, SPAWN_RING)


func _spawn_candidate(mass: IslandGenerator.Landmass, bearing: float,
		fraction: float) -> Vector2:
	return Vector2(cos(bearing), sin(bearing)) * mass.rim_radius(bearing) * fraction


## How far the nearest pad solved before this one is, on the ground plane, or INF
## for the first pad of the ring. `_solve_spawn` compares it against
## SPAWN_MIN_APART itself, because it keeps the crowded near misses.
func _pad_gap(spot: Vector2) -> float:
	var gap := INF
	for pad: Transform3D in spawn_points:
		gap = minf(gap, spot.distance_to(Vector2(pad.origin.x, pad.origin.z)))
	return gap


## Everything about a pad the search will not bend on: on the right landmass,
## well inside the rim, out of every landmark and off every torch. Slope and
## separation are judged separately, because those are the two rules the search
## will trade against each other when a bearing runs out of ground.
func _spawn_is_clear(mass: IslandGenerator.Landmass, spot: Vector2) -> bool:
	if island.landmass_at(spot.x, spot.y) != mass:
		return false
	if island.inset_at(spot.x, spot.y) < SPAWN_RIM_MARGIN:
		return false
	for keepout: PropScatter.Keepout in landmarks.keepouts:
		# Only the hard keepouts matter: a spawn is allowed to be on the grassy
		# skirt of a landmark, just not inside the landmark.
		if keepout.blocks_dense and spot.distance_to(keepout.centre) < keepout.radius + 1.5:
			return false
	# And never on top of a torch. Torches are placed before the spawn ring is
	# solved, and a pad that lands on one puts a player in the brightest circle
	# on the island on their first frame, fully lit to everyone outside it.
	for torch: Landmarks.TorchSpot in landmarks.torch_spots:
		if spot.distance_to(Vector2(torch.position.x, torch.position.z)) < 3.5:
			return false
	return true


# ----------------------------------------------------------------- torches ---

## Plant a torch at every spot the landmark pass asked for (4.5).
##
## The landmarks decide *where* — a torch marks something worth marking — and
## this decides only how many of them get to cast shadows, because that is a
## frame-cost question rather than a level-design one.
func _build_torches() -> void:
	var lights := Node3D.new()
	lights.name = "Torches"
	add_child(lights)

	var index := 0
	for spot: Landmarks.TorchSpot in landmarks.torch_spots:
		# A landmark can ask for a torch on ground the seed moved out from under
		# it. Better a missing torch than one burning in mid-air over the void.
		if spot.position.y <= IslandGenerator.NO_LAND:
			continue
		# Phase from the index and the seed: deterministic across clients, and
		# irrational enough between neighbours that no two torches pulse together.
		var phase := fposmod(float(index) * 2.399963 + float(Net.config.map_seed % 997), TAU)
		var torch := Torch.create(phase, spot.shadows, spot.height_scale)
		torch.name = "Torch%d" % index
		torch.position = spot.position
		lights.add_child(torch)
		index += 1


# ----------------------------------------------------------------- capture ---

## A glowing ring in each team's colour at each Capture B·O·G base (D-051),
## from the layout `register_arena` just planned. On every peer, and only in
## that mode: a base drawn in a kill-limit match is a promise of a rule that is
## not there.
func _build_capture_bases() -> void:
	var layout := MatchState.capture_layout()
	if not MatchState.is_capture() or layout == null:
		return
	var holder := Node3D.new()
	holder.name = "CaptureBases"
	add_child(holder)
	for team in layout.bases.size():
		var base := CaptureBase.create(team, layout.base_radius)
		# The base point is a spawn pad or a map's marker, both at foot height.
		base.position = layout.bases[team]
		holder.add_child(base)
		# And the vault inside it, which is where the cards actually stand
		# (D-092). Drawn as its own small ring rather than folded into the base's
		# so the two read as different promises: the big one is the team's
		# ground, the small one is the thing you walk onto to bank — and the
		# thing an enemy stands on for three seconds to take a letter away.
		if team < layout.vaults.size():
			var vault := CaptureBase.create(team, layout.vault_radius)
			vault.name = "Vault%d" % (team + 1)
			vault.position = layout.vaults[team]
			holder.add_child(vault)
	print("  capture: %d bases + %d vaults (%s), letters %s" % [layout.bases.size(),
		layout.vaults.size(),
		"declared by the map" if layout.bases_declared else "fallback from the spawn pads",
		"declared by the map" if layout.letters_declared else "fallback between the bases"])


# -------------------------------------------------------------- navigation ---

## The navmesh and the guide line, on every peer, for that peer alone.
##
## Added here for the same reason the capture rings are: this is the one node
## that knows the map has finished being built, whichever branch built it, and
## both of these need the collision that `_build_static` or the island
## generator has just put on layer 1. `NavBake` waits two more physics frames
## of its own before it parses, because a static map builds its `Collision`
## body inside its own `_ready` and a body is not in the broadphase until the
## frame after it is added.
##
## **Nothing here is replicated and nothing here is a rule.** The bake is local
## and cosmetic in exactly the sense a ragdoll is (D-010): every peer bakes its
## own navmesh off geometry it already has, in its own time, and the result is
## read by one dashed line on one screen and by that screen's minimap. The host
## still decides everything that counts (D-007) — it has no navmesh at all and
## does not need one.
##
## Both are added whatever the mode. `GuideTargets` is what knows the line has
## nothing to say outside B·O·G; `NavBake` is what the minimap asks for the
## shape of the map, which is a question the mode does not change.
func _build_navigation() -> void:
	var nav := NavBake.new()
	nav.name = "NavBake"
	add_child(nav)

	var guide := GuideLine.new()
	guide.name = "GuideLine"
	add_child(guide)
