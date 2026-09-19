extends Node3D
## The first screen anyone sees (PLAN 1.3): who you are, and the four ways out
## of here.
##
## The scene root is a `Node3D` rather than a `Control` because the menu is not
## a picture of the game, it is the game with a UI in front of it — a live
## `BogBackdrop` with a real Bog standing in a real glade, lit by the arena's
## own environment. Everything the player can touch lives on a `CanvasLayer`
## above it.
##
## Joining is deliberately a two-step reveal rather than a modal: pressing
## "Join with a code" opens a field directly inside the bar that opened it, so
## the eye never leaves the row it was already reading.
##
## The layout is one bar along the foot (D-118): the wordmark keeps the top-left
## corner and everything you can press lives in a single row at the bottom, name
## field at the left end and the six ways out of here centred in the rest of
## it. It is built in `main_menu.tscn` with anchors and containers; nothing here
## moves a control at runtime.
##
## **The wordmark is not a control any more.** "BOG" used to be a 148 px
## `Label` in the top-left; it is now three real letter cards floating over the
## campfire in the backdrop itself (`MenuLetters`), and the only thing left in
## that corner is the quip under them. So the top-left of this screen is the
## one part of it this file cannot move: it is three metres of glade away, and
## `BogBackdrop.FRAMING[HERO]` is where it is composed.

## Long enough to read, short enough that nobody wonders if it has hung. `Net`
## puts its own eight-second clock on the connection itself.
const CONNECT_HINT := "Connecting..."

## The one line under the wordmark, picked fresh every time this screen opens.
##
## It replaces "WHISPERBLOOM HOLLOW" and the yellow rule above it. A place name
## set in tracked caps is the furniture of a menu that wants to look like a
## menu, and it was saying something untrue as well: the hollow is one of seven
## maps and not the game. A joke told once is worth more than a subtitle told
## every time, and six of them means the screen is not quite the same screen
## twice — which is the cheapest possible reason to look at it again.
##
## Kept short enough to sit on one line under the wordmark at 1280 wide, and
## kept in the game's own voice: nobody in it is a hero. The wordmark it sits
## under is three floating letter cards now rather than a label, so the quip is
## anchored where they project (`BogBackdrop.FRAMING[HERO]` prints the box)
## instead of being stacked under a label in the same container.
const QUIPS: PackedStringArray = [
	"Throw first, apologise later.",
	"Nothing personal. Just spears.",
	"Two antennae. One bad idea.",
	"Friends are just targets that talk back.",
	"Mind the drop.",
	"Somebody has to fetch the spears.",
]

@onready var _backdrop: BogBackdrop = %Backdrop
@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _practice_button: Button = %PracticeButton
@onready var _how_to_play_button: Button = %HowToPlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _join_panel: Control = %JoinPanel
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _notice: PanelContainer = %Notice
@onready var _notice_title: Label = %NoticeTitle
@onready var _notice_body: Label = %NoticeBody
@onready var _settings: SettingsPanel = %Settings
@onready var _tutorial: Tutorial = %Tutorial
@onready var _version: Label = %Version
@onready var _quip: Label = %Quip

## True between pressing Host/Join and the session opening or failing, so the
## buttons can be locked without a second flag for each of them.
var _pending: bool = false

## Set for the one beat between pressing Practice and this screen being left, so
## that `_on_joined` does not send us to the lobby. See `_on_practice`.
var _practice_pending: bool = false


func _ready() -> void:
	# The menu is a mouse screen. Named, because the pause menu and the
	# scoreboard hold the cursor too and whoever lets go last must not hand
	# capture back to a game that is not running.
	SceneFlow.release_cursor("menu")

	# Arriving here with a session still open means something went wrong on the
	# way in, or the player backed out of a lobby. Either way this screen owns
	# no session, so close it before it can surprise anyone.
	if Net.in_session:
		Net.leave_lobby(Net.Leave.LOCAL_REQUEST, "", false)

	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	# Per open, not per build: the seed is Godot's global one, which is random
	# at startup, so a player who backs out of a lobby gets a different line on
	# the way back in. The scene ships with one of the six already in it so the
	# editor and any tool that never runs `_ready` still show a real line rather
	# than a blank row that silently changes the wordmark's height.
	_quip.text = QUIPS[randi() % QUIPS.size()]
	_name_edit.text = Settings.sanitized_player_name()
	_code_edit.text = String(Settings.get_value("last_invite_code"))
	_join_panel.visible = false
	_notice.visible = false
	_push_name_to_backdrop()

	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join_toggled)
	_practice_button.pressed.connect(_on_practice)
	# Straight to the panel's own `open`, the way SETTINGS is wired: the card
	# keeps its own state (which page, whether it has been seen before) and
	# this screen's only business with it is saying when to appear. It is on
	# the menu as well as in the lobby because the lobby is a place you arrive
	# at with five other people waiting, and reading six cards is not something
	# to do while they watch.
	_how_to_play_button.pressed.connect(_tutorial.open)
	_settings_button.pressed.connect(_settings.open)
	_quit_button.pressed.connect(_on_quit)
	_connect_button.pressed.connect(_on_connect)
	_code_edit.text_submitted.connect(func(_text: String) -> void: _on_connect())
	_name_edit.text_changed.connect(_on_name_typed)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)

	Net.joined_lobby.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)
	Net.left_lobby.connect(_on_left_lobby)

	# Whatever threw us back here gets the first word.
	var pending := UIState.take_notice()
	if not String(pending["body"]).is_empty():
		_show_notice(String(pending["title"]), String(pending["body"]))

	_host_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Escape backs out one layer at a time rather than doing nothing on a screen
	# that has no "back".
	if event.is_action_pressed("pause") and _join_panel.visible:
		_set_join_open(false)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ identity ---

func _on_name_typed(_text: String) -> void:
	_push_name_to_backdrop()


## Committed on submit and on losing focus rather than on every keystroke:
## `Settings.set_value` writes the file, and a disk write per character typed is
## a silly thing to do to someone's SSD.
func _commit_name() -> void:
	var clean := Net.sanitize_name(_name_edit.text)
	_name_edit.text = clean
	Net.set_name_local(clean)
	_push_name_to_backdrop()


## The Bog on screen wears the name in the box, live. It is the clearest
## possible answer to "is this field the name other people will see?"
##
## And the **skin this machine last picked for itself**: `Settings.chosen_skin`
## is the free-for-all pick, which is the only one that is this player's to keep
## — a team's skin belongs to the lobby it was chosen in. Nothing on this screen
## can change it; the picker is in the lobby, and this is where you find out what
## you are still wearing.
func _push_name_to_backdrop() -> void:
	var shown := Net.sanitize_name(_name_edit.text)
	_backdrop.set_roster([{"name": shown, "team": MatchConfig.TEAM_NONE,
		"skin": Settings.chosen_skin()}])


# -------------------------------------------------------------------- actions ---

func _on_host() -> void:
	if _pending:
		return
	_commit_name()
	_set_busy(true)
	_show_notice("Opening lobby", "Binding port %d..." % Net.DEFAULT_PORT)
	# `host_lobby` reports its own failure through `join_failed`, which this
	# screen is already listening to, so a bound port or a second copy of the
	# game running lands in the same notice as a bad invite code.
	if not Net.host_lobby():
		_set_busy(false)


func _on_join_toggled() -> void:
	_set_join_open(not _join_panel.visible)


func _set_join_open(open: bool) -> void:
	# No open/closed marker on the button: the field appearing directly beside
	# it is the affordance, and a bare glyph on the end of a label reads as a
	# typo. The bar's two flexible gaps absorb the width the field takes, so the
	# other four buttons slide rather than the row overflowing.
	_join_panel.visible = open
	if open:
		_code_edit.grab_focus()
		_code_edit.select_all()


func _on_connect() -> void:
	if _pending:
		return
	var code := _code_edit.text.strip_edges()
	if code.is_empty():
		_show_notice("No code", "Paste the code the host sent you.")
		return
	if not InviteCode.is_valid(code):
		# Checked here as well as inside `Net` so the player is told before a
		# socket is opened, and told what the shape of a code actually is.
		_show_notice("That code will not work",
			"An invite code looks like XXXXX-XXXXX.\nCheck for a missing character.")
		return
	_commit_name()
	Settings.set_value("last_invite_code", code)
	_set_busy(true)
	_show_notice(CONNECT_HINT, "Reaching the host at %s." % code.to_upper())
	if not Net.join_lobby(code):
		_set_busy(false)


## Straight into the practice range: no port, no code, no lobby (D-112).
##
## The third way out of this screen, and the only one that does not end at the
## lobby. Hosting binds a socket and asks the player to wait for someone;
## practice is a thing you do alone at two in the morning to learn where the bow
## drops, and making that a five-click trip through a lobby you are the only
## person in is the kind of friction that stops people practising at all.
##
## The session is a real one — `Net.start_practice` opens the same socket-less
## host `tools/playthrough.gd` and every dev harness use (D-011) — so everything
## downstream of here takes exactly the path it takes in a hosted match. Nothing
## about the range is a special case except which map is on.
##
## **This navigates itself** rather than leaving it to `joined_lobby`, and
## `_practice_pending` exists only to stop that signal doing it first.
## `start_practice` emits `joined_lobby` from inside `start_offline`, one line
## before it has said which map this is; a `go_to_arena` hanging off the signal
## would read `Net.config.map` in that window and load the island.
func _on_practice() -> void:
	if _pending:
		return
	_commit_name()
	_practice_pending = true
	Net.start_practice()
	_practice_pending = false
	SceneFlow.go_to_arena()


func _on_quit() -> void:
	get_tree().quit()


# -------------------------------------------------------------------- session ---

func _on_joined() -> void:
	# Practice has no lobby and drives its own transition; see `_on_practice`.
	if _practice_pending:
		return
	SceneFlow.go_to_lobby()


func _on_join_failed(message: String) -> void:
	_set_busy(false)
	_show_notice("Could not join", message)
	_set_join_open(true)


func _on_left_lobby(reason: Net.Leave, message: String) -> void:
	_set_busy(false)
	var described := UIState.describe_leave(reason, message)
	if not String(described["body"]).is_empty():
		_show_notice(String(described["title"]), String(described["body"]))


func _set_busy(busy: bool) -> void:
	_pending = busy
	_host_button.disabled = busy
	_connect_button.disabled = busy


func _show_notice(title: String, body: String) -> void:
	_notice_title.text = title
	_notice_body.text = body
	_notice.visible = true
