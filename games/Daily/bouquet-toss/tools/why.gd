extends SceneTree
## Prints why each attempt for a date was rejected.
##   godot --headless --path . -s tools/why.gd -- 2026-10-16 [throw=1] [attempts=10]

const Levels = preload("res://core/levels.gd")
const V = preload("res://core/validator.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var d: String = args[0]
	var hole := int(args[1]) - 1 if args.size() > 1 else 0
	var n := int(args[2]) if args.size() > 2 else 10
	for a in n:
		var lv := Levels.make_attempt(d, hole, a)
		var st := V.evaluate(lv)
		print("%d %s ok=%s rate=%.3f solves=%d robust=%d routes=%s  %s" % [a, lv.archetype, st.ok, st.rate, st.solves, st.robust, ",".join(st.routes), "; ".join(st.reasons.slice(0, 3))])
	quit()
