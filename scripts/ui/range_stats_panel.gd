class_name RangeStatsPanel
extends PanelContainer
## The practice range's corner readout: what you have thrown, what landed, and
## how far the best one went.
##
## **Top-left, and that is a free corner rather than a preference.** Since D-118
## the clock and the score are top-centre; the health bar, the abilities, the
## lives, the letters and the Elder track all stack in `BottomRight`; and the
## kill feed runs up the left edge off the top of the chat panel, which is why
## this is not bottom-left. That leaves top-left and top-right, and this takes
## top-left because it is the one furthest from the crosshair — which is where a
## readout nobody needs mid-fight belongs. Top-right is the corner still free.
##
## Only ever visible on a practice map. `HUD._refresh_range_panel` owns that, so
## this file never asks which map it is on.
##
## It holds no counters of its own. `RangeStats` is the one table and this is a
## view of it, rebuilt on `rows_changed` — which is what keeps the panel and the
## lodge board from being two numbers that drift.

## Rows, in the order `RangeStats.WEAPONS` lists them. A weapon you have not
## used is not shown: a panel listing four when you have fired one is three
## lines of nothing.
const TITLES := {
	"spear": "SPEAR", "bow": "BOW", "sword": "SWORD", "lightning": "BOLT",
}

## How often to go looking for a `RangeStats` that has not been built yet. The
## HUD comes up with the arena and the counter is installed by the map, so on
## the first frame there is usually nothing to bind to.
const REBIND := 0.5

var _grid: GridContainer
var _run: Label
var _bound: RangeStats
var _since_bind: float = 0.0
var _run_seconds: float = -1.0
var _best_seconds: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = "HudPanel"

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	var title := Label.new()
	title.theme_type_variation = "SectionLabel"
	title.text = "RANGE"
	column.add_child(title)

	# The parkour line, above the table. It is the only row here that is about
	# something happening *now*, so it reads first.
	_run = Label.new()
	_run.theme_type_variation = "SmallLabel"
	_run.visible = false
	column.add_child(_run)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 2)
	column.add_child(_grid)

	_rebuild()


func _process(delta: float) -> void:
	if _bound != null and is_instance_valid(_bound):
		return
	_since_bind += delta
	if _since_bind < REBIND:
		return
	_since_bind = 0.0
	_bind()


## Bind immediately rather than on the next poll.
##
## Called by the HUD the moment the panel is turned on, so that walking into the
## range shows a table straight away instead of "no shots yet" for up to half a
## second. The poll in `_process` stays, because the counter is installed by the
## map and may not exist yet when the HUD first asks.
func bind_now() -> void:
	_since_bind = 0.0
	_bind()


## Attach to whatever counter and timer exist now.
##
## A poll rather than a signal from either, so that nothing in units 3 or 5's
## world code has to know the HUD exists, and so that leaving and re-entering
## the range binds again without anybody disconnecting anything.
func _bind() -> void:
	var stats := RangeStats.instance
	if stats != null and is_instance_valid(stats):
		_bound = stats
		if not stats.rows_changed.is_connected(_rebuild):
			stats.rows_changed.connect(_rebuild)
		_rebuild()

	# Unit 3's parkour timer, treated as a stub: if it is not there, or names
	# its signals differently, this is simply a panel with no run line.
	var timer := get_tree().get_first_node_in_group("parkour_timer")
	if timer == null:
		return
	if timer.has_signal("run_tick") \
			and not timer.is_connected("run_tick", _on_run_tick):
		timer.connect("run_tick", _on_run_tick)
	if timer.has_signal("run_finished") \
			and not timer.is_connected("run_finished", _on_run_finished):
		timer.connect("run_finished", _on_run_finished)


func _on_run_tick(seconds: float) -> void:
	_run_seconds = seconds
	_refresh_run()


func _on_run_finished(seconds: float, best: float) -> void:
	_run_seconds = seconds
	_best_seconds = best
	_refresh_run()


func _refresh_run() -> void:
	if _run == null:
		return
	if _run_seconds < 0.0:
		_run.visible = false
		return
	_run.visible = true
	var line := "RUN  %.2f s" % _run_seconds
	if _best_seconds >= 0.0:
		line += "   best %.2f s" % _best_seconds
	_run.text = line
	_run.add_theme_color_override("font_color", UIPalette.AMBER)


func _rebuild() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var stats := _bound
	if stats == null or not is_instance_valid(stats):
		_cell("no shots yet", UIPalette.TEXT_FAINT, "SmallLabel")
		for i: int in 4:
			_cell("", UIPalette.TEXT_FAINT, "SmallLabel")
		return

	var me := Net.local_id()
	var used := stats.weapons_used(me)
	if used.is_empty():
		_cell("no shots yet", UIPalette.TEXT_FAINT, "SmallLabel")
		for i: int in 4:
			_cell("", UIPalette.TEXT_FAINT, "SmallLabel")
		return

	for weapon: String in used:
		var row := stats.row(me, weapon)
		_cell(String(TITLES.get(weapon, weapon.to_upper())), UIPalette.TEXT_DIM,
			"SmallLabel")
		_cell("%d/%d" % [int(row["hits"]), int(row["launches"])],
			UIPalette.TEXT, "ValueLabel")
		_cell("%d%%" % roundi(RangeStats.accuracy(row) * 100.0),
			UIPalette.AMBER, "ValueLabel")
		_cell("%.0f m" % float(row["longest"]), UIPalette.TEXT_DIM,
			"SmallLabel")
		# The streak is the one number here that can go down, so it is the one
		# worth colouring: live above zero, faint at zero.
		var streak := int(row["streak"])
		_cell("x%d" % streak,
			UIPalette.GOOD if streak > 0 else UIPalette.TEXT_FAINT, "SmallLabel")


func _cell(body: String, tint: Color, variation: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = body
	label.add_theme_color_override("font_color", tint)
	_grid.add_child(label)
	return label
