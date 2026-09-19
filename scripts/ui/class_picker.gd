class_name ClassPicker
extends Control
## The mid-match weapon picker — "change class" — reached from the pause menu
## and from the death screen.
##
## **The same request the lobby strip sends, into a host that answers it
## differently.** There is no second channel and no second piece of state: this
## calls `Net.set_weapon`, exactly as `Lobby._on_weapon_chosen` does, and the
## host decides off `match_running` whether that means a weapon now or a weapon
## queued for the asker's next spawn (see `Net._request_weapon`). Everything on
## this screen is drawn off the roster row that comes back, so what it shows is
## always what the host actually believes rather than what this machine asked
## for a moment ago.
##
## **It never changes the weapon in your hands**, which is the one promise the
## screen has to make and the reason the caption is as loud as the buttons. A
## player who opens this mid-fight, picks a bow and finds a spear still in their
## fist has not found a bug; a player who is not told so in advance has.
##
## Built in code from `Loadout`, like the lobby's strip and for its reason: the
## three weapons' names, blurbs and props live in one place, and a second hand-
## authored strip would be a second place to forget one.

## Emitted whichever way this closes, so the HUD can put the cursor back exactly
## as it found it.
signal closed()

## Its own named hold, so closing this over a pause menu that is still open
## leaves *that* menu's hold in place and does not hand the mouse back to a game
## the player is still standing in a menu over.
const CURSOR_REASON := "class_picker"

## The prop above each name, at the size the lobby's strip uses. Same number on
## purpose: this is the same choice in a smaller room, and two sizes of the same
## picture would read as two different controls.
const ICON := 56

@onready var _strip: HBoxContainer = %Strip
@onready var _blurb: Label = %Blurb
@onready var _pending: Label = %Pending
@onready var _close_button: Button = %CloseButton

## True while `_rebuild` is writing the buttons, so the `pressed` signals it
## causes are not read back as picks. The lobby's strip needs the same guard for
## the same reason.
var _writing: bool = false


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	# Every pick this sends comes back as a roster broadcast, and so does every
	# *other* player's — harmless, and the redraw is three buttons.
	Net.roster_changed.connect(_on_roster_changed)


func open() -> void:
	if visible:
		return
	visible = true
	_rebuild()
	SceneFlow.release_cursor(CURSOR_REASON)
	_focus_pick()


func close() -> void:
	if not visible:
		return
	visible = false
	SceneFlow.recapture_cursor(CURSOR_REASON)
	closed.emit()


func _on_roster_changed() -> void:
	if visible:
		_rebuild()


## Draw the three buttons, the blurb and the line that says what is queued.
##
## Rebuilt rather than updated, like the lobby's, so there is one code path and
## no partial one.
func _rebuild() -> void:
	_writing = true
	var had_focus := false
	for child in _strip.get_children():
		had_focus = had_focus or child.has_focus()
		_strip.remove_child(child)
		child.queue_free()

	var me := Net.local_id()
	var held := Net.player_weapon(me)
	var queued := Net.pending_weapon(me)
	# What the next life will be carrying: the queued pick if there is one, and
	# otherwise what this life is carrying. That is what the strip marks as
	# chosen — this screen is about the next Bog, not this one, and lighting the
	# button for the spear you are still holding while a bow is queued would
	# contradict the caption underneath it.
	var chosen := queued if queued != Net.NO_PENDING else held

	for weapon: int in Loadout.all():
		var button := Button.new()
		button.text = Loadout.NAMES[weapon].to_upper()
		button.icon = AbilitySlot.art_for_weapon(weapon)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", ICON)
		button.add_theme_constant_override("h_separation", 10)
		button.custom_minimum_size = Vector2(196, ICON + 16)
		button.toggle_mode = true
		button.button_pressed = weapon == chosen
		button.pressed.connect(_on_chosen.bind(weapon))
		# **Pressing picks; focus does not** — unlike the lobby strip, where
		# arrowing onto a button also picks because the ring behind it is a live
		# preview and a preview of something that had not happened would be a
		# lie. There is nothing to preview here: the consequence is a Bog that
		# does not exist yet, and a request per focus event would mean a player
		# arrowing across to read the third blurb had quietly queued the second.
		button.focus_entered.connect(_on_focused.bind(weapon))
		_strip.add_child(button)

	_blurb.text = Loadout.blurb(chosen)
	_pending.text = _describe(held, queued)
	if had_focus:
		_focus_pick()
	_writing = false


## The line under the strip, which is the whole of what this screen has to
## explain. Three states, and each says the *next* thing that will happen rather
## than naming a rule.
func _describe(held: int, queued: int) -> String:
	if queued == Net.NO_PENDING:
		return "Carrying the %s. Pick another and you will respawn with it." \
			% Loadout.weapon_name(held).to_lower()
	return "Carrying the %s. You will respawn with the %s." \
		% [Loadout.weapon_name(held).to_lower(),
			Loadout.weapon_name(queued).to_lower()]


func _focus_pick() -> void:
	for child in _strip.get_children():
		var button := child as Button
		if button != null and button.button_pressed:
			button.grab_focus()
			return


## Reading the blurb is free; only a press costs a packet.
func _on_focused(weapon: int) -> void:
	if _writing:
		return
	_blurb.text = Loadout.blurb(weapon)


## Ask, unless the rebuild is talking to itself.
##
## Nothing is filtered out here the way the lobby's strip filters a pick that
## matches the roster, and one case is why: pressing the weapon you are *already
## carrying* is how a queued change is called off, and the host is the thing
## that knows that (`Net._request_weapon` clears the queue when the request and
## the held weapon agree). Swallowing it locally would leave a player who
## changed their mind with no way back.
func _on_chosen(weapon: int) -> void:
	if _writing:
		return
	Net.set_weapon(weapon)
