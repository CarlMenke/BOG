class_name LetterCall
extends VBoxContainer
## "PIPWICK HAS A B" across the top of the screen, and "PIPWICK HAS BOG" when
## somebody's last one lands (D-093).
##
## The letters were the one thing in this game that happened in silence. A card
## coming out of a corpse is announced to nobody, a carrier crossing the map is
## a Bog with something in its fist, and the only place the state existed was the
## letter track at the bottom of your own screen and the scoreboard behind Tab.
## In a mode whose whole tension is *who is close to winning*, that is the one
## fact everybody needs and nobody had.
##
## Two calls, because they are two different pieces of news:
##
##   **picked up** — somebody is carrying a letter *now*. This is the one that
##   makes a player a target, and it fires in every mode that has letters at all.
##   **all three** — somebody's scoring mask is complete. In Teams that is the
##   team's pooled mask (D-049), so the name is whoever finished it and the news
##   is that their side is done.
##
## Written in the player's team colour, from the same `UIPalette.team_colour`
## the plates, the feed and the scoreboard use, so a name is the same colour
## everywhere it appears. Outside Teams there is no team, and the call is drawn
## in the neutral colour rather than in nothing.
##
## Rows are trimmed with `remove_child` *before* `queue_free`, for the reason
## `kill_feed.gd` spells out at length: `queue_free` defers, so a loop that frees
## a child and re-reads `get_child_count()` never terminates. That bug hung the
## whole process once already and this is the same shape of feed.

## How many calls can stack before the oldest is pushed off. Two: this sits
## under the clock and the score line, and a third row starts covering the map.
const MAX_ROWS := 2
## Full strength for this long, then fade. Longer than the kill feed's, because
## this is news you act on rather than news you register.
const HOLD := 4.2
const FADE := 0.9

## The three-bit mask that means somebody has the lot, mirrored from
## `MatchState.LETTER_ALL` rather than reached for, so this file has no opinion
## about the match.
const ALL := 7


## All three letters take "a" and not "an": G, U and B are read aloud as *jee*,
## *yoo* and *bee*, and "AN U" — which this said at first — is the spelling of a
## word nobody says.
func picked_up(who: String, letter_text: String, colour: Color) -> void:
	_say("%s HAS A %s" % [who.to_upper(), letter_text], colour)


## Somebody has lifted a card out of another team's vault (D-092). Written in
## the *thief's* colour, because the name at the front of the sentence is theirs
## and a line that changes colour halfway through reads as two lines.
func stolen(who: String, letter_text: String, from_team: int, colour: Color) -> void:
	_say("%s STOLE A %s FROM TEAM %d" % [who.to_upper(), letter_text,
		from_team + 1], colour)


## Somebody's scoring mask is complete.
func has_them_all(who: String, colour: Color) -> void:
	_say("%s HAS BOG" % who.to_upper(), colour)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _say(text: String, colour: Color) -> void:
	var row := Label.new()
	row.text = text
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.theme_type_variation = &"ReadoutLabel"
	row.add_theme_font_size_override("font_size", 26)
	row.add_theme_color_override("font_color", colour)
	# A dark outline rather than a panel behind it: this floats over whatever the
	# map happens to be, and a pale name on a pale wall is unreadable without one.
	row.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.9))
	row.add_theme_constant_override("outline_size", 6)

	add_child(row)
	move_child(row, 0)
	while get_child_count() > MAX_ROWS:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()

	var tween := create_tween()
	tween.tween_interval(HOLD)
	tween.tween_property(row, "modulate:a", 0.0, FADE)
	tween.tween_callback(row.queue_free)
