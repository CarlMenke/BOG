class_name ChatPanel
extends PanelContainer
## Lobby and in-match chat (PLAN 6.7). One scene, used in three places' worth of
## shapes, because the only thing that differs between them is **which half is
## put away when nobody is talking**:
##
##   plain           — heading, log and input, all of it, all the time.
##   `compact`       — in a match: the log is the overlay and the input appears
##                     when you press the chat key (the HUD drives it).
##   `reveal_on_focus` — in the lobby: the input is the whole panel and the
##                     heading and log appear while the caret is in it.
##
## The two flags are opposite halves of one idea and are never both set.
##
## The log is a single `RichTextLabel` rather than a list of `Label` nodes. It
## gets wrapping, scrollback, per-name colour and "stay pinned to the bottom
## unless the reader has scrolled up" for free, and a chat log is exactly the
## widget that was built for.
##
## Names are tinted with the same team colours the nameplates use, so the person
## who just said something and the Bog across the clearing are visibly the same
## player.

signal submitted(text: String)

## Long chats are trimmed rather than allowed to grow without bound: this runs
## for a whole session, and nobody scrolls back four hundred lines.
const MAX_LINES := 120

## In-match, chat is a quiet overlay that only takes the keyboard while you are
## actually typing.
@export var compact: bool = false

## In the lobby, the panel is **a line of input until somebody means to use
## it**: the heading and the log appear when the caret arrives and go away when
## it leaves. A lobby is read at a glance and a chat log nobody has written in
## is a tall empty box in the third of the screen the ring is standing in.
##
## The state is the **caret**, not a boolean this file keeps beside it. Focus is
## something the engine is already authoritative about — a click elsewhere, a
## Tab, a `release_focus` from anywhere — and a second copy of it here would be
## a copy that is wrong the first time somebody focuses the input by a route
## this file did not think of.
@export var reveal_on_focus: bool = false

@onready var _log: RichTextLabel = %Log
@onready var _input: LineEdit = %Input
@onready var _heading: Control = %Heading
@onready var _hint: Label = %Hint

var _lines: int = 0


func _ready() -> void:
	_input.text_submitted.connect(_on_submitted)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	if compact:
		_heading.visible = false
		theme_type_variation = &"HudPanel"
		set_input_visible(false)
	elif reveal_on_focus:
		_input.focus_entered.connect(_apply_reveal)
		_input.focus_exited.connect(_apply_reveal)
		_input.gui_input.connect(_on_input_gui_input)
		_apply_reveal()
	_hint.text = "%s to chat" % SettingsPanel.primary_key("chat")
	_update_compact_skin()


## Show or put away everything that is not the input box, from the one fact that
## decides it. Called on both focus signals and once on load, and it is the only
## place in this file that writes `visible` on the heading or the log.
func _apply_reveal() -> void:
	if not reveal_on_focus:
		return
	var open := _input.has_focus()
	_heading.visible = open
	_log.visible = open
	# The log is the only child carrying `SIZE_EXPAND_FILL`, so it is the only
	# reason this panel is ever tall. Hidden, a panel left on `SIZE_FILL` is a
	# full-height glass box with a line edit at the top of it — which is the
	# thing this mode exists to stop. Shrinking to the input is the other half
	# of hiding the log, so the two are written on adjacent lines.
	size_flags_vertical = Control.SIZE_FILL if open else Control.SIZE_SHRINK_BEGIN


## Escape puts the caret down; it does not leave the lobby.
##
## Taken on the `LineEdit` rather than in the lobby's `_unhandled_input`,
## because that is where the event is: a focused control sees a key press first,
## and if this did not accept it the lobby's own Escape handler would read
## somebody abandoning a half-typed message as somebody leaving the session.
func _on_input_gui_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	_input.accept_event()
	_input.release_focus()


# ------------------------------------------------------------------ writing ---

## A line from a player. `peer_id` is looked up rather than passed as a name so
## a rename between sending and receiving cannot produce two names for one Bog.
func add_message(peer_id: int, text: String) -> void:
	var team := Net.player_team(peer_id)
	var colour := UIPalette.team_colour(team) if Net.config.mode == MatchConfig.Mode.TEAMS \
		else (UIPalette.BOG if peer_id == Net.local_id() else UIPalette.TEXT)
	_append("[color=#%s]%s[/color]  %s" % [
		colour.to_html(false), _escape(Net.player_name(peer_id)), _escape(text)])


## Something the game itself is saying: a join, a leave, a match starting.
func add_system(text: String) -> void:
	_append("[color=#%s]%s[/color]" % [UIPalette.TEXT_FAINT.to_html(false), _escape(text)])


func _append(bbcode: String) -> void:
	if _lines > 0:
		_log.append_text("\n")
	_log.append_text(bbcode)
	_lines += 1
	_update_compact_skin()
	if _lines > MAX_LINES:
		# `RichTextLabel` can only drop whole lines from the front, which is
		# exactly the granularity wanted here.
		_log.remove_paragraph(0)
		_lines -= 1


## Player text is escaped before it reaches a BBCode-enabled label. Without
## this, anyone in the lobby can type `[img]` or a colour tag and rewrite the
## chat log for everybody.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


# ------------------------------------------------------------------- typing ---

func _on_submitted(text: String) -> void:
	var clean := text.strip_edges()
	_input.clear()
	if clean.is_empty():
		_close_after_send()
		return
	submitted.emit(clean)
	_close_after_send()


## Sending is the end of a typing session in both modes, and it is the same end:
## the in-match input puts itself away, and the lobby's puts the caret down,
## which folds the log away behind it. Anyone with more to say presses the key
## or clicks the box again, exactly as they did the first time.
func _close_after_send() -> void:
	if compact:
		set_input_visible(false)
	elif reveal_on_focus:
		_input.release_focus()


## In-match, the input box appears when the player presses the chat key and
## goes away again on send or on escape. It has to actually take focus, or the
## first few characters go to the game and the Bog jumps.
func set_input_visible(shown: bool) -> void:
	_input.visible = shown
	_hint.visible = compact and not shown
	_update_compact_skin()
	if shown:
		_input.grab_focus()
	else:
		_input.release_focus()


func is_typing() -> bool:
	return _input.visible and _input.has_focus()


## In-match, an empty chat box is a black rectangle in the corner of a game
## nobody has spoken in yet. The panel earns its background only once it has
## something in it, or once someone starts typing.
func _update_compact_skin() -> void:
	if not compact:
		return
	var earned := _lines > 0 or _input.visible
	if earned:
		remove_theme_stylebox_override("panel")
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _gui_input(event: InputEvent) -> void:
	if compact and _input.visible and event.is_action_pressed("pause"):
		accept_event()
		_input.clear()
		set_input_visible(false)
