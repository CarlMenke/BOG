class_name HUD
extends CanvasLayer
## Everything drawn over a running match (PLAN 6.1-6.7).
##
## The arena is expected to instance this once, as a child of its root:
##
##     [node name="HUD" parent="." instance=ExtResource("res://scenes/ui/hud.tscn")]
##
## It reaches into no arena node and holds no reference to one. Everything it
## shows comes from `MatchState`, `Net` and the local Gub's own `GubCombat`, so
## it works over any scene that has registered an arena — including
## `tools/hud_range.tscn`, which is how every screen in it was looked at.
##
## Four things are read every frame rather than driven by signals: the ability
## bar, the clock, the seconds left on a letter hold, and the seconds left on the
## Elder's robe. Three of those are wall-clock deadlines with no per-frame signal
## to hang off — inside `GubCombat` for the bar, on the host for the other two —
## and the clock is broadcast twice a second, so polling is both simpler and
## smoother than the alternative.
## Everything else — kills, scores, phases, deaths, letters — arrives as a signal
## and is handled once. The controls being pushed to all early-out when nothing
## has actually moved, which is what keeps a per-frame push cheap.

## The banner is the only element that ever covers the middle of the screen, so
## it is on a short leash.
const FLASH_TIME := 1.4

## Your own health bar, in pixels. The same 224 wide as the Elder's track and
## the letter hold's, because they stack in one column and a column of bars of
## three different widths reads as three unrelated things. Taller than either,
## at 22, because it carries a number inside it and because it is the one thing
## in that column you are always looking at.
const HEALTH_BAR := Vector2(224.0, 22.0)

## Everything drawn *during* play lives under this one node — clock, score, kill
## feed, crosshair, banner, ability bar, chat. The scoreboard, pause menu and
## results screen are its siblings, so any of them can take the screen by
## hiding it rather than by each element knowing about each overlay.
@onready var _root: Control = $Root
@onready var _crosshair: Crosshair = %Crosshair
@onready var _clock: Label = %Clock
@onready var _score_line: RichTextLabel = %ScoreLine
@onready var _team_chip: PanelContainer = %TeamChip
@onready var _team_label: Label = %TeamLabel
@onready var _kill_feed: KillFeed = %KillFeed
@onready var _lives: HBoxContainer = %Lives
@onready var _letters: LetterTrack = %Letters
@onready var _elder: ElderTrack = %Elder
@onready var _abilities: HBoxContainer = %Abilities
@onready var _spear_slot: AbilitySlot = %SpearSlot
@onready var _mushroom_slot: AbilitySlot = %MushroomSlot
@onready var _lure_slot: AbilitySlot = %LureSlot
@onready var _banner: Control = %Banner
@onready var _banner_title: Label = %BannerTitle
@onready var _banner_sub: Label = %BannerSub
@onready var _spectate_label: Label = %SpectateLabel
@onready var _chat: ChatPanel = %Chat
@onready var _scoreboard: Scoreboard = %Scoreboard
@onready var _pause: PauseMenu = %PauseMenu
@onready var _results: ResultsScreen = %Results

## Counts down the phase this client believes it is in. `phase_changed` does not
## carry the phase timer, so a warmup countdown has to be run locally off
## `MatchConfig.warmup_time`. Both sides start it from the same RPC, so they
## agree to within a round trip, which is well inside what a countdown needs.
var _phase_clock: float = 0.0
## Seconds until the local Gub respawns, from `local_death`.
var _respawn_clock: float = 0.0
## Index into `MatchState.living_gubs()` while spectating (PLAN 6.5). Held as an
## index rather than as a reference to the Gub because the list changes under us
## constantly — the player being watched dies, respawns, or leaves — and an index
## degrades into "somebody else" where a stale reference degrades into a crash.
var _spectate_index: int = 0
var _spectating: bool = false
var _flash: float = 0.0
## Your own health, built in `_build_health` rather than in `hud.tscn`.
var _health: Control
var _health_fill: ColorRect
var _health_value: Label
## What the bar and the number are currently showing, so a per-frame refresh of
## something that changes a few times a minute costs a comparison.
var _health_fraction: float = -1.0
var _health_shown: int = -1


func _ready() -> void:
	layer = 8
	# The match owns the mouse. This used to say `recapture_cursor("hud")`, which
	# could never work: the HUD has no hold of its own to give back, and the
	# holds that actually mattered were taken by the menu and the lobby. Entering
	# the arena means nothing that wants the cursor is on screen any more, so say
	# that directly. `SceneFlow.go_to` also clears on the way in; this covers the
	# testbeds, which stand the arena up without ever going through it.
	# Anything that wants the cursor back from here asks by name.
	SceneFlow.clear_cursor_holds()

	_chat.compact = true
	_chat.submitted.connect(Net.send_chat)
	_pause.resumed.connect(_on_resumed)
	_pause.left_match.connect(_on_leave_match)
	_results.return_to_lobby.connect(_on_back_to_lobby)
	_results.rematch.connect(_on_rematch_pressed)

	MatchState.phase_changed.connect(_on_phase_changed)
	MatchState.scores_changed.connect(_refresh_score)
	MatchState.player_killed.connect(_on_player_killed)
	MatchState.match_finished.connect(_on_match_finished)
	MatchState.local_death.connect(_on_local_death)
	MatchState.local_respawn.connect(_on_local_respawn)
	MatchState.letters_changed.connect(_on_letters_changed)
	MatchState.letter_hold_changed.connect(_on_letters_changed)
	MatchState.letter_picked_up.connect(_on_letter_picked_up)
	MatchState.letter_banked.connect(_on_letter_banked)
	MatchState.letter_dropped.connect(_on_letter_dropped)
	MatchState.letter_returned.connect(_on_letter_returned)
	Net.chat_received.connect(_chat.add_message)
	Net.left_lobby.connect(_on_left_lobby)
	Net.return_to_lobby_requested.connect(_go_to_lobby)
	Net.rematch_requested.connect(_on_rematch)

	_banner.visible = false
	_build_health()
	_refresh_score()
	_refresh_letters()
	_on_phase_changed(MatchState.phase)


func _process(delta: float) -> void:
	_tick_clocks(delta)
	_refresh_crosshair()
	_refresh_health()
	_refresh_abilities()
	_refresh_letters()
	_refresh_elder()
	_refresh_clock()
	if _spectating:
		_apply_spectator()
	# An invariant rather than something switched on at the moment the match
	# ends: the results screen replaces the gameplay HUD, it does not sit over
	# it. Written this way it holds no matter who put the results screen up —
	# `tools/hud_range.tscn` calls `show_summary` directly, and a rule that only
	# fires on `match_finished` would be quietly false in the one place anybody
	# ever photographs this screen.
	_root.visible = not _results.visible


# ------------------------------------------------------------------- input ---

func _unhandled_input(event: InputEvent) -> void:
	# Typing beats every other binding: T is also a perfectly good movement key
	# on somebody's layout, and the scoreboard must not open under a message.
	if _chat.is_typing():
		return

	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_toggle_pause()
		return
	if _pause.visible or _results.visible:
		return
	# Dead players have no spear to throw, so the throw and aim buttons are free
	# and are the two most obvious things to press. They step the spectator
	# camera forward and back through whoever is still alive.
	if _spectating:
		if event.is_action_pressed("throw_spear"):
			get_viewport().set_input_as_handled()
			_step_spectator(1)
			return
		if event.is_action_pressed("aim"):
			get_viewport().set_input_as_handled()
			_step_spectator(-1)
			return
	if event.is_action_pressed("scoreboard"):
		_scoreboard.open()
	elif event.is_action_released("scoreboard"):
		_scoreboard.close()
	elif event.is_action_pressed("chat"):
		get_viewport().set_input_as_handled()
		_begin_chat()


func _toggle_pause() -> void:
	if _results.visible:
		return
	if _pause.visible:
		_pause.close()
	else:
		_scoreboard.close()
		_pause.open()


func _on_resumed() -> void:
	pass  # the pause menu has already handed the cursor back


## Typing releases the cursor, which is what actually stops the Gub looking
## around and throwing spears: `GubCamera` and `GubCombat` both check
## `SceneFlow.cursor_is_free()` before acting on input.
func _begin_chat() -> void:
	_chat.set_input_visible(true)
	SceneFlow.release_cursor("chat")


func _on_chat_closed() -> void:
	SceneFlow.recapture_cursor("chat")


# ----------------------------------------------------------------- per frame ---

func _tick_clocks(delta: float) -> void:
	if _phase_clock > 0.0:
		_phase_clock = maxf(0.0, _phase_clock - delta)
		_banner_sub.text = "%d" % ceili(_phase_clock) if _phase_clock > 0.0 else "GO"
	if _respawn_clock > 0.0:
		_respawn_clock = maxf(0.0, _respawn_clock - delta)
		_banner_sub.text = "Back in %d" % ceili(_respawn_clock) if _respawn_clock > 0.0 \
			else "Any moment now"
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _flash <= 0.0 and _respawn_clock <= 0.0 and _phase_clock <= 0.0:
			_banner.visible = false
	# Chat closes itself on send; the cursor hold has to be released with it.
	if not _chat.is_typing() and _chat.visible and SceneFlow.cursor_is_free() \
			and not _pause.visible and not _results.visible:
		SceneFlow.recapture_cursor("chat")


## Armed means "there is a living Gub behind this crosshair", and since D-036
## that is the whole of what the crosshair says. Whether that Gub has a spear is
## answered by the spear in its hand, which is drawn off the one gate the throw
## is (`GubCombat.has_spear`) — so there is nothing here to divide, and no
## denominator left to get wrong for a third time.
func _refresh_crosshair() -> void:
	_crosshair.set_state(_local_combat() != null and MatchState.is_alive(Net.local_id()))


## Your own health (D-062), in the bottom-centre column with everything else the
## local player owns.
##
## **Not on the crosshair, and not a vignette.** D-036 threw the recharge ring
## out of the middle of the screen and the rule it left behind is that the
## middle of the screen is for aiming; a health readout is exactly the thing
## that gets put there next. A red edge on the screen was the other candidate
## and is worse for this game: Gubs are small, bright and fast against a dark
## forest, and washing the edges of the frame red hurts the one thing a hurt
## player needs most, which is seeing the Gub that is hurting them.
##
## **A number as well as a bar.** The bar is what you glance at; the number is
## what tells you whether the next arrow kills you, and with damage running from
## 20 to 80 that is arithmetic a player can genuinely do. It is your own health
## only — nobody else's number is ever shown as a number, because a bar over a
## body is a read and a number over a body is a spreadsheet.
##
## Unlike the plate over a Gub's head, this is **always** up while you are
## alive. A missing bar on your own screen is indistinguishable from a bar you
## have not looked at, and "am I hurt" has to be answerable without remembering.
func _refresh_health() -> void:
	var gub := MatchState.local_gub()
	var alive := gub != null and MatchState.is_alive(Net.local_id())
	_health.visible = alive and MatchState.phase != MatchState.Phase.IDLE
	if not _health.visible:
		return
	var fraction := gub.health_fraction()
	var shown := maxi(1, ceili(gub.health)) if gub.health > 0.0 else 0
	# Rounded *up*, so the last sliver of a Gub is a 1 and never a 0. A player
	# reading "0" while still standing believes the HUD has broken; the same
	# rule the letter and Elder countdowns use for the same reason.
	if shown != _health_shown:
		_health_shown = shown
		_health_value.text = str(shown)
	if is_equal_approx(fraction, _health_fraction):
		return
	_health_fraction = fraction
	_health_fill.anchor_right = fraction
	var colour := UIPalette.GOOD
	if fraction < Nameplate.HEALTH_LOW_AT:
		colour = UIPalette.DANGER
	elif fraction < Nameplate.HEALTH_HURT_AT:
		colour = UIPalette.AMBER
	_health_fill.color = colour


## Built here rather than in `hud.tscn` for the same reason the lives pips are:
## it is one row of two rectangles and a number whose whole behaviour is in this
## file, and a scene node for it would be a second place to look.
##
## It goes in immediately above the ability tiles, which is the bottom of the
## column and the closest this HUD has to "about you, right now".
func _build_health() -> void:
	var column := _abilities.get_parent() as Control
	_health = Control.new()
	_health.name = "Health"
	_health.custom_minimum_size = HEALTH_BAR
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health.visible = false

	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = UIPalette.faded(UIPalette.VOID, 0.72)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health.add_child(back)

	_health_fill = ColorRect.new()
	_health_fill.anchor_right = 1.0
	_health_fill.anchor_bottom = 1.0
	_health_fill.color = UIPalette.GOOD
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health.add_child(_health_fill)

	_health_value = Label.new()
	_health_value.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_value.add_theme_font_size_override("font_size", UIPalette.FONT_SMALL)
	# The number stays white while the bar changes colour, and that is not an
	# oversight: it sits *on* the fill, so a number tinted to match it would be
	# green on green at full health — the one state a player glances at most.
	# The colour is the bar's job and the outline is what keeps the number
	# legible over either it or the dark backing.
	_health_value.add_theme_color_override("font_color", UIPalette.TEXT)
	_health_value.add_theme_color_override("font_outline_color", UIPalette.VOID)
	_health_value.add_theme_constant_override("outline_size", 5)
	_health_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health.add_child(_health_value)

	column.add_child(_health)
	column.move_child(_health, _abilities.get_index())


func _refresh_abilities() -> void:
	var combat := _local_combat()
	if combat == null:
		# Spectating: the bar stays on screen but plainly inert, rather than
		# vanishing and taking the layout with it.
		_abilities.modulate = Color(1, 1, 1, 0.25)
		return
	_abilities.modulate = Color(1, 1, 1, 1.0 if MatchState.is_alive(Net.local_id()) else 0.3)
	# `has_spear()` is still the one boolean for lit or dark — it covers the
	# recharge *and* a letter hold (D-035), so the tile cannot disagree with the
	# hand about whether there is a spear. What D-054 adds on top is the timer,
	# and it is handed over only when the recharge is genuinely the reason:
	#
	# * Not during the windup. The spear is still in the hand and the clock the
	#   tile would read is the whole cycle, which is exactly the "already gone"
	#   ring D-036 threw away. Timed from the release, the sweep starts empty
	#   and the number starts at the full recharge, which is the truth.
	# * Not during a hold or a capture carry (D-051 made a carry a hold with no
	#   clock). A recharge that reaches zero over a Gub still holding a card
	#   would be a countdown to nothing; the lamps are that player's timer.
	#
	# For an Elder the tile is a different weapon and the same sentence: the
	# glyph swaps to a bolt and its own clock and denominator are used (D-038,
	# D-040).
	var spear_timed := not combat.is_winding_up() and not combat.is_holding_letter()
	if combat.is_elder():
		# "Bolt" rather than "Lightning": the tile is 62 px wide and the other
		# three labels are Spear, Shield and Lure. A caption that overhangs its
		# own square would be the one thing on this bar that does not line up.
		_spear_slot.set_kind(AbilitySlot.Kind.LIGHTNING, "Bolt")
		_spear_slot.set_armed(combat.has_lightning(),
			combat.lightning_cooldown() if spear_timed else 0.0,
			Net.config.lightning_cooldown)
	else:
		_spear_slot.set_kind(AbilitySlot.Kind.SPEAR, "Spear")
		_spear_slot.set_armed(combat.has_spear(),
			combat.spear_cooldown() if spear_timed else 0.0,
			Net.config.spear_recharge)
	# Stock, not cooldowns (D-032). The count is the readout; the use-delay only
	# dims the tile, because it is a floor on spend rate and not something worth
	# timing a fight around. Note what is *not* passed: no totals — the spear
	# tile is the only thing on this bar that divides (D-054).
	_mushroom_slot.set_stock(combat.mushroom_count(), combat.mushroom_use_cooldown() > 0.0)
	_lure_slot.set_stock(combat.lure_count(), combat.lure_use_cooldown() > 0.0)


## The G/U/B lamps and the hold, for the local player only.
##
## Polled here as well as driven by the two signals, and both are wanted.
## `letters_changed` is what lights a lamp on the frame the host says so; the
## poll is for `letter_hold_remaining`, which is a deadline on the host with no
## per-frame signal behind it, so a countdown that only moved when a letter
## changed hands would sit perfectly still for the whole ten seconds.
## `LetterTrack.set_state` throws away the repaint when nothing actually moved,
## which is what makes paying for both free.
func _refresh_letters() -> void:
	var show := MatchConfig.scores_letters(Net.config.win_condition)
	_letters.visible = show
	if not show:
		return
	var me := Net.local_id()
	# A Capture G·U·B carry is a hold with no clock (D-051): the lamp is full
	# from the moment the card is picked up, and the caption says where to take
	# it instead of how long is left. `letter_hold_remaining` is INF for one, so
	# it is not handed to a control that would divide by it.
	var carrying := MatchState.is_capture()
	# `scoring_letters` is your team's pooled mask in Teams and your own in a
	# free-for-all (D-049) — the lamps show what the match is judged on, which
	# in Teams is not what you personally banked.
	_letters.set_state(MatchState.scoring_letters(me), MatchState.letter_hold_letter(me),
		0.0 if carrying else MatchState.letter_hold_remaining(me),
		Net.config.letter_hold_time,
		Net.config.mode == MatchConfig.Mode.TEAMS, carrying)


## The robe's countdown, for the local player only (D-040).
##
## Polled rather than driven by `elder_changed`, for exactly the reason the
## letter hold's countdown is: `elder_remaining` is a deadline on the host with
## no per-frame signal behind it, so a bar that only moved when somebody picked
## a robe up would sit perfectly still for the whole twenty seconds. There is no
## signal connection at all here — the signal only says the row appeared or went,
## which the poll notices on the next frame anyway.
##
## Unlike the letter track this is not gated on a win condition. The robe drops
## in every mode (D-038), so the row is shown whenever there is one and is
## invisible the rest of the time; `ElderTrack._draw` returns immediately when
## the robe is off, so an empty control costs a call and nothing else.
func _refresh_elder() -> void:
	var me := Net.local_id()
	_elder.set_state(MatchState.is_elder(me), MatchState.elder_remaining(me),
		Net.config.elder_duration)


func _refresh_clock() -> void:
	if Net.config.time_limit <= 0:
		_clock.text = "--:--"
		return
	_clock.text = UIPalette.clock(MatchState.time_left)
	# The last thirty seconds go amber. Nothing else on the HUD changes colour
	# with time, so it cannot be confused with anything.
	_clock.add_theme_color_override("font_color",
		UIPalette.AMBER if MatchState.time_left <= 30.0 else UIPalette.TEXT)


func _local_combat() -> GubCombat:
	var gub := MatchState.local_gub()
	if gub == null:
		return null
	return gub.get_node_or_null("Combat") as GubCombat


# ------------------------------------------------------------------- score ---

func _refresh_score() -> void:
	var config := Net.config
	var me := Net.local_id()
	if config.mode == MatchConfig.Mode.TEAMS:
		var parts: Array[String] = []
		for team in config.team_count:
			parts.append("[color=#%s]%d[/color]" % [
				UIPalette.team_colour(team).to_html(false), MatchState.team_score(team)])
		_score_line.text = "[center]%s[/center]" % "  [color=#4a545f]—[/color]  ".join(parts)
	else:
		var mine := MatchState.kills(me)
		var ranking := MatchState.ranking()
		var leader: int = ranking[0] if not ranking.is_empty() else me
		var target := " / %d" % config.kill_limit \
			if config.win_condition == MatchConfig.WinCondition.KILL_LIMIT else ""
		var tail := "you lead" if leader == me and mine > 0 \
			else "%s %d" % [Net.player_name(leader), MatchState.kills(leader)]
		_score_line.text = "[center][color=#%s]%d%s[/color]  [color=#4a545f]·[/color]  %s[/center]" % [
			UIPalette.GUB.to_html(false), mine, target, tail]

	_refresh_team_chip()
	_refresh_lives()


## Which team you are on, said in words and in its colour under the score (D-047).
## The score line already shows every team's colour, and that is exactly why it
## cannot answer this on its own: two coloured numbers do not say which is yours.
## Hidden in free-for-all, where there is no side to be on.
func _refresh_team_chip() -> void:
	var team := Net.player_team(Net.local_id())
	var show := Net.config.mode == MatchConfig.Mode.TEAMS and team >= 0
	_team_chip.visible = show
	if not show:
		return
	var colour := UIPalette.team_colour(team)
	_team_label.text = "TEAM %d" % (team + 1)
	_team_label.add_theme_color_override("font_color", colour)
	var box := StyleBoxFlat.new()
	box.bg_color = UIPalette.PANEL
	box.border_color = UIPalette.faded(colour, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(UIPalette.RADIUS)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 2
	box.content_margin_bottom = 3
	_team_chip.add_theme_stylebox_override("panel", box)


## Lives are pips rather than a number: at three or five, a row of shapes is
## read without counting, and the moment there is one left it is unmistakable.
func _refresh_lives() -> void:
	var config := Net.config
	var show := config.win_condition == MatchConfig.WinCondition.LIVES
	_lives.visible = show
	if not show:
		return
	for child in _lives.get_children():
		child.queue_free()
	var left := MatchState.lives_left(Net.local_id())
	for i in config.lives:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 5)
		pip.color = UIPalette.GUB if i < left else UIPalette.faded(UIPalette.TEXT, 0.16)
		_lives.add_child(pip)


# ----------------------------------------------------------------- signals ---

## Put the gameplay HUD back after a results screen. Leaving the arena rebuilds
## the whole scene so this would not be needed for that alone — but a rematch
## that reuses the arena would otherwise start with everything still hidden.
func restore_gameplay_hud() -> void:
	_root.visible = true
	_results.close()
	_end_spectating()


func _on_phase_changed(phase: int) -> void:
	match phase:
		MatchState.Phase.WARMUP:
			_phase_clock = maxf(0.1, Net.config.warmup_time)
			_show_banner("GET READY", "%d" % ceili(_phase_clock), UIPalette.AMBER)
		MatchState.Phase.PLAYING:
			_phase_clock = 0.0
			_flash = FLASH_TIME
			_show_banner("FIGHT", "", UIPalette.GUB)
		MatchState.Phase.POST_MATCH:
			_phase_clock = 0.0
			_flash = 0.0
			_banner.visible = false
			_scoreboard.close()
		_:
			_banner.visible = false
	_refresh_score()


func _on_player_killed(victim_id: int, killer_id: int, cause: int) -> void:
	_kill_feed.add_kill(victim_id, killer_id, cause)
	# Visual only. `MatchState` already plays the hitmarker sound and shakes the
	# camera on a kill; a second one from here would be two of each.
	if killer_id == Net.local_id() and victim_id != killer_id:
		_crosshair.strike()
	_refresh_score()


## Both letter signals carry a peer id and fire for everybody. Only your own
## hold is on the lamps: somebody else's is told in the feed and by the marker
## over their head (D-050), not by lighting anything of yours.
##
## A teammate's letter does light your lamps in Teams, though, because the lamps
## are the team's pooled mask there (D-049) — so a letter banked by anybody on
## your team has to refresh them. Refreshing on every peer is simpler than
## asking whose team the sender is on, and costs nothing: `LetterTrack.set_state`
## drops a repaint when nothing moved, and the other team's letters move nothing.
func _on_letters_changed(_peer_id: int) -> void:
	_refresh_letters()


## Somebody else's hold still gets nothing on the lamps, but since D-050 it gets
## a line in the feed: the lit card in a fist is only a tell to whoever can see
## the fist, and a letter is the rarest thing in the match. The Gub carrying it
## gets a marker over its head on every screen as well (`CarrierMarker`).
func _on_letter_picked_up(peer_id: int, letter: int) -> void:
	_kill_feed.add_event([peer_id, "picked up",
		[MatchState.letter_name(letter), Pickup.LETTER_COLOUR]])


func _on_letter_banked(peer_id: int, letter: int) -> void:
	_kill_feed.add_event([peer_id, "banked",
		[MatchState.letter_name(letter), Pickup.LETTER_COLOUR]])


## Capture G·U·B (D-051). A carrier's death already has a kill row; this is the
## row that says the card is now on the ground and whose it was, which is what
## both teams run towards.
func _on_letter_dropped(peer_id: int, letter: int) -> void:
	_kill_feed.add_event([peer_id, "dropped",
		[MatchState.letter_name(letter), Pickup.LETTER_COLOUR]])


func _on_letter_returned(letter: int) -> void:
	_kill_feed.add_event([[MatchState.letter_name(letter), Pickup.LETTER_COLOUR],
		"went home"])


func _on_local_death(respawn_in: float) -> void:
	_scoreboard.close()
	# Watch somebody who is still playing rather than the patch of dirt you died
	# on. This matters most in a lives match, where "dead" is permanent and the
	# alternative is staring at your own corpse until the match ends.
	_begin_spectating()
	if _is_eliminated():
		_respawn_clock = 0.0
		_show_banner("ELIMINATED", "The match goes on without you.", UIPalette.DANGER)
		return
	_respawn_clock = maxf(0.1, respawn_in)
	_show_banner("YOU DIED", "Back in %d" % ceili(_respawn_clock), UIPalette.DANGER)


func _on_local_respawn() -> void:
	_respawn_clock = 0.0
	_banner.visible = false
	_end_spectating()


# -------------------------------------------------------------- spectating ---

## The local Gub's own rig, which keeps the viewport even while its Gub is
## hidden. Null once the match has torn its Gubs down.
func _local_rig() -> GubCamera:
	var gub := MatchState.local_gub()
	if gub == null:
		return null
	return gub.get_node_or_null("CameraRig") as GubCamera


func _begin_spectating() -> void:
	var living := MatchState.living_gubs(Net.local_id())
	if living.is_empty():
		return
	_spectating = true
	_spectate_index = 0
	_apply_spectator()


func _end_spectating() -> void:
	_spectating = false
	var rig := _local_rig()
	if rig != null:
		rig.spectate(null)
	_spectate_label.visible = false


func _step_spectator(direction: int) -> void:
	var living := MatchState.living_gubs(Net.local_id())
	if living.is_empty():
		return
	_spectate_index = posmod(_spectate_index + direction, living.size())
	_apply_spectator()


## Point the rig at the current pick and say whose eyes we are borrowing. Called
## every frame while dead as well as on a keypress, because the target can die
## or respawn without the player touching anything.
func _apply_spectator() -> void:
	if not _spectating:
		return
	var living := MatchState.living_gubs(Net.local_id())
	var rig := _local_rig()
	if living.is_empty() or rig == null:
		_spectate_label.visible = false
		if rig != null:
			rig.spectate(null)
		return
	_spectate_index = posmod(_spectate_index, living.size())
	var target := living[_spectate_index]
	rig.spectate(target)
	_spectate_label.text = "Spectating %s      LMB / RMB to switch" % target.display_name
	_spectate_label.visible = true


## Out of lives, in a mode that has them. The distinction matters: a dead Gub is
## back in three seconds and an eliminated one is done, and telling someone
## "respawning in 3" when they are not is worse than saying nothing.
func _is_eliminated() -> bool:
	return Net.config.win_condition == MatchConfig.WinCondition.LIVES \
		and MatchState.lives_left(Net.local_id()) <= 0


func _on_match_finished(summary: Dictionary) -> void:
	_banner.visible = false
	_scoreboard.close()
	_pause.close()
	_end_spectating()
	# The gameplay HUD goes away entirely rather than being dimmed behind the
	# scrim. A crosshair, a live ability bar and a counting clock over a table of
	# final scores read as a match still in progress, and the ability bar sat
	# directly behind the button people are meant to press next. `_process` keeps
	# it hidden for as long as the results are up.
	_root.visible = false
	_results.show_summary(summary)


func _on_left_lobby(reason: Net.Leave, message: String) -> void:
	var described := UIState.describe_leave(reason, message)
	# A deliberate walk-out has nothing to explain; anything else does.
	if not String(described["body"]).is_empty():
		UIState.post_notice(String(described["title"]), String(described["body"]))
	SceneFlow.clear_cursor_holds()
	SceneFlow.go_to_menu()


func _on_leave_match() -> void:
	# Announced, so `MatchState` hears `left_lobby` and tears the match down.
	# `_on_left_lobby` above does the navigating.
	Net.leave_lobby(Net.Leave.LOCAL_REQUEST, "", true)


## The host ends the match for the whole lobby; a client only moves itself.
##
## `Net.request_return_to_lobby` broadcasts, and everyone — the host included —
## arrives back here through `_go_to_lobby`. A client pressing the same button
## just walks itself home and stays connected, so leaving a results screen never
## needs the host's cooperation.
func _on_back_to_lobby() -> void:
	if Net.is_host:
		Net.request_return_to_lobby()
	else:
		_go_to_lobby()


func _go_to_lobby() -> void:
	MatchState.reset()
	if Net.is_host:
		# Otherwise the lobby keeps refusing joiners with "that match has
		# already started" for the rest of the session.
		Net.match_running = false
	SceneFlow.clear_cursor_holds()
	SceneFlow.go_to_lobby()


## Host only; the button is not shown to anyone else.
func _on_rematch_pressed() -> void:
	Net.request_rematch()


## Same roster, same settings, same island. Reloading the arena scene is what
## re-runs `register_arena`, and on the host that is what starts a fresh warmup
## and spawns everybody again — so a rematch is a scene change, not a special
## case inside `MatchState`.
func _on_rematch() -> void:
	MatchState.reset()
	SceneFlow.clear_cursor_holds()
	SceneFlow.go_to_arena()


func _show_banner(title: String, subtitle: String, colour: Color) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", colour)
	_banner_sub.text = subtitle
	_banner.visible = true
