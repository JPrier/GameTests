extends SceneTree
## godot --headless --path . -s tools/precompute.gd -- [days=400] [start=EPOCH]
## Writes core/attempts.json: for each date, which generator attempt produces its puzzle, so the
## game regenerates one attempt instead of searching. Purely a speed-up: results are identical,
## and the game falls back to the full search for dates not in the table.
## Rerun after any change to the generator (and bump Generator.GEN_VERSION).

const G = preload("res://core/generator.gd")
const Daily = preload("res://core/daily.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 400
	var start := String(args[1]) if args.size() > 1 else Daily.EPOCH
	var out := {}
	var t0 := Time.get_ticks_msec()
	for i in days:
		var d := Daily.add_days(start, i)
		var m = G.new().generate_full(d, Daily.tier_for(d))
		if m != null and m.tier == Daily.tier_for(d):
			out[d] = m.attempts
		if i % 20 == 0:
			print("%s  attempt %s  (%d s)" % [d, out.get(d, "-"), (Time.get_ticks_msec() - t0) / 1000])
	var f := FileAccess.open("res://core/attempts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": G.GEN_VERSION, "from": start, "days": out}, "", false))
	f.close()
	print("wrote %d days in %d s" % [out.size(), (Time.get_ticks_msec() - t0) / 1000])
	quit()
