class_name MatchSettingsPanel
extends PanelContainer
## The host's match dials, and everyone else's read-only view of them (PLAN 1.4,
## 1.6). One panel serves both: clients get exactly the same rows with every
## control disabled, so what the host is choosing is never a mystery to the
## people waiting on it.
##
## Every edit goes straight out through `Net.update_config`, which is
## host-authoritative and rebroadcasts the whole config. This panel therefore
## never holds state of its own — it renders `Net.config` and asks for changes.
## The alternative, editing a local copy and pushing it on "Apply", means the
## lobby can show a setting nobody else has, which is precisely the confusion a
## shared config exists to prevent.
##
## Rows are generated from a table rather than authored, for the same reason the
## settings panel generates its own: a dozen rows of label-control-readout is a
## dozen chances to forget a theme variation.

## Rows that only make sense under some configurations. Hiding them beats
## disabling them: a greyed-out "Friendly fire" in a free-for-all invites the
## question of what it would do, and there is no good answer.
const TEAM_ONLY := ["team_count", "random_teams", "friendly_fire"]

@onready var _rows_root: VBoxContainer = %Rows
@onready var _summary: Label = %Summary
@onready var _host_only_hint: Label = %HostOnlyHint

## Built in code, so it cannot be reached through `%` — nodes added at runtime
## have no owner to register a unique name with.
var _seed_button: Button
## The Capture G·U·B section's heading, separator and rules note, hidden with its
## rows when another condition is picked (D-051).
var _capture_section: Array[Control] = []
var _capture_note: Label

## field name -> {"row": Control, "control": Control, "readout": Label}
var _fields: Dictionary = {}
## Set while widgets are being written from `Net.config`, so the change signals
## that causes do not bounce straight back out as edits.
var _applying: bool = false


func _ready() -> void:
	_build()
	Net.config_changed.connect(refresh)
	Net.roster_changed.connect(refresh)
	refresh()


func _build() -> void:
	_section("Mode")
	_choice("mode", "Match type", ["Free-for-all", "Teams"])
	_choice("team_count", "Teams", ["2", "3", "4", "5", "6", "7", "8"], 2)
	# Directly under the count it deals into, and hidden with it outside Teams.
	# Dealt at Start, not now — see `Net.request_match_start` (D-048).
	_toggle("random_teams", "Random teams")
	# In `MatchConfig.WinCondition` order, because `_choice` converts by index.
	# Appending here is the other half of never reordering that enum.
	_choice("win_condition", "Ends on",
		["First to the kill limit", "Last Gub standing", "The clock",
			"First to collect G·U·B", "Capture G·U·B (teams)"])

	_section("Limits")
	_slider("kill_limit", "Kill limit", 1, 50, 1, func(v: float) -> String:
		return "%d" % int(v))
	_slider("lives", "Lives each", 1, 15, 1, func(v: float) -> String:
		return "%d" % int(v))
	_slider("time_limit", "Time limit", 0, 1800, 30, func(v: float) -> String:
		return "No limit" if v <= 0.0 else UIPalette.clock(v))
	# Shown only under the letters condition, like the kill limit and the lives
	# count above it. It is also the dial most likely to be wrong out of the box
	# — see the note on `MatchConfig.letter_drop_chance` — so it is deliberately
	# in front of the host rather than buried under "Feel".
	_slider("letter_drop_chance", "Letter drop chance", 0.0, 1.0, 0.01,
		func(v: float) -> String: return "%d%% of deaths" % roundi(v * 100.0))
	# Beside the drop chance and under the same condition, because the two are
	# one balance question: how many cards there are, and what it costs to keep
	# one. Zero reads as "Instant" rather than as "0.0 s" — it is a real setting
	# (the mode without the hold), not a slider someone has dragged off the end.
	_slider("letter_hold_time", "Letter hold", 0.0, 30.0, 0.5,
		func(v: float) -> String:
			return "Instant" if v <= 0.0 else "%.1f s" % v)
	# Not under the letters condition, and that is the point of where it sits:
	# the Elder rolls out of the same corpse in every mode (D-038), so its dial
	# is above the `friendly_fire` toggle with the other rules that always
	# apply, rather than in the pair of rows `_apply_visibility` hides.
	_slider("elder_drop_chance", "Elder robe chance", 0.0, 1.0, 0.01,
		func(v: float) -> String: return "%d%% of deaths" % roundi(v * 100.0))
	_toggle("friendly_fire", "Friendly fire")

	# Capture G·U·B's own rules (D-051), a section of their own rather than rows
	# tucked into Limits, and shown only when that condition is picked: they
	# describe a different game, and a host reading "Dropped letter returns"
	# under a kill-limit match would be reading about rules that do not exist.
	_capture_section = _section("Capture G·U·B")
	# How long a dead carrier's card lies where it fell before going home. The
	# one number that decides what killing a carrier is worth.
	_slider("capture_return_time", "Dropped letter returns", 3.0, 60.0, 1.0,
		func(v: float) -> String: return "after %d s" % roundi(v))
	# As a percentage off the base speed, like the Elder's boost, because "-10%"
	# is a sentence about the game and "0.9" is a number about the code.
	_slider("capture_carrier_speed", "Carrier speed", 0.5, 1.2, 0.05,
		func(v: float) -> String:
			var percent := roundi((v - 1.0) * 100.0)
			return "normal" if percent == 0 else "%+d%%" % percent)
	# The rules that are not dials, said once in the panel rather than learned
	# the hard way in a match.
	_capture_note = _note("Three letters. Carry one into your team's ring to bank "
		+ "it; it goes back to the middle. A carrier cannot throw. A dead carrier "
		+ "drops the card for anyone to take. Bank G, U and B to win.")
	_capture_note.name = "CaptureRules"

	_section("Feel")
	# The single most important balance dial in the game: spears always kill, so
	# the recharge is what decides how punishing a miss is.
	_slider("spear_recharge", "Spear recharge", 0.5, 15.0, 0.1, func(v: float) -> String:
		return "%.1f s" % v)
	# Directly under the spear's recharge, because the two are one question: how
	# often anybody can commit to an attack — and since D-040 the Elder's is the
	# *shorter* of the two, which is exactly the sort of thing a host should
	# discover by reading one row under the other rather than in a match.
	_slider("lightning_cooldown", "Lightning recharge", 0.2, 10.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	# The four Elder dials that are not the drop chance, kept together and in
	# the order they are met: how long the bolt takes to come out, how long the
	# robe lasts, and the two boosts. They are in "Feel" rather than beside the
	# robe chance up in "Limits" because none of them changes how *often* an
	# Elder happens — only what one is like — and because this is the feature
	# most likely to want tuning the moment real people meet it (D-040).
	#
	# Zero reads as "Instant", the same word `letter_hold_time` and
	# `respawn_delay` use for the same thing: a real setting rather than a
	# slider dragged off the end.
	_slider("lightning_delay", "Lightning delay", 0.0, 2.0, 0.05,
		func(v: float) -> String:
			return "Instant" if v <= 0.0 else "%.2f s" % v)
	_slider("elder_duration", "Elder lasts", 1.0, 120.0, 1.0,
		func(v: float) -> String: return "%d s" % roundi(v))
	# Shown as a percentage over the base speed rather than as the bare
	# multiplier, because "+35%" is a sentence about the game and "1.35" is a
	# number about the code.
	_slider("elder_speed_multiplier", "Elder speed", 1.0, 3.0, 0.05,
		func(v: float) -> String: return "+%d%%" % roundi((v - 1.0) * 100.0))
	# And the jump is shown as the height it actually reaches, because the
	# multiplier is on launch velocity and height goes as its square: +25% on
	# this slider is +56% of apex, and a host reading "+25%" would be tuning the
	# wrong number. 1.69 m at 1.0, and asked of `Gub` rather than worked out
	# here, so a UI file cannot end up quoting an apex the physics stopped
	# producing.
	_slider("elder_jump_multiplier", "Elder jump", 1.0, 3.0, 0.05,
		func(v: float) -> String:
			return "%.2f m high" % Gub.apex_for(Gub.JUMP_VELOCITY * v))
	_slider("respawn_delay", "Respawn delay", 0.0, 10.0, 0.5, func(v: float) -> String:
		return "Instant" if v <= 0.0 else "%.1f s" % v)
	# Not cooldowns. Mushrooms and lures are carried stock now (D-032) and these
	# only decide how fast a stack can be emptied — which is why they are
	# seconds and not tens of seconds.
	_slider("mushroom_use_delay", "Mushroom delay", 0.1, 10.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	_slider("lure_use_delay", "Lure delay", 0.1, 10.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	_slider("max_players", "Lobby size", MatchConfig.MIN_PLAYERS, MatchConfig.MAX_PLAYERS,
		1, func(v: float) -> String: return "%d Gubs" % int(v))

	_section("Map")
	_map_row()
	_seed_row()


# --------------------------------------------------------------- refreshing ---

## Pull everything from `Net.config`. Called on load, on every broadcast from
## the host, and whenever the roster changes (the lobby-size floor moves with
## the number of people already in the room).
func refresh() -> void:
	_applying = true
	var config := Net.config
	for field: String in _fields:
		_write_field(field, config)
	_apply_visibility(config)
	_apply_editability()
	_summary.text = config.summary()
	_applying = false


func _write_field(field: String, config: MatchConfig) -> void:
	var entry: Dictionary = _fields[field]
	var control: Control = entry["control"]
	var value: Variant = config.get(field)
	if control is OptionButton:
		var picker := control as OptionButton
		# Most pickers stand for an int (an enum, or a count with an offset).
		# The map picker stands for a string id, so it carries the id list that
		# pairs with its items and is selected by lookup instead of arithmetic.
		var ids: Array[String] = entry.get("ids", [] as Array[String])
		if ids.is_empty():
			picker.selected = clampi(int(value) - int(entry.get("offset", 0)),
				0, picker.item_count - 1)
		else:
			# An id this build does not have would be a config that skipped
			# `_clamp_all`; show the first map rather than nothing selected.
			picker.selected = maxi(0, ids.find(String(value)))
	elif control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))
	elif control is HSlider:
		var slider := control as HSlider
		if field == "max_players":
			# Never offer a lobby size smaller than the number of people
			# already standing in it.
			slider.min_value = maxf(float(MatchConfig.MIN_PLAYERS),
				float(Net.player_count()))
		slider.set_value_no_signal(float(value))
		_write_readout(field, slider.value)
	elif control is Label:
		(control as Label).text = str(value)


func _write_readout(field: String, value: float) -> void:
	var entry: Dictionary = _fields[field]
	var readout: Label = entry.get("readout")
	if readout == null:
		return
	var formatter: Callable = entry["format"]
	readout.text = formatter.call(value)


## Show only the rows this configuration can act on.
func _apply_visibility(config: MatchConfig) -> void:
	var teams := config.mode == MatchConfig.Mode.TEAMS
	for field: String in TEAM_ONLY:
		_fields[field]["row"].visible = teams
	_fields["kill_limit"]["row"].visible = \
		config.win_condition == MatchConfig.WinCondition.KILL_LIMIT
	_fields["lives"]["row"].visible = \
		config.win_condition == MatchConfig.WinCondition.LIVES
	_fields["letter_drop_chance"]["row"].visible = \
		config.win_condition == MatchConfig.WinCondition.LETTERS
	_fields["letter_hold_time"]["row"].visible = \
		config.win_condition == MatchConfig.WinCondition.LETTERS
	var capture := config.win_condition == MatchConfig.WinCondition.CAPTURE
	for node: Control in _capture_section:
		node.visible = capture
	_capture_note.visible = capture
	_fields["capture_return_time"]["row"].visible = capture
	_fields["capture_carrier_speed"]["row"].visible = capture
	# A seed only means something to a map that is grown from one. On a static
	# map the row would offer to reroll an island nobody is going to see.
	_fields["map_seed"]["row"].visible = MapCatalog.is_procedural(config.map)


func _apply_editability() -> void:
	var editable := Net.is_host
	for field: String in _fields:
		var control: Control = _fields[field]["control"]
		if control is BaseButton:
			(control as BaseButton).disabled = not editable
		elif control is HSlider:
			(control as HSlider).editable = editable
	if _seed_button != null:
		_seed_button.disabled = not editable
	_host_only_hint.visible = not editable


# ------------------------------------------------------------------ editing ---

## Copy the current config, change one field, and push the whole thing. Sending
## the whole config rather than a delta is what `Net.update_config` expects, and
## with thirty primitives it is a few hundred bytes.
func _push(field: String, value: Variant) -> void:
	if _applying or not Net.is_host:
		return
	var next := Net.config.duplicate_config()
	next.set(field, value)
	# Capture G·U·B is teams-only, and `MatchConfig._clamp_all` turns Teams on
	# whenever it is picked (D-051). That clamp cannot tell which of the two was
	# just changed, so the other direction is decided here, where it can: a host
	# who picks Free-for-all while Capture is selected gets a free-for-all, on
	# the kill limit, rather than a picker that snaps back to Teams.
	if field == "mode" and int(value) == MatchConfig.Mode.FREE_FOR_ALL \
			and next.win_condition == MatchConfig.WinCondition.CAPTURE:
		next.win_condition = MatchConfig.WinCondition.KILL_LIMIT
	Net.update_config(next)


# --------------------------------------------------------------------- rows ---

## Returns the nodes it added, so a section that only applies sometimes can be
## hidden whole.
func _section(title: String) -> Array[Control]:
	var added: Array[Control] = []
	if _rows_root.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		_rows_root.add_child(gap)
		added.append(gap)
	var label := Label.new()
	label.theme_type_variation = "SectionLabel"
	label.text = title.to_upper()
	_rows_root.add_child(label)
	added.append(label)
	var line := HSeparator.new()
	_rows_root.add_child(line)
	added.append(line)
	return added


## A line of small print under a section's rows.
func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200
	_rows_root.add_child(label)
	return label


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 28
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = "DimLabel"
	label.custom_minimum_size.x = 168
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_rows_root.add_child(row)
	return row


func _slider(field: String, label_text: String, low: float, high: float, step: float,
		formatter: Callable) -> void:
	var row := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 18
	row.add_child(slider)

	var readout := Label.new()
	readout.theme_type_variation = "AccentLabel"
	readout.custom_minimum_size.x = 92
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(readout)

	_fields[field] = {"row": row, "control": slider, "readout": readout,
		"format": formatter}
	slider.value_changed.connect(func(value: float) -> void:
		_write_readout(field, value)
		# Ints on the wire for int fields: `MatchConfig.apply_dict` will coerce
		# either way, but sending 14.999999 for a kill limit is asking for it.
		_push(field, int(value) if step >= 1.0 and absf(step - roundf(step)) < 0.001
			else value))


func _choice(field: String, label_text: String, options: Array,
		offset: int = 0) -> void:
	var row := _row(label_text)
	var picker := OptionButton.new()
	for i in options.size():
		picker.add_item(String(options[i]), i)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	_fields[field] = {"row": row, "control": picker, "offset": offset,
		"format": func(_v: float) -> String: return ""}
	picker.item_selected.connect(func(index: int) -> void:
		_push(field, index + offset))


func _toggle(field: String, label_text: String) -> void:
	var row := _row(label_text)
	var toggle := CheckButton.new()
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(toggle)
	_fields[field] = {"row": row, "control": toggle,
		"format": func(_v: float) -> String: return ""}
	toggle.toggled.connect(func(on: bool) -> void: _push(field, on))


## Which map the match is played on. Above the seed row because it decides
## whether the seed row is there at all.
##
## The picker deals in indices and the config deals in ids, and `MapCatalog`
## keeps `ids()` and `display_names()` in the same order so the two can be
## converted by position. It is not built from an enum for the reason
## `MapCatalog` exists: a map's id has to survive being sent to a peer that may
## not have the same list, and an ordinal does not.
func _map_row() -> void:
	var row := _row("Map")
	# The one generated row with a name. The panel scrolls and this row is below
	# the fold at every window size the game ships at, so `tools/ui_range.gd`
	# has to be able to scroll to it to photograph it — and a row that nothing
	# can find is a row no screenshot check will ever cover.
	row.name = "MapRow"
	var picker := OptionButton.new()
	var names := MapCatalog.display_names()
	for i in names.size():
		picker.add_item(names[i], i)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)

	_fields["map"] = {"row": row, "control": picker, "ids": MapCatalog.ids(),
		"format": func(_v: float) -> String: return ""}
	picker.item_selected.connect(func(index: int) -> void:
		var ids := MapCatalog.ids()
		if index >= 0 and index < ids.size():
			_push("map", ids[index]))


## The island is generated from this number and every client builds the same map
## from it (D-007), so it is worth showing rather than hiding: "we all got a bad
## map" and "reroll it" are the same conversation. Hidden entirely on a map that
## is not generated — see `_apply_visibility`.
func _seed_row() -> void:
	var row := _row("Island seed")
	# Named for the same reason `MapRow` is, and for one more: this row's
	# *absence* is a feature, and "the seed row is hidden on a static map" is
	# not a claim anything can check about a row it cannot find.
	# `tools/playthrough.gd` checks it on both maps.
	row.name = "MapSeedRow"
	var value := Label.new()
	value.theme_type_variation = "AccentLabel"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	var button := Button.new()
	button.theme_type_variation = "GhostButton"
	button.text = "Reroll"
	row.add_child(button)
	_seed_button = button

	_fields["map_seed"] = {"row": row, "control": value,
		"format": func(_v: float) -> String: return ""}
	button.pressed.connect(func() -> void:
		_push("map_seed", randi_range(1, 99999999)))
