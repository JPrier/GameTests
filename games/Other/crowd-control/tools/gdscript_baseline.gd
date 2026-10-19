extends SceneTree
## "Is Rust worth it?" baseline: the collision-free speed model's inner loop (uniform-grid neighbour
## search, exponential repulsion, spacing ahead) written as plainly as possible in GDScript, timed
## per tick. No routing, gates, walls, metrics or rendering: the real Rust step does far more.
##   godot --headless --script tools/gdscript_baseline.gd

const CELL := 2.0
const W := 46.0
const H := 62.0


func _init() -> void:
	for n in [700, 3000]:
		print("GDScript CFSM inner loop, %d agents: %.2f ms/tick" % [n, _bench(n)])
	quit()


func _bench(n: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var pos := PackedVector2Array()
	var head := PackedVector2Array()
	for i in n:
		pos.append(Vector2(rng.randf() * W, rng.randf() * H))
		head.append(Vector2.RIGHT)
	var cols := int(ceil(W / CELL)) + 1
	var rows := int(ceil(H / CELL)) + 1
	var total := 0.0
	var ticks := 20
	for t in ticks:
		var t0 := Time.get_ticks_usec()
		var cells := []
		cells.resize(cols * rows)
		for k in cells.size():
			cells[k] = PackedInt32Array()
		for i in n:
			var c := int(pos[i].y / CELL) * cols + int(pos[i].x / CELL)
			cells[c].append(i)
		var new_pos := PackedVector2Array()
		new_pos.resize(n)
		for i in n:
			var p := pos[i]
			var e0 := (Vector2(W, H * 0.5) - p).normalized()
			var dir := e0
			var spacing := INF
			var cx := int(p.x / CELL)
			var cy := int(p.y / CELL)
			for y in range(maxi(cy - 1, 0), mini(cy + 2, rows)):
				for x in range(maxi(cx - 1, 0), mini(cx + 2, cols)):
					for j in cells[y * cols + x]:
						if j == i:
							continue
						var dv := p - pos[j]
						var d := dv.length()
						if d > CELL or d < 0.00001:
							continue
						dir += dv / d * 8.0 * exp((0.4 - d) / 0.1)
			var e := dir.normalized()
			for y in range(maxi(cy - 1, 0), mini(cy + 2, rows)):
				for x in range(maxi(cx - 1, 0), mini(cx + 2, cols)):
					for j in cells[y * cols + x]:
						if j == i:
							continue
						var dv := pos[j] - p
						if dv.dot(e) <= 0.0 or absf(dv.cross(e)) >= 0.4:
							continue
						spacing = minf(spacing, dv.length() - 0.4)
			var v := minf(1.3, maxf(spacing / 0.5, 0.0))
			new_pos[i] = p + e * v * 0.05
		pos = new_pos
		total += (Time.get_ticks_usec() - t0) / 1000.0
	return total / ticks
