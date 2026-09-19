extends Node
## Local, per-machine preferences. Never replicated — these are this player's
## own display/input/audio choices plus the name they last used.
##
## Autoloaded as `Settings`.

const CONFIG_PATH := "user://settings.cfg"

signal changed(key: String, value: Variant)

const DEFAULTS := {
	# identity
	"player_name": "",
	"last_invite_code": "",
	# The weapon last picked in a lobby, as a `Loadout.Weapon` ordinal (D-069).
	# Local like the name and for the same reason: it is what this machine asks
	# for when it next joins somewhere, and the roster the host keeps is the
	# only authority on what it actually got.
	"weapon": 0,
	# The skin last picked in a **free-for-all** lobby, as a `Skins` index.
	# The weapon's neighbour and for the weapon's reason. Free-for-all only:
	# a skin picked in Teams belongs to the team rather than to the player, so
	# carrying it to the next lobby would be carrying somebody else's shirt.
	"skin": 0,
	# network — the playit.gg tunnel address this machine hands out when it
	# hosts, as `host:port`. Blank means "use whatever interface I am on", which
	# is the LAN/Tailscale behaviour and the right default for everyone who is
	# not the host. See docs/DECISIONS.md D-028.
	"public_address": "",
	# input
	"mouse_sensitivity": 0.25,
	"invert_y": false,
	# Rebound controls: action name -> the events that action sits on, each
	# {"kind": "key", "physical": int} or {"kind": "mouse", "button": int}.
	# **The difference from `project.godot`, not a copy of it.** An action
	# nobody moved is absent, so the day a default key moves it moves for
	# everybody who never touched it, and a `settings.cfg` written by an older
	# build cannot pin a key to an action this one no longer has. One entry
	# rather than sixteen because `ConfigFile` stores a Dictionary whole and
	# because "what this player rebound" is one concern (D-098).
	"keybinds": {},
	# view
	"fov": 75.0,
	"camera_shake": 1.0,
	# audio (linear 0..1, converted to dB when applied)
	"volume_master": 0.9,
	"volume_music": 0.5,
	"volume_sfx": 1.0,
	"volume_ambience": 0.7,
	# video
	"quality": 2,  # 0 low, 1 medium, 2 high
	"vsync": true,
	"fullscreen": false,
	# The frame-rate readout in the top-left corner (D-148). A display choice
	# like the two above it, and off by default: it is a diagnostic somebody
	# turns on to answer a question, not part of what the game looks like.
	"show_fps": false,
	# tutorial — whether the B·O·G how-to-play cards have been through once on
	# this machine. Local rather than per-lobby and per-account, because what it
	# records is "this person has read it", and the person is the machine here:
	# the lobby pops the cards for a first B·O·G match and never again, and HOW
	# TO PLAY on the menu is how anybody asks for them back. "Reset to defaults"
	# clears it deliberately — somebody who resets their settings to show the
	# game to a friend gets the introduction with it.
	"tutorial_seen": false,
}

## Every action a player may put on a different key, in the order the settings
## panel lists them.
##
## **The permission lives here rather than in the panel** because it has to hold
## when no panel is on screen: `apply_keybinds` reads a file a player can open in
## a text editor, and "may this action be moved" has to have the same answer for
## a click and for a line somebody typed. `ui_*` is never on it — Godot's own
## actions are how a menu answers at all, and a player who rebound `ui_accept`
## would have locked themselves out of the panel they did it in. Nor are
## `emote`, `respawn` and `free_cursor`, which the panel does not list either:
## this list and that one say the same thing twice on purpose, and `_bind_row`
## warns if they ever stop agreeing.
const REBINDABLE: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right",
	"sprint", "crouch", "jump",
	"primary_attack", "holster", "aim",
	"place_shield", "throw_magnet", "drink_potion",
	"emote", "respawn",
	"scoreboard", "chat", "pause",
]

var _values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	load_from_disk()
	apply_video()
	# Last, and after the load: the binds are the one setting that changes a
	# global the rest of the game reads on its first frame, so the `InputMap` has
	# to be the player's before anything polls it or asks it for a key cap.
	apply_keybinds()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key, value)
	save_to_disk()


## A display name that is always safe to show above a Bog's head.
func sanitized_player_name() -> String:
	var raw := String(get_value("player_name")).strip_edges()
	if raw.is_empty():
		return "Bog"
	# Collapse whitespace and clamp length so nameplates stay readable.
	var collapsed := ""
	var last_was_space := false
	for c in raw:
		var is_space := c == " " or c == "\t"
		if is_space and last_was_space:
			continue
		collapsed += " " if is_space else c
		last_was_space = is_space
	return collapsed.substr(0, 16).strip_edges()


## The weapon this machine last picked, as a `Loadout.Weapon` (D-069).
##
## `sanitized_player_name`'s sibling, and written the same way round: the stored
## value is whatever was last saved, and this is the one place that turns it
## into something safe to hand to `Net`. A `settings.cfg` edited by hand — or
## written by a build that had a fourth weapon in it — comes back as a spear
## rather than as an index into nothing.
func chosen_weapon() -> int:
	return Loadout.sanitize(get_value("weapon"))


## The free-for-all skin this machine last picked, as a `Skins` index.
## `chosen_weapon`'s twin, sanitized here for the same reason: a `settings.cfg`
## written by a build with more skins in it comes back as the plain body rather
## than as an index into nothing.
func chosen_skin() -> int:
	return Skins.sanitize(get_value("skin"))


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for key: String in DEFAULTS:
		if cfg.has_section_key("settings", key):
			_values[key] = cfg.get_value("settings", key)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value("settings", key, _values[key])
	cfg.save(CONFIG_PATH)


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen")
		else DisplayServer.WINDOW_MODE_WINDOWED
	)


# ---------------------------------------------------------------- keybinds ---

## True for an action the player is allowed to move. Everything else — `ui_*`,
## `emote`, `respawn`, an action some hand-edited file invented — keeps the key
## `project.godot` gave it.
func is_rebindable(action: String) -> bool:
	return REBINDABLE.has(action)


## Put the saved binds on the live `InputMap`. Called once at startup and again
## after every change.
##
## It always starts from `load_from_project_settings`, because what is stored
## here is a *difference* and a difference can shrink: rebuilding the whole map
## from the bottom is the only way a removed override goes back to the key it
## came from. Cheap enough to do on every rebind — sixteen actions and a file
## already in memory.
func apply_keybinds() -> void:
	_apply_keybinds(get_value("keybinds"))


## Move `action` onto `events`. An empty array unbinds it, which is a thing a
## player can mean.
func rebind(action: String, events: Array[InputEvent]) -> bool:
	if not is_rebindable(action):
		push_warning("Settings: %s may not be rebound" % action)
		return false
	var saved := _keybinds_copy()
	var rows: Array = []
	for event: InputEvent in events:
		var row := _serialise_event(event)
		if not row.is_empty():
			rows.append(row)
	saved[action] = rows
	# The map first, then the save. `set_value` emits `changed`, and everything
	# listening for it answers by reading the live `InputMap` for a key cap;
	# emitting before the map moved would show every one of them the old key.
	_apply_keybinds(saved)
	set_value("keybinds", saved)
	return true


## Put one action back on the key `project.godot` gives it.
func reset_keybind(action: String) -> void:
	var saved := _keybinds_copy()
	if not saved.has(action):
		return
	saved.erase(action)
	_apply_keybinds(saved)
	set_value("keybinds", saved)


## Put every action back. Forgetting the overrides is the whole of it: the
## defaults were never copied anywhere, so there is nothing to restore from.
func reset_all_keybinds() -> void:
	var empty: Dictionary = {}
	_apply_keybinds(empty)
	set_value("keybinds", empty)


## Are these two events the same press? Field by field rather than `==`, which
## on two `InputEvent`s compares identity, and rather than comparing the
## serialised rows, which would tie "the same key" to how it happens to be
## written down.
static func same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var left := _physical_of(a as InputEventKey)
		return left != KEY_NONE and left == _physical_of(b as InputEventKey)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index \
			== (b as InputEventMouseButton).button_index
	return false


## The saved binds as something safe to change. Deep, because `set_value` is
## allowed to look at the value it already holds and decide nothing happened:
## handing it back the very dictionary it is holding is how a save goes missing.
func _keybinds_copy() -> Dictionary:
	var saved: Variant = get_value("keybinds")
	if saved is not Dictionary:
		return {}
	var copy: Dictionary = saved
	return copy.duplicate(true)


## Defaults, then overrides. Tolerant of every shape a hand-edited
## `settings.cfg` can be in, because the alternative to skipping a bad row is a
## game that will not start.
func _apply_keybinds(saved: Dictionary) -> void:
	InputMap.load_from_project_settings()
	for key: Variant in saved:
		var action := String(key)
		if not is_rebindable(action) or not InputMap.has_action(action):
			continue
		var raw: Variant = saved[key]
		if raw is not Array:
			continue
		var rows: Array = raw
		InputMap.action_erase_events(action)
		for row: Variant in rows:
			var event := _deserialise_event(row)
			if event != null:
				InputMap.action_add_event(action, event)


## One event as something `ConfigFile` can write. Keys go by *physical* code, the
## way `project.godot` stores them and for the reason `SettingsPanel`'s
## `describe_event` gives: a binding is a place on the keyboard, not the letter
## printed on it. A pad button serialises to nothing — the panel cannot record
## one and the map does not bind one, and a format with no way in is a format
## nobody can test.
static func _serialise_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var physical := _physical_of(event as InputEventKey)
		if physical == KEY_NONE:
			return {}
		return {"kind": "key", "physical": int(physical)}
	if event is InputEventMouseButton:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_NONE:
			return {}
		return {"kind": "mouse", "button": int(button)}
	return {}


## The inverse, or `null` for a row this build does not understand.
static func _deserialise_event(row: Variant) -> InputEvent:
	if row is not Dictionary:
		return null
	var data: Dictionary = row
	match String(data.get("kind", "")):
		"key":
			var physical := int(data.get("physical", 0))
			if physical == 0:
				return null
			var key := InputEventKey.new()
			key.physical_keycode = physical as Key
			return key
		"mouse":
			var button := int(data.get("button", 0))
			if button == 0:
				return null
			var click := InputEventMouseButton.new()
			click.button_index = button as MouseButton
			return click
	return null


## Where a key event is on the keyboard. Falls back to the layout code for an
## event carrying only that — nothing here writes one, but an imported
## `settings.cfg` might.
static func _physical_of(key: InputEventKey) -> Key:
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
