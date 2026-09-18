extends SceneTree
## Which of the showroom's font families this machine actually has. Development
## tool, not shipped.
##
##     Godot --headless --path . --script tools/showroom/font_check.gd
##
## `SystemFont.font_names` is a wish list: Godot walks it, takes the first family
## the OS knows, and silently falls through to the engine's bundled sans if it
## knows none of them. That silence is the one thing a screenshot cannot tell you
## apart from "the style just looks like that", so this asks the OS directly.

const STYLES := preload("res://tools/showroom/showroom_styles.gd")


func _initialize() -> void:
	var installed := OS.get_system_fonts()
	for variant: String in STYLES.names():
		var style: Dictionary = STYLES.get_style(variant)
		if style.is_empty():
			continue
		print("[%s]" % variant)
		for role: String in ["display_faces", "body_faces"]:
			if not style.has(role):
				continue
			var report: PackedStringArray = []
			var winner := ""
			for face: String in style[role]:
				var found := OS.get_system_font_path(face) != "" or installed.has(face)
				report.append("%s %s" % ["+" if found else "-", face])
				if found and winner.is_empty():
					winner = face
			print("  %-14s %s" % [role, ", ".join(report)])
			print("  %-14s %s" % ["", "resolves to: " + (winner if winner else "NOTHING - engine default")])
	quit(0)


func _process(_delta: float) -> bool:
	return true
