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

## Pressed when the host wants this panel out of the way. The lobby owns the
## answer; this only asks (see `set_folded`).
signal fold_requested

## Rows that only make sense under some configurations. Hiding them beats
## disabling them: a greyed-out "Friendly fire" in a free-for-all invites the
## question of what it would do, and there is no good answer.
const TEAM_ONLY := ["team_count", "random_teams", "friendly_fire"]

@onready var _rows_root: VBoxContainer = %Rows
@onready var _summary: Label = %Summary
@onready var _host_only_hint: Label = %HostOnlyHint
## Opens the capture sheet (D-076). In the heading rather than at the foot of
## the rows, because the rows scroll and a button that is below the fold at every
## window size the game ships at is a button nobody finds. **Not host-only**,
## and it stays that way even though the whole panel is now hidden from clients
## in the lobby: this scene is instanced elsewhere, and the day a client is
## given a read-only view of the config again, the thing they most want from it
## is to write down what they played on. Only `APPLY`, on a saved row, is
## host-only.
@onready var _capture_button: Button = %CaptureButton
## Asks the lobby to fold this panel down to its heading. **Asks**: the boolean
## lives in `lobby.gd` and comes back through `set_folded` below, because that
## file's single `_refresh` is the only thing allowed to write `visible` on a
## panel in the stack (D-069).
@onready var _fold_button: Button = %FoldButton
@onready var _scroll: ScrollContainer = %Scroll

## Built in code, so it cannot be reached through `%` — nodes added at runtime
## have no owner to register a unique name with.
var _seed_button: Button
## The Capture B·O·G section's heading, separator and rules note, hidden with its
## rows when another condition is picked (D-051).
var _capture_section: Array[Control] = []
var _capture_note: Label

## field name -> {"row": Control, "control": Control, "readout": Label}
var _fields: Dictionary = {}
## The heading the next row will be filed under, so a captured config can say
## which part of the panel a setting came from without a second table.
var _current_section: String = ""
## The capture sheet (D-076), built on first use and kept: it carries the name
## and the notes being typed, and rebuilding it on every open would throw those
## away every time the panel refreshed behind it.
var _sheet: CanvasLayer = null
var _sheet_name: LineEdit
var _sheet_notes: TextEdit
var _sheet_preview: TextEdit
var _sheet_saved: VBoxContainer
var _sheet_status: Label
## Set while widgets are being written from `Net.config`, so the change signals
## that causes do not bounce straight back out as edits.
var _applying: bool = false


func _ready() -> void:
	_build()
	_capture_button.pressed.connect(open_capture)
	_fold_button.pressed.connect(fold_requested.emit)
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
		["First to the kill limit", "Last Bog standing", "The clock",
			"First to collect B·O·G", "Capture B·O·G (teams)"])

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
	# Beside the robe's chance and in the same words, because they are the same
	# kind of row: both are named shares taken off the top of one drop table, and
	# reading them together is the only way to see what is left for the shield
	# and the magnet (D-067).
	_slider("potion_drop_chance", "Heal potion chance", 0.0, 1.0, 0.01,
		func(v: float) -> String: return "%d%% of deaths" % roundi(v * 100.0))
	_toggle("friendly_fire", "Friendly fire")

	# Capture B·O·G's own rules (D-051), a section of their own rather than rows
	# tucked into Limits, and shown only when that condition is picked: they
	# describe a different game, and a host reading "Dropped letter returns"
	# under a kill-limit match would be reading about rules that do not exist.
	_capture_section = _section("Capture B·O·G")
	# How long a dead carrier's card lies where it fell before going home. The
	# one number that decides what killing a carrier is worth.
	_slider("capture_return_time", "Dropped letter returns", 3.0, 60.0, 1.0,
		func(v: float) -> String: return "after %d s" % roundi(v))
	# How long a thief stands on an enemy vault before the card comes out of it.
	_slider("capture_steal_time", "Stealing a banked letter", 1.0, 5.0, 0.5,
		func(v: float) -> String: return "takes %.1f s" % v)
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
		+ "drops the card for anyone to take. Bank B, O and G to win.")
	_capture_note.name = "CaptureRules"

	_section("Feel")
	# The single most important balance dial in the game: spears always kill, so
	# the recharge is what decides how punishing a miss is.
	_slider("spear_recharge", "Spear recharge", 0.5, 15.0, 0.1, func(v: float) -> String:
		return "%.1f s" % v)
	# The bow's eight, under the spear's recharge and above the Elder's, because
	# that is the order a player meets the three weapons in and because the row
	# that matters most here is the one right under `spear_recharge`: how long a
	# full draw takes against how long a spear takes to come back is the whole
	# of how the two weapons trade (D-065).
	#
	# The four pairs are read as pairs — a snap shot and a full draw — so every
	# one of them shows both ends in one row rather than as two sliders a host
	# has to hold in their head at once.
	_slider("bow_draw_time", "Full draw takes", 0.2, 4.0, 0.05,
		func(v: float) -> String: return "%.2f s" % v)
	_slider("bow_recharge", "Bow recharge", 0.2, 15.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	# Damage as a fraction of a Bog rather than as a bare number, because "80"
	# means nothing without knowing that a Bog is 100 — and the two numbers a
	# host is actually tuning against are `Nameplate`'s bands at 50 and 25
	# (D-062).
	_slider("bow_damage_snap", "Snap shot hits for", 1.0, 100.0, 1.0,
		func(v: float) -> String:
			return "%d  (%d%% of a Bog)" % [roundi(v), roundi(v / Bog.MAX_HEALTH * 100.0)])
	_slider("bow_damage_full", "Full draw hits for", 1.0, 100.0, 1.0,
		func(v: float) -> String:
			return "%d  (%d%% of a Bog)" % [roundi(v), roundi(v / Bog.MAX_HEALTH * 100.0)])
	# The four flight dials say what they *buy* as well as what they are: the
	# flat band is the distance inside which you point at a Bog and hit it
	# (`BogCombat.flat_band`), and it is the only reading of speed-against-drop
	# that a host can act on. It is also the number the Elder's own range is now
	# derived from, which is why the full draw's two rows say so.
	_slider("bow_speed_snap", "Snap shot speed", 5.0, 120.0, 1.0,
		func(v: float) -> String:
			return "%d m/s  ·  flat to %.0f m" % [roundi(v),
				BogCombat.flat_band(v, Net.config.bow_drop_snap)])
	_slider("bow_drop_snap", "Snap shot drop", 0.5, 40.0, 0.5,
		func(v: float) -> String:
			return "%.1f m/s²  ·  flat to %.0f m" % [v,
				BogCombat.flat_band(Net.config.bow_speed_snap, v)])
	_slider("bow_speed_full", "Full draw speed", 5.0, 120.0, 1.0,
		func(v: float) -> String:
			return "%d m/s  ·  flat to %.0f m" % [roundi(v),
				BogCombat.flat_band(v, Net.config.bow_drop_full)])
	_slider("bow_drop_full", "Full draw drop", 0.5, 40.0, 0.5,
		func(v: float) -> String:
			return "%.1f m/s²  ·  flat to %.0f m  (and the bolt with it)" % [v,
				BogCombat.flat_band(Net.config.bow_speed_full, v)])
	# The great sword's two, under the bow's eight and above the Elder's, because
	# that is the order a player meets the four weapons in — and because the row
	# that matters is again the one against `spear_recharge`: what a sword trades
	# is a guaranteed kill for having to be *there*, and how often it can be
	# asked for against how often a spear can is the whole of that trade (D-068).
	#
	# There are only two of them because there is nothing else to tune. The
	# damage is a whole Bog by construction and the sweep's shape is a fact about
	# the weapon rather than a setting (`BogCombat.SWORD_ARC`).
	_slider("sword_reach", "Great sword reaches", 0.5, 6.0, 0.01,
		func(v: float) -> String:
			# Said with the advance in it, because the dial on its own is not
			# the number a player experiences: the body covers
			# `Bog.SPIN_ADVANCE` during the swing, so what a host is really
			# dragging is where a swing can be *started* from.
			return "%.2f m  ·  %.2f m with the advance" % [v, v + Bog.SPIN_ADVANCE])
	_slider("sword_recharge", "Great sword recharge", 0.0, 10.0, 0.05,
		func(v: float) -> String:
			# And this one says what it buys, which is the chain: at the default
			# the next swing becomes available on the tick the last one's spin
			# ends, which is the one moment the momentum it built is still
			# there to be added to (D-052, D-068).
			var cycle := BogAnimator.SWING_RELEASE_TIME + v
			return "%.2f s  ·  a swing every %.2f s%s" % [v, cycle,
				"  (chains)" if cycle <= BogAnimator.SWING_SECONDS + 0.001 else ""])
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
	# Right after the delay, because the two are the whole of how forgiving the
	# bolt is: how long the target has to move, and how far off you can be and
	# still have it count (D-053). Zero reads as "Direct hit", which is what it
	# means — the blast is gone and only the ray kills.
	_slider("lightning_radius", "Lightning blast", 0.0, 4.0, 0.1,
		func(v: float) -> String:
			return "Direct hit" if v <= 0.0 else "%.1f m" % v)
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
	# wrong number. 1.69 m at 1.0, and asked of `Bog` rather than worked out
	# here, so a UI file cannot end up quoting an apex the physics stopped
	# producing.
	_slider("elder_jump_multiplier", "Elder jump", 1.0, 3.0, 0.05,
		func(v: float) -> String:
			return "%.2f m high" % Bog.apex_for(Bog.JUMP_VELOCITY * v))
	_slider("respawn_delay", "Respawn delay", 0.0, 10.0, 0.5, func(v: float) -> String:
		return "Instant" if v <= 0.0 else "%.1f s" % v)
	# Not cooldowns. Shields and magnets are carried stock now (D-032) and these
	# only decide how fast a stack can be emptied — which is why they are
	# seconds and not tens of seconds.
	_slider("shield_use_delay", "Shield delay", 0.1, 10.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	_slider("magnet_use_delay", "Magnet delay", 0.1, 10.0, 0.1,
		func(v: float) -> String: return "%.1f s" % v)
	# The potion's two, under the other carried stock. It has no use-delay row to
	# sit beside them, and that is deliberate: the channel *is* the floor on how
	# fast a stack can be emptied, and a second dial that also gated it would be
	# two answers to one question (D-067).
	#
	# The heal is said as a fraction of a Bog rather than as "40", because what
	# a player wants to know is how much of one this is worth and `Bog.MAX_HEALTH`
	# is the unit everything in this game is written in (D-062).
	_slider("heal_amount", "Potion heals", 5.0, 100.0, 5.0,
		func(v: float) -> String:
			return "%d (%d%% of a Bog)" % [roundi(v),
				roundi(100.0 * v / Bog.MAX_HEALTH)])
	_slider("heal_channel", "Drinking takes", 0.5, 6.0, 0.1,
		func(v: float) -> String: return "%.1f s standing still" % v)
	_slider("max_players", "Lobby size", MatchConfig.MIN_PLAYERS, MatchConfig.MAX_PLAYERS,
		1, func(v: float) -> String: return "%d Bogs" % int(v))

	_section("Map")
	_map_row()
	_seed_row()


## Every slider row in the panel, as `{"field", "label", "slider", "readout",
## "format", "row"}`. Public because `tools/ui_range.gd` measures this panel
## rather than eyeballing it: a readout wide enough to squeeze the slider beside
## it to nothing is a setting the host cannot change, and that is arithmetic on
## two rectangles rather than something a screenshot proves. See the `widths`
## mode there and D-076.
func slider_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for field: String in _fields:
		var entry: Dictionary = _fields[field]
		if not (entry["control"] is HSlider):
			continue
		out.append({
			"field": field,
			"label": entry["label"] as Label,
			"slider": entry["control"] as HSlider,
			"readout": entry["readout"] as Label,
			"format": entry["format"] as Callable,
			"row": entry["row"] as Control,
		})
	return out


# ------------------------------------------------------ capturing a config ---
#
# D-076, on the user's own *"there should be some way to capture a settings
# config from the menu... and i can put in some notes about that. Ideally there
# is also a copy to clipboard button that copied everything."*
#
# **The clipboard payload is the feature.** The reason to want this is to hand a
# config to a playtester or to write down what a match was actually played on,
# and both of those end in a chat window — so the text is written to be read
# there by a person, in a proportional font, and not to be parsed. One line per
# setting, each line saying what it is and what it is set to, under the panel's
# own headings.
#
# **Built from `MatchConfig.fields()`, never from a list written here.** That is
# what travels on the wire, so a field missing from a capture is a setting the
# person you sent it to would never see. Eight of those fields have no row in
# this panel — `spawn_protection`, `warmup_time`, the shield's lifetime and
# cap, the magnet's four — and they are captured anyway, under their own heading,
# because "capture all the settings" means all of them and a dial that is not on
# the panel is exactly the one somebody would otherwise forget.

## What the transcript calls the fields this panel has no row for.
const UNLISTED_SECTION := "Not on the panel"


## Every field of the config, in wire order, as `{field, section, label, value}`.
## The one place that decides what a captured config *is*; the transcript below
## and `tools/ui_range.gd -- capture_config` both read it, so the check and the
## clipboard cannot disagree about what was left out.
func capture_rows() -> Array[Dictionary]:
	var config := Net.config
	var out: Array[Dictionary] = []
	for field: String in MatchConfig.fields():
		var entry: Dictionary = _fields.get(field, {})
		var label: String = _pretty(field)
		var section: String = UNLISTED_SECTION
		if not entry.is_empty():
			var node: Label = entry.get("label")
			if node != null:
				label = node.text
			section = String(entry.get("section", UNLISTED_SECTION))
		out.append({
			"field": field,
			"section": section,
			"label": label,
			"value": _capture_value(field, entry, config),
		})
	return out


## What one field reads as. The panel's own words wherever the panel has them —
## a slider's formatter already says "80  (80% of a Bog)" and "a swing every
## 1.47 s  (chains)", which is the whole reason those formatters exist and is far
## better than the float underneath. A field with no row falls back to the value.
func _capture_value(field: String, entry: Dictionary, config: MatchConfig) -> String:
	var raw: Variant = config.get(field)
	if entry.is_empty():
		return _plain(raw)
	var control: Control = entry["control"]
	if control is HSlider:
		var formatter: Callable = entry["format"]
		return String(formatter.call(float(raw)))
	if control is OptionButton:
		var picker := control as OptionButton
		if picker.selected >= 0:
			return picker.get_item_text(picker.selected)
		return _plain(raw)
	if control is CheckButton:
		return "on" if bool(raw) else "off"
	return _plain(raw)


static func _plain(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return "%.2f" % float(value)
	if typeof(value) == TYPE_BOOL:
		return "on" if bool(value) else "off"
	return str(value)


## `spawn_protection` becomes `Spawn protection`, for the eight fields with no
## row of their own to take a label from.
static func _pretty(field: String) -> String:
	var words := field.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


## The thing that goes on the clipboard.
func transcript(title: String, notes: String) -> String:
	var rows := capture_rows()
	var lines: Array[String] = []
	var named := title.strip_edges()
	lines.append("BOG match config — %s" % (named if not named.is_empty()
		else "unnamed"))
	lines.append(Net.config.summary())
	var said := notes.strip_edges()
	if not said.is_empty():
		# Indented under "Notes:" rather than run together, so a note with its
		# own line breaks in it still reads as one block of somebody's words.
		lines.append("")
		lines.append("Notes:")
		for line: String in said.split("\n"):
			lines.append("  " + line)
	# Grouped by the panel's own headings, in the order the headings first come
	# up, and in wire order *inside* each one. Nothing is dropped and nothing is
	# invented — this is a sort, not a filter — but it matters: `_FIELDS` is
	# ordered by when a feature landed rather than by where its dials are, so
	# printed straight it walks MODE, LIMITS, MODE, FEEL, LIMITS, FEEL and reads
	# like a changelog instead of like a config.
	var order: Array[String] = []
	var grouped := {}
	for row: Dictionary in rows:
		var section := String(row["section"])
		if not grouped.has(section):
			grouped[section] = [] as Array[String]
			order.append(section)
		grouped[section].append("  %s: %s" % [row["label"], row["value"]])
	for section: String in order:
		lines.append("")
		lines.append(section.to_upper())
		lines.append_array(grouped[section] as Array[String])
	lines.append("")
	lines.append("(%d settings, captured %s)" % [rows.size(),
		Time.get_datetime_string_from_system(false, true)])
	return "\n".join(lines)


# --------------------------------------------------------------- the sheet ---

## Open the capture sheet, building it the first time.
##
## On its own `CanvasLayer` rather than as a child Control, and that is the only
## structural decision in here: this panel lives inside the lobby's
## `PanelStack`, with the chat panel as a *later* sibling, so a full-screen
## overlay parented to it in the ordinary way would be drawn underneath the chat
## it is supposed to be covering. A `CanvasLayer` is above everything below its
## own layer wherever it is hung, which means this panel can own a modal without
## knowing a thing about the screen it is sitting on.
func open_capture() -> void:
	if _sheet == null:
		_build_sheet()
	_refresh_sheet()
	_sheet.visible = true
	_sheet_name.grab_focus()


func close_capture() -> void:
	if _sheet != null:
		_sheet.visible = false


func _build_sheet() -> void:
	_sheet = CanvasLayer.new()
	_sheet.layer = 10
	add_child(_sheet)

	var scrim := PanelContainer.new()
	scrim.theme_type_variation = "ScrimPanel"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# **The theme has to be handed over by hand here**, and it is the price of the
	# `CanvasLayer` above. A `Control` finds its theme by walking up its *Control*
	# ancestors, and a `CanvasLayer` is a plain `Node` — so everything under this
	# layer has no Control parent, falls through to Godot's own default theme, and
	# comes out as grey engine boxes in the middle of a game that has a theme.
	# There is no project-wide default to catch it (this project sets the theme on
	# each screen's root), which is exactly why it showed up as nothing rather
	# than as something slightly wrong.
	scrim.theme = _inherited_theme(self)
	_sheet.add_child(scrim)

	var centre := CenterContainer.new()
	scrim.add_child(centre)

	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(740, 660)
	centre.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UIPalette.GAP)
	card.add_child(body)

	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := Label.new()
	title.theme_type_variation = "LeadLabel"
	title.text = "Capture this config"
	heading.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	_sheet_status = Label.new()
	_sheet_status.name = "CaptureStatus"
	_sheet_status.theme_type_variation = "TinyLabel"
	heading.add_child(_sheet_status)

	body.add_child(_sheet_caption("NAME"))
	_sheet_name = LineEdit.new()
	_sheet_name.name = "CaptureName"
	_sheet_name.placeholder_text = "What is this one?"
	_sheet_name.text_changed.connect(func(_text: String) -> void: _refresh_preview())
	body.add_child(_sheet_name)

	body.add_child(_sheet_caption("NOTES"))
	_sheet_notes = TextEdit.new()
	_sheet_notes.name = "CaptureNotes"
	_sheet_notes.placeholder_text = "Why, and what you were trying to find out."
	_sheet_notes.custom_minimum_size.y = 74
	_sheet_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_sheet_notes.text_changed.connect(_refresh_preview)
	body.add_child(_sheet_notes)

	# The payload, on screen, before it goes anywhere. Read-only and *exactly*
	# what the button copies — the whole risk with a copy button is that nobody
	# ever sees what came out of it, and a preview is one assignment away.
	body.add_child(_sheet_caption("WHAT GETS COPIED"))
	_sheet_preview = TextEdit.new()
	_sheet_preview.name = "CapturePreview"
	_sheet_preview.editable = false
	_sheet_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet_preview.custom_minimum_size.y = 196
	_sheet_preview.add_theme_font_size_override("font_size", UIPalette.FONT_TINY)
	body.add_child(_sheet_preview)

	body.add_child(_sheet_caption("SAVED THIS SESSION"))
	# Scrolled rather than free to grow: `UIState.MAX_CAPTURES` is eight, and
	# eight rows added to a card that already holds a preview would push the copy
	# button off the bottom of the screen — which is the one button on this sheet
	# that has to be reachable.
	var saved_scroll := ScrollContainer.new()
	saved_scroll.custom_minimum_size.y = 96
	saved_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(saved_scroll)
	_sheet_saved = VBoxContainer.new()
	_sheet_saved.name = "CaptureSaved"
	_sheet_saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_saved.add_theme_constant_override("separation", 4)
	saved_scroll.add_child(_sheet_saved)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UIPalette.GAP)
	actions.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(actions)

	var close := Button.new()
	close.theme_type_variation = "GhostButton"
	close.text = "CLOSE"
	close.pressed.connect(close_capture)
	actions.add_child(close)

	var save := Button.new()
	save.name = "CaptureSave"
	save.text = "SAVE FOR THIS SESSION"
	save.pressed.connect(_on_sheet_save)
	actions.add_child(save)

	var copy := Button.new()
	copy.name = "CaptureCopy"
	copy.theme_type_variation = "PrimaryButton"
	copy.text = "COPY TO CLIPBOARD"
	copy.pressed.connect(_on_sheet_copy)
	actions.add_child(copy)
	_sheet.visible = false


## The nearest theme above this panel. `Control.theme` is what a node was
## *given*, not what it resolves to, so this is the walk the engine would have
## done if the layer were a Control.
static func _inherited_theme(from: Control) -> Theme:
	var node: Node = from
	while node != null:
		var control := node as Control
		if control != null and control.theme != null:
			return control.theme
		node = node.get_parent()
	return null


static func _sheet_caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "SectionLabel"
	label.text = text
	return label


func _refresh_sheet() -> void:
	_refresh_preview()
	_rebuild_saved()


func _refresh_preview() -> void:
	if _sheet_preview == null:
		return
	_sheet_preview.text = transcript(_sheet_name.text, _sheet_notes.text)


func _rebuild_saved() -> void:
	for child in _sheet_saved.get_children():
		_sheet_saved.remove_child(child)
		child.queue_free()
	var saved := UIState.captured_configs()
	if saved.is_empty():
		var none := Label.new()
		none.theme_type_variation = "SmallLabel"
		none.text = "Nothing captured yet."
		_sheet_saved.add_child(none)
		return
	for capture: Dictionary in saved:
		_sheet_saved.add_child(_saved_row(capture))


func _saved_row(capture: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = "RowPanel"
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UIPalette.GAP)
	row.add_child(line)

	var name_label := Label.new()
	name_label.text = String(capture["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)

	var copy := Button.new()
	copy.theme_type_variation = "GhostButton"
	copy.text = "COPY"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(String(capture["text"]))
		_say("Copied %s." % capture["name"]))
	line.add_child(copy)

	# Applying a capture is one `Net.update_config` — the same call every slider
	# in this panel already makes — so it is here rather than not, per the step's
	# own "if applying one back is cheap, do it". A client gets the button
	# disabled, for the reason every other control in this panel is disabled for
	# them: the host owns the config.
	var apply := Button.new()
	apply.theme_type_variation = "GhostButton"
	apply.text = "APPLY"
	apply.disabled = not Net.is_host
	apply.pressed.connect(func() -> void:
		var next := MatchConfig.new()
		next.apply_dict(capture["config"])
		Net.update_config(next)
		_say("Applied %s." % capture["name"]))
	line.add_child(apply)
	return row


func _on_sheet_copy() -> void:
	DisplayServer.clipboard_set(transcript(_sheet_name.text, _sheet_notes.text))
	_say("Copied. Paste it anywhere.")


func _on_sheet_save() -> void:
	var named := _sheet_name.text.strip_edges()
	if named.is_empty():
		named = Net.config.summary()
	UIState.remember_config(named, _sheet_notes.text,
		transcript(named, _sheet_notes.text), Net.config.to_dict())
	_rebuild_saved()
	_say("Saved for this session.")


func _say(text: String) -> void:
	if _sheet_status != null:
		_sheet_status.text = text


## Show the panel, or show only its heading.
##
## **Pure application — this panel keeps no folded state of its own.** The
## lobby holds the boolean and calls this from its one `_refresh`, and the
## button above only emits a request. A panel that folded itself on its own
## button press would be exactly the second update path `lobby.gd`'s header
## forbids: a roster broadcast landing mid-fold would redraw one and not the
## other.
##
## Folding takes the panel's share of the stack away with it, and drops what is
## left to the bottom of the stack's box, where the other headings are. Left on
## `SIZE_EXPAND_FILL` a folded panel is a full-height glass box with three words
## at the top of it, which is worse than the panel it replaced; left on
## `SHRINK_BEGIN` it is a bar across the middle of the glade with nothing under
## it.
func set_folded(folded: bool) -> void:
	_summary.visible = not folded
	_scroll.visible = not folded
	_fold_button.text = "▸" if folded else "▾"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if folded \
		else Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_END if folded \
		else Control.SIZE_FILL


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
	# The sheet quotes the config, so a dial moved behind it has to move in the
	# preview too — otherwise the one thing on screen claiming to be what will be
	# copied is the one thing that is out of date.
	if _sheet != null and _sheet.visible:
		_refresh_preview()


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
	_fields["capture_steal_time"]["row"].visible = capture
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
	# Capture B·O·G is teams-only, and `MatchConfig._clamp_all` turns Teams on
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
	_current_section = title
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


## The one column measurement in this panel. Every row's name sits in it and
## every slider's unit is indented by it, so the names line up down the left
## edge and the units line up under the tracks.
const NAME_COLUMN := 168
const ROW_GAP := 14


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	row.custom_minimum_size.y = 28
	row.add_child(_name_label(label_text))
	row.set_meta("label", row.get_child(0))
	_rows_root.add_child(row)
	return row


func _name_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = "DimLabel"
	label.custom_minimum_size.x = NAME_COLUMN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A slider row is two lines, and that is the whole of D-076's slider fix.
##
## It used to be one: name, track, readout, left to right, with the track on
## `SIZE_EXPAND_FILL` and therefore holding whatever the other two left it. A
## `Label`'s minimum width is the width of its own text, so every unit string
## this panel learned to say came straight off the track — and they got longer
## with every step from D-062 on. At the worst label the panel currently has
## (`bow_drop_full`, "25.5 m/s²  ·  flat to 39 m  (and the bolt with it)") the
## track measured **zero pixels**: a grabber with nothing to slide along, a
## setting that could be read and not changed.
##
## So the unit goes **under** the track, indented to the track's own left edge,
## and the track takes the entire rest of the row. The readout is the only
## control in this panel that can be handed an arbitrarily long string, and down
## there it costs the slider nothing at all — it wraps instead of pushing, which
## is why `AUTOWRAP_WORD_SMART` is set rather than a minimum width: a label that
## cannot wrap has a minimum width, and a minimum width is how this bug works.
##
## Measured rather than eyeballed. `tools/ui_range.gd -- widths` puts every
## slider at the value that renders its own unit widest, in the real font, under
## every win condition, and fails the gate if any track is under `MIN_TRACK`.
func _slider(field: String, label_text: String, low: float, high: float, step: float,
		formatter: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_rows_root.add_child(row)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", ROW_GAP)
	top.custom_minimum_size.y = 26
	var label := _name_label(label_text)
	top.add_child(label)
	row.add_child(top)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 18
	top.add_child(slider)

	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", ROW_GAP)
	# A couple of pixels taller than the unit needs, so consecutive two-line rows
	# do not run into one another down a panel of forty of them.
	under.custom_minimum_size.y = 24
	row.add_child(under)
	# An empty control rather than a margin, so the indent is the *same* number
	# the name column is and cannot drift away from it.
	var indent := Control.new()
	indent.custom_minimum_size.x = NAME_COLUMN
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(indent)

	var readout := Label.new()
	readout.theme_type_variation = "ValueLabel"
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under.add_child(readout)

	_fields[field] = {"row": row, "control": slider, "readout": readout,
		"label": label, "section": _current_section, "format": formatter}
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
		"label": row.get_meta("label"), "section": _current_section,
		"format": func(_v: float) -> String: return ""}
	picker.item_selected.connect(func(index: int) -> void:
		_push(field, index + offset))


func _toggle(field: String, label_text: String) -> void:
	var row := _row(label_text)
	var toggle := CheckButton.new()
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(toggle)
	_fields[field] = {"row": row, "control": toggle,
		"label": row.get_meta("label"), "section": _current_section,
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
		"label": row.get_meta("label"), "section": _current_section,
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
		"label": row.get_meta("label"), "section": _current_section,
		"format": func(_v: float) -> String: return ""}
	button.pressed.connect(func() -> void:
		_push("map_seed", randi_range(1, 99999999)))
