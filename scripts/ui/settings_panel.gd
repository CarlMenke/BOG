class_name SettingsPanel
extends Control
## The settings overlay (PLAN 6.4). One scene, opened from the main menu and
## from the pause menu, so the two can never drift apart.
##
## The rows are built in code rather than authored as thirty nodes: every one of
## them is the same shape — a label, a control, a live readout — and as scene
## nodes that is thirty places to forget a theme variation. The scene holds the
## frame (scrim, card, header, footer); this holds the list.
##
## Every control writes straight through to `Settings`, which persists on each
## change and emits `changed`. Nothing here caches: the panel is a view onto
## `Settings`, and closing it is not a "save".

signal closed()

## Quality presets are applied here, on the viewport, rather than by writing
## project settings: these are per-machine display choices, and a viewport
## property can be turned back down again the moment the player changes their
## mind. Fields are MSAA, screen-space AA, and the 3D render scale.
const QUALITY_PRESETS := [
	{"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED, "scale": 0.77},
	{"msaa": Viewport.MSAA_2X, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA, "scale": 1.0},
	{"msaa": Viewport.MSAA_4X, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA, "scale": 1.0},
]

## The rows of the Controls section: what to call it, and the action it moves.
## Order is the order a new player needs them in.
##
## D-016 built this as a reference page — a list you read and could not change —
## and the key-binding round makes every row of it a button. The list itself is
## unchanged by that except at the top: **Move is four rows now**, because one
## row saying "W / Up" could be read but could not be clicked, and a player who
## wants their movement on the arrow keys wants four different keys rather than
## one of them four times.
##
## Every action here is in `Settings.REBINDABLE`, which is the side of the pair
## that decides; `_bind_row` says so out loud if a row is ever added to only one.
const CONTROL_REFERENCE: Array[Array] = [
	["Move forward", "move_forward"],
	["Move back", "move_back"],
	["Move left", "move_left"],
	["Move right", "move_right"],
	["Sprint", "sprint"],
	["Crouch / slide", "crouch"],
	["Jump", "jump"],
	# **One line for all three weapons, because there is one button** (D-070).
	# D-069 put three here — one per weapon, in the picker's order — on the
	# argument that a player who came looking for their own weapon's key should
	# not find somebody else's. That was the right fix for three actions and the
	# wrong shape for the problem, which was that a player has one weapon and had
	# to learn three keys to find out. There is one key now, and the caption says
	# what it does for all three rather than naming a weapon this player may not
	# have brought.
	["Attack", "primary_attack"],
	# The one key a player would not find on their own: it takes a weapon *away*
	# rather than using one, and nothing on screen invites a press. The tile's
	# cap says H once the weapon is down; this is where you find out it is H
	# before you have put it down (the feel round).
	["Put weapon away", "holster"],
	["Aim", "aim"],
	["Plant shield", "place_shield"],
	["Throw magnet", "throw_magnet"],
	# Between the things you do with a weapon and the things you do with the
	# screen, because it is both: it is pressed from a death screen, and what it
	# changes is what you are holding when you come back.
	["Change class", "change_class"],
	["Emote", "emote"],
	["Respawn", "respawn"],
	["Scoreboard", "scoreboard"],
	["Chat", "chat"],
	["Pause", "pause"],
]

const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "Left Mouse",
	MOUSE_BUTTON_RIGHT: "Right Mouse",
	MOUSE_BUTTON_MIDDLE: "Middle Mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}

## The same buttons for a key cap sixty pixels wide. "Left Mouse" spills out of
## an ability slot and "LMB" is what everyone calls it anyway.
const MOUSE_BUTTON_CAPS := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "WH+",
	MOUSE_BUTTON_WHEEL_DOWN: "WH-",
}

## The face of an armed row. A prompt rather than a blank, because a row that
## went empty when you clicked it reads as a row that broke.
const ARMED_PROMPT := "PRESS A KEY…"

@onready var _sections: VBoxContainer = %Sections
@onready var _done: Button = %DoneButton
@onready var _reset: Button = %ResetButton
@onready var _close: Button = %CloseButton

## Rebuilt rows would lose the slider being dragged, so readouts are refreshed
## in place. key -> the Label showing the current value.
var _readouts: Dictionary = {}

## The Controls rows, in the order they were built: `{button, actions}`. Kept as
## a list rather than keyed by action because a row *is* the unit here — it is
## what gets armed, what gets redrawn, and one day what holds two actions.
var _bind_rows: Array[Dictionary] = []

## Which row is listening for a key, or -1 for none. At most one: arming a
## second row disarms the first, so there is never a press two rows both want.
var _armed: int = -1


func _ready() -> void:
	visible = false
	# Off until a row is armed. `_input` sees every event in the game, including
	# the ones aimed at the Bog, and a panel that is not waiting for a key has no
	# business being in that path.
	set_process_input(false)
	_build()
	_done.pressed.connect(close)
	_close.pressed.connect(close)
	_reset.pressed.connect(_restore_defaults)
	Settings.changed.connect(_on_setting_changed)
	apply_quality(int(Settings.get_value("quality")))


func open() -> void:
	visible = true
	_refresh_all()
	# Grab focus so the panel owns the keyboard: without this, Escape and the
	# arrow keys still reach whatever opened it.
	_done.grab_focus()


func close() -> void:
	if not visible:
		return
	# An armed row that survives the close would keep swallowing every key in
	# the game, which is the worst bug this feature can have: a panel nobody can
	# see eating the jump button.
	_cancel_arm()
	visible = false
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	# Swallowed rather than left to propagate, so closing settings from inside
	# the pause menu does not also close the pause menu behind it.
	if visible and event.is_action_pressed("pause"):
		accept_event()
		close()


# ------------------------------------------------------------------- rows ---

func _build() -> void:
	_section("Input")
	_slider_row("Mouse sensitivity", "mouse_sensitivity", 0.05, 1.50, 0.01, "%.2f")
	_toggle_row("Invert vertical look", "invert_y")

	_section("View")
	_slider_row("Field of view", "fov", 60.0, 110.0, 1.0, "%.0f")
	_slider_row("Camera shake", "camera_shake", 0.0, 1.5, 0.05, "%d%%", 100.0)

	_section("Audio")
	_slider_row("Master", "volume_master", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider_row("Music", "volume_music", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider_row("Effects", "volume_sfx", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider_row("Ambience", "volume_ambience", 0.0, 1.0, 0.01, "%d%%", 100.0)

	_section("Video")
	_choice_row("Quality", "quality", ["Low", "Medium", "High"])
	_toggle_row("V-Sync", "vsync")
	_toggle_row("Fullscreen", "fullscreen")
	# The readout itself is `SceneFlow`'s child and watches the setting, so there
	# is nothing to apply here (D-148).
	_toggle_row("FPS counter", "show_fps")

	_section("Network")
	_text_row("Public address", "public_address", "name.at.ply.gg:41235")
	var net_note := Label.new()
	net_note.name = "PublicAddressNote"
	net_note.theme_type_variation = "TinyLabel"
	net_note.text = "Public address (playit.gg) — leave blank to use LAN/Tailscale.\nOnly the host needs one. The tunnel must be UDP, forwarding to local port %d." % Net.DEFAULT_PORT
	net_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sections.add_child(net_note)

	_section("Controls")
	for entry: Array in CONTROL_REFERENCE:
		var actions: Array[String] = [String(entry[1])]
		_bind_row(String(entry[0]), actions)
	var note := Label.new()
	note.theme_type_variation = "TinyLabel"
	# The note the reference page had said rebinding was not wired up. This one
	# says the two things a player cannot see: that the row is a button at all,
	# and that the way back from a bad choice is the same button.
	note.text = "Click a key to change it, then press the key or mouse button you want. Escape cancels. Right-click a key to put its default back."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sections.add_child(note)

	var reset_controls := Button.new()
	reset_controls.name = "ResetControls"
	reset_controls.text = "RESET CONTROLS"
	reset_controls.theme_type_variation = "GhostButton"
	reset_controls.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_sections.add_child(reset_controls)
	reset_controls.pressed.connect(func() -> void:
		_cancel_arm()
		Settings.reset_all_keybinds()
		_refresh_binds())


func _section(title: String) -> void:
	if _sections.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 18
		_sections.add_child(gap)
	var label := Label.new()
	label.theme_type_variation = "SectionLabel"
	label.text = title.to_upper()
	_sections.add_child(label)
	_sections.add_child(HSeparator.new())


## Every row is the same three-column shape, so alignment holds down the whole
## panel without a single hand-set margin.
func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size.y = 34
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = "DimLabel"
	label.custom_minimum_size.x = 230
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_sections.add_child(row)
	return row


func _slider_row(label_text: String, key: String, low: float, high: float,
		step: float, format: String, display_scale: float = 1.0) -> void:
	var row := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(Settings.get_value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 18
	row.add_child(slider)

	var readout := Label.new()
	readout.theme_type_variation = "AccentLabel"
	readout.custom_minimum_size.x = 66
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(readout)
	readout.set_meta("format", format)
	readout.set_meta("scale", display_scale)
	_readouts[key] = readout
	_write_readout(key, slider.value)

	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_value(key, value)
		_write_readout(key, value))


func _toggle_row(label_text: String, key: String) -> void:
	var row := _row(label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(Settings.get_value(key))
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(toggle)
	_readouts[key] = toggle
	toggle.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		# Vsync and fullscreen only take effect when something applies them.
		if key == "vsync" or key == "fullscreen":
			Settings.apply_video())


func _choice_row(label_text: String, key: String, options: Array) -> void:
	var row := _row(label_text)
	var picker := OptionButton.new()
	for i in options.size():
		picker.add_item(String(options[i]), i)
	picker.selected = clampi(int(Settings.get_value(key)), 0, options.size() - 1)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	_readouts[key] = picker
	picker.item_selected.connect(func(index: int) -> void:
		Settings.set_value(key, index)
		if key == "quality":
			apply_quality(index))


## The only free-text row in the panel. It lives here rather than on the lobby
## screen because it is a property of this machine, not of a session: the person
## who hosts sets it once when they set up their tunnel and never looks at it
## again, which is exactly the life of a volume slider.
func _text_row(label_text: String, key: String, placeholder: String) -> void:
	var row := _row(label_text)
	var field := LineEdit.new()
	# Named so `tools/ui_range.gd` can put a plausible address in it for a
	# screenshot without going through `Settings` and persisting one.
	field.name = "PublicAddress"
	field.text = String(Settings.get_value(key))
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(field)
	_readouts[key] = field
	# Written on every keystroke, not on Enter or on focus loss. `Settings`
	# persists each change, and this panel is explicitly not a form with a save
	# button — a host who types an address and clicks Done would otherwise have
	# typed nothing at all, and would find out at the worst possible moment.
	field.text_changed.connect(func(value: String) -> void:
		Settings.set_value(key, value))


## One rebindable row: the name on the left, and where the reference page had a
## label, a button whose face is the key the action is on.
##
## Flat and `GhostButton`, which is the theme's Button variation at SmallLabel's
## size and SmallLabel's grey with a hover that brightens — so the row still
## reads as the label it replaced until the pointer touches it, and no third
## shade of grey had to be invented for it.
##
## `actions` is a list because a row is a statement about a *key*, not about an
## action. Nothing needs two of them yet; the day a row does — aim and zoom, say
## — it takes one press and binds both, rather than asking a player to press the
## same key twice and work out which one took.
func _bind_row(label_text: String, actions: Array[String]) -> void:
	for action: String in actions:
		if not Settings.is_rebindable(action):
			push_warning("SettingsPanel: %s has a row but is not in Settings.REBINDABLE" % action)
	var row := _row(label_text)
	var button := Button.new()
	button.flat = true
	button.theme_type_variation = "GhostButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "Click to set a new key. Right-click for the default."
	row.add_child(button)

	var index := _bind_rows.size()
	_bind_rows.append({"button": button, "actions": actions})
	button.pressed.connect(func() -> void: _arm(index))
	# Right-click is the undo, and it has to be caught before the Button decides
	# it is not interested: `pressed` is the left button only.
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is not InputEventMouseButton:
			return
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
			return
		button.accept_event()
		_cancel_arm()
		for action: String in actions:
			Settings.reset_keybind(action)
		_refresh_binds())
	_write_bind(index)


# -------------------------------------------------------------- binding ---

## Listen for the next press, on this row and no other.
func _arm(index: int) -> void:
	if _armed == index:
		return
	var previous := _armed
	_armed = index
	set_process_input(true)
	if previous >= 0:
		_write_bind(previous)
	_write_bind(index)


## Stop listening, changing nothing. Escape, a close, a reset, or another row.
func _cancel_arm() -> void:
	if _armed < 0:
		return
	var index := _armed
	_armed = -1
	set_process_input(false)
	_write_bind(index)


## The press that arrives while a row is armed.
##
## Read in `_input` rather than `_gui_input` because the interesting keys are
## exactly the ones the GUI would have eaten first — Escape closes this panel,
## Tab moves focus, Space presses the focused button — and because a bind has to
## be recordable whether or not the pointer is over the row. Everything that
## reaches here while armed is marked handled for the same reason: the press is
## a *choice of key*, not a use of it, and nothing downstream should act on it.
func _input(event: InputEvent) -> void:
	if _armed < 0 or not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		# Escape is the way out of an arm, so Escape is the one key that cannot
		# be bound. That is the trade every game makes here, and it is the right
		# way round: a player who binds their cancel key away has no cancel key.
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			_cancel_arm()
			return
		var bound := InputEventKey.new()
		# Physical, the way `project.godot` stores every key and for the reason
		# `describe_event` gives below: what a player chose is the place on the
		# keyboard their finger was, not the letter their layout prints there.
		bound.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE \
			else key.keycode
		_take_binding(bound)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed:
			return
		get_viewport().set_input_as_handled()
		var bound := InputEventMouseButton.new()
		bound.button_index = click.button_index
		_take_binding(bound)


## Give the armed row this press, and take the press off anything else that had
## it.
##
## **One key, one meaning** — the rule `tools/hud_range.gd`'s `controls` mode
## checks, and the reason it exists is D-070, where two actions quietly shared R
## for two decision records. A player who puts Jump on E is not asking to throw
## a magnet at the same time; they are asking for E to mean Jump, and the magnet
## row goes to "-" where they can see it and give it somewhere else.
func _take_binding(event: InputEvent) -> void:
	var index := _armed
	_armed = -1
	set_process_input(false)
	var row: Dictionary = _bind_rows[index]
	var actions: Array = row["actions"]

	for other: String in Settings.REBINDABLE:
		if actions.has(other):
			continue
		var kept: Array[InputEvent] = []
		var taken := false
		for existing: InputEvent in InputMap.action_get_events(other):
			if Settings.same_binding(existing, event):
				taken = true
			else:
				kept.append(existing)
		if taken:
			Settings.rebind(other, kept)

	# One event, not an added one: a row shows one key and has to *be* one key,
	# or the second press would be a key the row never admitted to. The arrow
	# keys the movement actions come with are the visible cost of that, and
	# RESET CONTROLS is how they come back.
	var one: Array[InputEvent] = [event]
	for action: String in actions:
		Settings.rebind(action, one)

	var button: Button = row["button"]
	# Focus would otherwise sit on the row we just bound, and the next press of
	# the key that arms a button — Space, Enter — would arm it all over again.
	button.release_focus()
	_refresh_binds()


## What one row's button says: the keys its action is on, or the prompt while it
## is waiting for a press.
func _write_bind(index: int) -> void:
	var row: Dictionary = _bind_rows[index]
	var button: Button = row["button"]
	if index == _armed:
		button.text = ARMED_PROMPT
		return
	var actions: Array = row["actions"]
	button.text = describe_action(String(actions[0]))


## Every row, because one rebind can move two of them.
func _refresh_binds() -> void:
	for index in _bind_rows.size():
		_write_bind(index)


# --------------------------------------------------------------- refreshing ---

func _write_readout(key: String, value: float) -> void:
	var readout := _readouts.get(key) as Label
	if readout == null:
		return
	var scaled := value * float(readout.get_meta("scale", 1.0))
	var format := String(readout.get_meta("format", "%.2f"))
	readout.text = format % (int(round(scaled)) if format.contains("%d") else scaled)


func _refresh_all() -> void:
	for key: String in _readouts:
		_sync_control(key)
	_refresh_binds()


func _on_setting_changed(key: String, _value: Variant) -> void:
	# The binds are not one control with one readout: a single rebind moves the
	# row that took the key and the row that lost it, so the whole list answers.
	# Answered while hidden too — this is the one setting something else can
	# change (a reset from anywhere), and the rows are cheap.
	if key == "keybinds":
		_refresh_binds()
		return
	if visible:
		_sync_control(key)


## Push a value from `Settings` back into whatever control shows it. Needed
## because "Reset to defaults" changes eleven settings at once and every one of
## them has a widget still displaying the old number.
func _sync_control(key: String) -> void:
	var node: Variant = _readouts.get(key)
	var value: Variant = Settings.get_value(key)
	if node is LineEdit:
		# Only when it actually differs. Assigning `text` moves the caret to the
		# end, so writing it back on every `changed` would fight the person
		# typing into it — this control is the one thing here that emits the
		# signal it also listens to.
		var field := node as LineEdit
		if field.text != String(value):
			field.text = String(value)
	elif node is CheckButton:
		(node as CheckButton).set_pressed_no_signal(bool(value))
	elif node is OptionButton:
		(node as OptionButton).selected = int(value)
	elif node is Label:
		_write_readout(key, float(value))
		# The slider is the readout's left-hand sibling; find it rather than
		# keeping a second dictionary of the same rows.
		var row := (node as Label).get_parent()
		for child in row.get_children():
			if child is HSlider:
				(child as HSlider).set_value_no_signal(float(value))


func _restore_defaults() -> void:
	for key: String in Settings.DEFAULTS:
		# Identity and the host's tunnel address are not display settings;
		# wiping something someone typed because they nudged a volume slider
		# would be its own bug. The field is right there if they want it gone.
		if key in ["player_name", "last_invite_code", "public_address"]:
			continue
		# The binds go back through their own call, below. Writing the default
		# here would hand `Settings` the constant dictionary itself to hold and
		# to save, and would leave the live `InputMap` still on the old keys.
		if key == "keybinds":
			continue
		Settings.set_value(key, Settings.DEFAULTS[key])
	Settings.reset_all_keybinds()
	Settings.apply_video()
	apply_quality(int(Settings.get_value("quality")))
	_refresh_all()


# ----------------------------------------------------------------- quality ---

## Apply a preset to the current viewport. Public because the pause menu and the
## menu both open this panel, and whichever one is first should still leave the
## renderer matching what the player last chose.
func apply_quality(level: int) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var preset: Dictionary = QUALITY_PRESETS[clampi(level, 0, QUALITY_PRESETS.size() - 1)]
	viewport.msaa_3d = preset["msaa"]
	viewport.screen_space_aa = preset["ssaa"]
	viewport.scaling_3d_scale = preset["scale"]


# ------------------------------------------------------------------ helpers ---

## The keys and buttons bound to an action, as something readable. Used by the
## settings reference and by the HUD, which labels each ability slot with the
## key that fires it rather than hard-coding "Q" and hoping.
static func describe_action(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var names: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var text := describe_event(event)
		if not text.is_empty() and not names.has(text):
			names.append(text)
	return " / ".join(names) if not names.is_empty() else "-"


## The shortest label for one binding. Keys are reported by *physical* code, the
## way the input map stores them, so a WASD binding still says W on a keyboard
## whose layout would otherwise make it Z.
static func describe_event(event: InputEvent, short: bool = false) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		# The headless display server does not implement this, and every build of
		# a settings panel or a chat panel therefore printed a stack trace — which
		# was most of the noise in every automated log, from three different
		# screens. Headless has no keyboard layout to translate for anyway, so the
		# physical code *is* the answer there.
		if DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(code)
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		var button := (event as InputEventMouseButton).button_index
		var table: Dictionary = MOUSE_BUTTON_CAPS if short else MOUSE_BUTTON_NAMES
		return table.get(button, "Mouse %d" % button)
	if event is InputEventJoypadButton:
		return "Pad %d" % (event as InputEventJoypadButton).button_index
	return ""


## The first binding only, abbreviated, for a HUD key cap where there is room
## for about three characters.
static func primary_key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		var text := describe_event(event, true)
		if not text.is_empty():
			return text
	return "?"
