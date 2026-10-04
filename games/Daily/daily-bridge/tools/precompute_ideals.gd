extends SceneTree
## Precompute each day's ideal bridge (its index in BridgeSim.candidates) into ideals.json.
## godot --headless --path . --script tools/precompute_ideals.gd -- <first-day> <days>
func _init():
	var args := OS.get_cmdline_user_args()
	var first: String = args[0] if args.size() > 0 else "2026-10-02"
	var n: int = int(args[1]) if args.size() > 1 else 400
	var out := {}
	var t0 := Time.get_unix_time_from_datetime_string(first + "T00:00:00")
	for i in n:
		var d := Time.get_date_string_from_unix_time(t0 + i * 86400)
		var s := BridgeSim.IdealSearch.new(BridgeSim.make_level(d))
		s.run()
		out[d] = s.index()
		if i % 50 == 0:
			print(d, " -> ", s.index(), " cost ", s.cost)
	var f := FileAccess.open("res://ideals.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("wrote ", out.size(), " days")
	quit()
