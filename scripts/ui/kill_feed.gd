class_name KillFeed
extends VBoxContainer
## Who just killed whom (PLAN 3.8, 6.3), and who just picked up a letter (D-050).
##
## In a game where one hit kills, the feed is not trivia — it is the only way to
## know that the Bog you were about to fight is already dead, or that the person
## who keeps killing you is on a streak. So rows you are in are marked: your own
## name is always the Bog's yellow, and a row you are involved in keeps a bright
## edge while the others sink back.
##
## Rows are plain nodes with a tween on their modulate rather than a timer that
## rebuilds a list. A feed that repaints itself every frame in the middle of a
## fight is the kind of thing that shows up in a profile later.

## Long enough to catch out of the corner of your eye while running, short
## enough that it is never a wall of text.
const HOLD := 5.0
const FADE := 0.9
const MAX_ROWS := 5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 4)


## `cause` is a `Bog.Cause`. A victim who is their own killer fell off the
## island under their own steam, which the feed says in words rather than
## drawing an arrow from someone to themselves.
func add_kill(victim_id: int, killer_id: int, cause: int) -> void:
	if killer_id == victim_id or killer_id == 0:
		# Name first, so every row in the feed starts with a Bog and the eye can
		# scan the left edge of the column for its own name.
		add_event([victim_id, _self_death_text(cause)])
	else:
		add_event([killer_id, _cause_glyph(cause), victim_id])


## Anything that is not a kill but belongs in the same corner of the eye: a
## letter picked up or banked (D-050), and whatever the next mode needs to shout
## about. A row is a list of segments, read left to right:
##
##   int              a peer, drawn as their name in the colour a kill row uses
##   String           a word in the feed's verb colour
##   [String, Color]  a word in a colour of its own (a letter in gold)
##
##   feed.add_event([peer_id, "picked up", ["G", Pickup.LETTER_COLOUR]])
##
## Segments rather than one formatted string because a name has to keep its own
## colour — your name yellow, a teammate's in the team colour — and a Label
## colours all of its text at once. The row counts as yours, and stays bright,
## if any peer in it is you, exactly as a kill does.
func add_event(segments: Array) -> void:
	var involved := false
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 9)
	for segment: Variant in segments:
		if segment is int:
			involved = involved or segment == Net.local_id()
			line.add_child(_name_label(segment))
		elif segment is Array and (segment as Array).size() == 2:
			line.add_child(_word(str(segment[0]), segment[1]))
		else:
			line.add_child(_word(str(segment), UIPalette.AMBER))
	_push_row(line, involved)


func _push_row(line: HBoxContainer, involved: bool) -> void:
	var row := PanelContainer.new()
	row.theme_type_variation = "HudPanel"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shrink to the text and hang off the right edge. Full-width rows turn the
	# feed into a banner across the top of the screen.
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(line)

	add_child(row)
	move_child(row, 0)  # newest at the top, nearest the eye
	# `remove_child` first, and it is not optional. `queue_free` defers to the end
	# of the frame, so a loop that frees a child and then re-reads
	# `get_child_count()` sees the same number it saw last time and spins for
	# ever. The sixth death in any match — six kills inside the 5.9 s a row is on
	# screen, which in an eight-player game with a one-hit weapon is an ordinary
	# fight — hung the process at 100% CPU with no error and no output.
	# `remove_child` detaches immediately, so the count actually falls.
	while get_child_count() > MAX_ROWS:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()

	# A row you are in stays at full strength for its whole life; everyone
	# else's settles back so the feed reads as background.
	row.modulate = Color(1, 1, 1, 1.0 if involved else 0.78)
	var tween := create_tween()
	tween.tween_interval(HOLD)
	tween.tween_property(row, "modulate:a", 0.0, FADE)
	tween.tween_callback(row.queue_free)


func clear() -> void:
	for child in get_children():
		child.queue_free()


func _name_label(peer_id: int) -> Label:
	var label := Label.new()
	label.text = Net.player_name(peer_id)
	label.theme_type_variation = "SmallLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var colour := UIPalette.TEXT
	if peer_id == Net.local_id():
		colour = UIPalette.BOG
	elif Net.config.mode == MatchConfig.Mode.TEAMS:
		colour = UIPalette.team_colour(Net.player_team(peer_id))
	label.add_theme_color_override("font_color", colour)
	return label


func _word(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "SmallLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", colour)
	return label


## The kit has no icon font, so the weapon is a typographic mark. An arrow reads
## as "did this to" in every language a player is likely to bring.
static func _cause_glyph(cause: int) -> String:
	match cause:
		Bog.Cause.SPEAR:
			return "⟶"
		Bog.Cause.ARROW:
			# A shorter arrow with a nock on the back of it, because the bow and
			# the spear are otherwise the same sentence — "a pointy thing flew
			# at you" — and the feed is where a player works out which of the
			# two they keep dying to (D-065).
			return "↣"
		Bog.Cause.SWORD:
			# Not an arrow at all, because nothing flew: the great sword is the
			# one kill in this game that happened at arm's length, and the feed
			# is where a player finds out that somebody got that close (D-068).
			return "⚔"
		Bog.Cause.LIGHTNING:
			# The one cause with a mark of its own rather than the generic
			# arrow, because it is the one kill in the game that is worth
			# reading the feed to find out about (D-038).
			return "⚡"
		Bog.Cause.FIST:
			# The sword's argument one step further in (D-124). A fist is the
			# one kill in this game that took five blows and no weapon at all,
			# and a generic arrow would tell the player they were speared by
			# somebody who was not even holding a spear.
			return "✊"
		Bog.Cause.VOID:
			return "pushed off"
		Bog.Cause.FALL:
			return "dropped"
		_:
			return "⟶"


static func _self_death_text(cause: int) -> String:
	match cause:
		Bog.Cause.VOID:
			return "fell off the island"
		Bog.Cause.FALL:
			return "misjudged a drop"
		_:
			return "died"
