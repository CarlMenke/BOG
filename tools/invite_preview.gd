extends Node
## Print the invite code this machine would hand out, without opening a lobby.
##
##   Godot --headless --path . tools/invite_preview.tscn
##   Godot --headless --path . tools/invite_preview.tscn -- host:port
##
## Development tool, not shipped. With no argument it reads `public_address` out
## of Settings — the same value the lobby reads — so it answers for the tunnel
## this machine is actually configured for. An argument overrides that without
## touching the saved setting.
##
## Why this exists: an invite code is a pure encoding of the host's endpoint
## (see `scripts/net/invite_code.gd`), so for a fixed playit tunnel the code is
## the same every time the lobby opens. That means it can be read out *before*
## anyone launches the game — the difference between "everybody get on and wait
## for me" and "here is the code, I will see you in there".
##
## It calls the shipped `Net.parse_public_address`, `Net.is_ipv4_literal`,
## `IP.resolve_hostname` and `InviteCode.encode` rather than reimplementing any
## of them, so it cannot drift from what the lobby prints. The one thing that can
## still make it wrong is DNS: playit's A record can move, and the code carries
## the *address*, not the name. `ip=` is printed for exactly that reason — if a
## code stops working, compare that line against a fresh run.
##
## **It is a scene, not a `--script` tool, and that is load-bearing.** Godot only
## instantiates autoloads when it runs a scene, and `scripts/net/net.gd` refers
## to `Settings` at compile time — under `--script` it fails to compile, the
## static call lands on a broken GDScript, and the error names
## `parse_public_address` rather than the autoload that is really missing.
##
## Output is one `key=value` per line so a script can grep it. Exit codes: 0 a
## code was produced, 1 there is no usable public address (the reason is on the
## `problem=` line, worded as the lobby words it).


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var typed := String(args[0]) if args.size() > 0 else String(Settings.get_value("public_address"))
	var source := "argument" if args.size() > 0 else "user://settings.cfg"

	print("invite_preview: source=%s" % source)

	if typed.strip_edges().is_empty():
		print("invite_preview: problem=NO PUBLIC ADDRESS SET — WOULD USE LAN/TAILNET")
		get_tree().quit(1)
		return

	print("invite_preview: address=%s" % typed)

	var parsed := Net.parse_public_address(typed)
	if parsed.is_empty():
		print("invite_preview: problem=PUBLIC ADDRESS IS NOT HOST:PORT")
		get_tree().quit(1)
		return

	var host: String = parsed["host"]
	var port: int = parsed["port"]

	# A typed-in IP needs no lookup, which is also `Net`'s behaviour.
	var ip := host
	if not Net.is_ipv4_literal(host):
		ip = IP.resolve_hostname(host, IP.TYPE_IPV4)
		if not Net.is_ipv4_literal(ip):
			# Empty for a name that does not resolve; an IPv6 answer is
			# well-formed and useless to a code with four bytes for an address.
			print("invite_preview: problem=PUBLIC ADDRESS DID NOT RESOLVE")
			get_tree().quit(1)
			return

	print("invite_preview: ip=%s" % ip)
	print("invite_preview: port=%d" % port)
	print("invite_preview: code=%s" % InviteCode.encode(ip, port))
	get_tree().quit(0)
