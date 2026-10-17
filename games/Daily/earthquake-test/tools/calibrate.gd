extends SceneTree
## Headless calibration / fuzz tool for the daily challenge generator.
##
##   godot --headless --path . --script res://tools/calibrate.gd -- [options]
##
##   --start=YYYY-MM-DD   first date (default: generator CUTOVER)
##   --days=N             how many consecutive dates (default 365)
##   --check              synthesize every quake and validate the record (NaN, drift, pga...)
##   --canon=K            run the canonical reference structures on every K-th day (0 = off)
##   --out=PATH           also write one JSON record per day (JSON lines)
##   --merge=A,B,...      skip generation: build the report from earlier --out files
##   --quiet              no report (useful with --out for parallel shards)
##
## The report shows archetype / site / soil / modifier / budget distributions, repeat rates,
## numeric spreads, rejection and fallback counts, how well the analytic response estimate
## matches a time-domain response spectrum, the canonical-structure response matrix (which
## kind of build does best under which quake), and the extreme days.

const Gen = preload("res://challenge/generator.gd")
const Arch = preload("res://challenge/archetypes.gd")
const Validator = preload("res://challenge/validator.gd")
const Waveform = preload("res://quake/waveform.gd")
const Fingerprint = preload("res://challenge/fingerprint.gd")
const Canon = preload("res://reference/canonical.gd")


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var records: Array = []
	if opts.has("merge"):
		for path in String(opts.merge).split(","):
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				printerr("can't read ", path)
				continue
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line != "":
					records.append(JSON.parse_string(line))
	else:
		records = collect(String(opts.get("start", Gen.CUTOVER)), int(opts.get("days", "365")),
			opts.has("check"), int(opts.get("canon", "0")), String(opts.get("out", "")))
	if not opts.has("quiet"):
		print(report(records))
	quit()


static func collect(start: String, days: int, check: bool, canon: int, out_path: String) -> Array:
	var out: Array = []
	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)
	var i0 := Gen.day_index(start)
	var t0 := Time.get_ticks_msec()
	for i in days:
		var d := Gen.date_of(i0 + i)
		var c = Gen.generate(d)
		var r := record(c, check, canon > 0 and i % canon == 0)
		out.append(r)
		if f:
			f.store_line(JSON.stringify(r))
		if (i + 1) % 50 == 0:
			printerr("  %d/%d days (%.1fs)" % [i + 1, days, (Time.get_ticks_msec() - t0) / 1000.0])
	return out


static func record(c, check: bool, canon: bool) -> Dictionary:
	var r: Dictionary = c.to_dict()
	r["fingerprint"] = Array(c.fingerprint)
	if c.is_legacy():
		return r
	if check or canon:
		var q = c.make_quake()
		r["problems"] = Array(Validator.quake_problems(q, c.quake_archetype, c.modifier))
		r["synth"] = {"pga": q.pga, "pga_v": q.pga_v, "max_disp": q.max_disp, "end_disp": q.end_disp, "dominant_hz": q.dominant_hz}
		r["psa_td"] = Array(Waveform.response_spectrum(q.dx)).map(func(x): return x / q.pga)
	if canon:
		var res := Canon.evaluate(c)
		var cr := {}
		for id in res:
			var m: Dictionary = res[id]
			cr[id] = {"built": m.built, "standing": m.standing, "survive": m.survive, "collapse": m.collapse,
				"first_fail": m.first_fail, "max_sway": m.max_sway, "unstable": m.unstable, "beams": m.beams}
		r["canon"] = cr
	return r


# ------------------------------------------------------------------ report

static func _pct(n: int, total: int) -> String:
	return "%5.1f%%" % (100.0 * n / maxf(total, 1))


static func _count(records: Array, key: String) -> Dictionary:
	var out := {}
	for r in records:
		var k := str(r.get(key, ""))
		out[k] = int(out.get(k, 0)) + 1
	return out


static func _table(title: String, counts: Dictionary, total: int, order: Array = []) -> String:
	var s := "%s:\n" % title
	var keys: Array = order if not order.is_empty() else counts.keys()
	if order.is_empty():
		keys.sort()
	for k in keys:
		s += "  %-18s %s  (%d)\n" % [k if str(k) != "" else "(none)", _pct(int(counts.get(k, 0)), total), int(counts.get(k, 0))]
	return s


static func _stats(xs: Array) -> String:
	if xs.is_empty():
		return "n/a"
	var v := xs.duplicate()
	v.sort()
	var q := func(p: float) -> float: return float(v[clampi(int(p * (v.size() - 1)), 0, v.size() - 1)])
	return "min %.2f  p10 %.2f  median %.2f  p90 %.2f  max %.2f" % [q.call(0.0), q.call(0.1), q.call(0.5), q.call(0.9), q.call(1.0)]


static func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	if n < 3:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))


static func report(records: Array) -> String:
	var v2: Array = records.filter(func(r): return int(r.version) == 2)
	var n := v2.size()
	if n == 0:
		return "no v2 days in sample"
	var s := "\n==== Earthquake Test challenge calibration: %d days (%s .. %s) ====\n\n" % [n, v2[0].date, v2[-1].date]
	s += _table("quake archetypes", _count(v2, "quake"), n, Arch.QUAKES) + "\n"
	s += _table("site archetypes", _count(v2, "site"), n, Arch.SITES) + "\n"
	s += _table("soils", _count(v2, "soil"), n, Arch.SOILS) + "\n"
	s += _table("modifiers", _count(v2, "modifier"), n, [""] + Arch.MODIFIERS) + "\n"
	s += _table("budgets", _count(v2, "budget"), n) + "\n"
	# quake x soil and quake x site mixes
	s += "quake x soil (days):\n"
	for qk in Arch.QUAKES:
		var row := "  %-14s" % qk
		for so in Arch.SOILS:
			row += " %s %3d" % [so.substr(0, 4), v2.filter(func(r): return r.quake == qk and r.soil == so).size()]
		s += row + "\n"
	s += "quake x site (days):\n"
	for qk in Arch.QUAKES:
		var row := "  %-14s" % qk
		for si in Arch.SITES:
			row += " %s %3d" % [si.substr(0, 5), v2.filter(func(r): return r.quake == qk and r.site == si).size()]
		s += row + "\n"
	var combos := {}
	for r in v2:
		var k := "%s/%s/%s" % [r.quake, r.site, r.soil]
		combos[k] = int(combos.get(k, 0)) + 1
	var ck: Array = combos.keys()
	ck.sort_custom(func(a, b): return combos[a] > combos[b])
	s += "distinct quake/site/soil combos: %d of %d possible; most common: " % [combos.size(), Arch.QUAKES.size() * Arch.SITES.size() * Arch.SOILS.size()]
	for i in mini(5, ck.size()):
		s += "%s x%d  " % [ck[i], combos[ck[i]]]
	s += "\n\n"
	# repeats
	var same_q := 0
	var same_site := 0
	var same_combo := 0
	var mod_close := 0
	var mod_adjacent := 0
	for i in range(1, n):
		if v2[i].quake == v2[i - 1].quake:
			same_q += 1
		if v2[i].site == v2[i - 1].site:
			same_site += 1
		if v2[i].quake == v2[i - 1].quake and v2[i].site == v2[i - 1].site and v2[i].soil == v2[i - 1].soil:
			same_combo += 1
		if v2[i].modifier != "" and v2[i - 1].modifier != "":
			mod_adjacent += 1
		if v2[i].modifier != "":
			for k in range(maxi(0, i - 7), i):
				if v2[k].modifier == v2[i].modifier:
					mod_close += 1
					break
	s += "repeats: same quake as yesterday %s, same site %s, same quake+site+soil %s, modifier days back-to-back %d, same modifier within 7 days %d\n" % [
		_pct(same_q, n - 1), _pct(same_site, n - 1), _pct(same_combo, n - 1), mod_adjacent, mod_close]
	var combo_repeat_14 := 0
	for i in n:
		for k in range(maxi(0, i - 14), i):
			if v2[k].quake == v2[i].quake and v2[k].site == v2[i].site and v2[k].soil == v2[i].soil:
				combo_repeat_14 += 1
				break
	s += "same quake+site+soil within the previous 14 days: %s\n\n" % _pct(combo_repeat_14, n)
	# numbers
	s += "duration (s):   %s\n" % _stats(v2.map(func(r): return float(r.duration)))
	s += "pga (m/s^2):    %s\n" % _stats(v2.map(func(r): return float(r.pga)))
	s += "magnitude:      %s\n" % _stats(v2.map(func(r): return float(r.magnitude)))
	s += "difficulty est: %s\n" % _stats(v2.map(func(r): return float(r.metrics.difficulty)))
	s += "response spread:%s\n" % _stats(v2.map(func(r): return float(r.metrics.spread)))
	s += "novelty:        %s\n" % _stats(v2.map(func(r): return float(r.novelty)))
	var rej: Array = v2.map(func(r): return int(r.rejected))
	var rej_total := 0
	for x in rej:
		rej_total += int(x)
	s += "candidates rejected per day: %s  (overall rate %s)\n" % [_stats(rej), _pct(rej_total, n * Gen.N_CANDIDATES)]
	s += "fallback days: %d\n" % v2.filter(func(r): return bool(r.fallback)).size()
	# synthesized checks
	var checked: Array = v2.filter(func(r): return r.has("problems"))
	if not checked.is_empty():
		var bad: Array = checked.filter(func(r): return not r.problems.is_empty())
		s += "\nsynthesized quakes checked: %d, with problems: %d\n" % [checked.size(), bad.size()]
		for r in bad.slice(0, 8):
			s += "  %s %s: %s\n" % [r.date, r.quake, ", ".join(r.problems)]
		s += "max ground displacement (m): %s\n" % _stats(checked.map(func(r): return float(r.synth.max_disp)))
		var ea: Array = []
		var eb: Array = []
		for r in checked:
			for j in r.psa_td.size():
				ea.append(log(maxf(float(r.metrics.psa[j]), 1e-6)))
				eb.append(log(maxf(float(r.psa_td[j]), 1e-6)))
		s += "analytic vs time-domain response spectrum: log correlation %.3f over %d ordinates\n" % [_corr(ea, eb), ea.size()]
		s += "dominant Hz (synth) by archetype:\n"
		for qk in Arch.QUAKES:
			var xs: Array = checked.filter(func(r): return r.quake == qk).map(func(r): return float(r.synth.dominant_hz))
			s += "  %-14s %s\n" % [qk, _stats(xs)]
	# canonical structures
	var canon: Array = v2.filter(func(r): return r.has("canon"))
	if not canon.is_empty():
		s += "\n---- canonical structures (%d days) ----\n" % canon.size()
		s += "%-14s %8s %8s %8s %8s %8s\n" % ["structure", "built", "kept", "survive", "collapse", "unstable"]
		for id in Canon.IDS:
			var built := 0.0
			var kept := 0.0
			var surv := 0.0
			var col := 0
			var uns := 0
			for r in canon:
				var m: Dictionary = r.canon[id]
				built += float(m.built)
				kept += float(m.standing) / maxf(float(m.built), 0.01)
				surv += float(m.survive)
				col += 1 if m.collapse else 0
				uns += 1 if m.unstable else 0
			s += "%-14s %7.1fm %7.0f%% %7.0f%% %8s %8d\n" % [id, built / canon.size(), 100.0 * kept / canon.size(), 100.0 * surv / canon.size(), _pct(col, canon.size()), uns]
		s += "\nmean standing height (m) by quake archetype (rows) and structure (cols):\n%-14s" % ""
		for id in Canon.IDS:
			s += " %6s" % id.substr(0, 6)
		s += "   best\n"
		for qk in Arch.QUAKES:
			var rows: Array = canon.filter(func(r): return r.quake == qk)
			if rows.is_empty():
				continue
			var line := "%-14s" % qk
			var best_id := ""
			var best_v := -1.0
			for id in Canon.IDS:
				var tot := 0.0
				for r in rows:
					tot += float(r.canon[id].standing)
				tot /= rows.size()
				line += " %6.2f" % tot
				if tot > best_v:
					best_v = tot
					best_id = id
			s += line + "   " + best_id + "\n"
		var wins := {}
		var flat := 0
		var spreads: Array = []
		var means: Array = []
		var keeps: Array = []
		var diffs: Array = []
		for r in canon:
			var best_id := ""
			var best_v := -1.0
			var hs: Array = []
			for id in Canon.IDS:
				var h := float(r.canon[id].standing)
				hs.append(h)
				if h > best_v:
					best_v = h
					best_id = id
			wins[best_id] = int(wins.get(best_id, 0)) + 1
			var mean := 0.0
			var kept := 0.0
			for h in hs:
				mean += h
			for id in Canon.IDS:
				kept += float(r.canon[id].standing) / maxf(float(r.canon[id].built), 0.01) / Canon.IDS.size()
			mean /= hs.size()
			keeps.append(kept)
			var sd := 0.0
			for h in hs:
				sd += (h - mean) * (h - mean)
			sd = sqrt(sd / hs.size())
			var cv := sd / maxf(mean, 0.1)
			spreads.append(cv)
			means.append(mean)
			diffs.append(float(r.metrics.difficulty))
			r["_canon_mean"] = mean
			r["_canon_cv"] = cv
			if cv < 0.35:
				flat += 1
		s += "\nbest canonical structure per day: "
		for k in wins:
			s += "%s %d  " % [k, wins[k]]
		s += "\nstanding-height spread across structures (coeff. of variation): %s\n" % _stats(spreads)
		s += "'flat' days (every structure about the same, CV < 0.35): %d of %d\n" % [flat, canon.size()]
		s += "difficulty estimate vs share of canonical height kept: correlation %.3f (negative = estimate tracks damage)\n" % _corr(diffs, keeps)
		s += "share of canonical height kept per day: %s\n" % _stats(keeps)
		var hardest = canon[0]
		var easiest = canon[0]
		for r in canon:
			if float(r._canon_mean) < float(hardest._canon_mean):
				hardest = r
			if float(r._canon_mean) > float(easiest._canon_mean):
				easiest = r
		s += "hardest canonical day: %s %s/%s/%s %s $%d (mean %.2f m)\n" % [hardest.date, hardest.quake, hardest.site, hardest.soil, hardest.modifier, hardest.budget, hardest._canon_mean]
		s += "easiest canonical day: %s %s/%s/%s %s $%d (mean %.2f m)\n" % [easiest.date, easiest.quake, easiest.site, easiest.soil, easiest.modifier, easiest.budget, easiest._canon_mean]
	# extremes
	s += "\n---- extreme days ----\n"
	var lowest = v2[0]
	var most_rej = v2[0]
	var hardest_est = v2[0]
	var easiest_est = v2[0]
	for r in v2:
		if float(r.novelty) < float(lowest.novelty):
			lowest = r
		if int(r.rejected) > int(most_rej.rejected):
			most_rej = r
		if float(r.metrics.difficulty) > float(hardest_est.metrics.difficulty):
			hardest_est = r
		if float(r.metrics.difficulty) < float(easiest_est.metrics.difficulty):
			easiest_est = r
	# most unusual: largest mean fingerprint distance to every other day
	var unusual = v2[0]
	var unusual_d := -1.0
	var stride := maxi(1, n / 200)
	for i in range(0, n, stride):
		var tot := 0.0
		var cnt := 0
		for k in range(0, n, stride):
			if k != i:
				tot += Fingerprint.distance(PackedFloat32Array(v2[i].fingerprint), PackedFloat32Array(v2[k].fingerprint))
				cnt += 1
		if tot / maxf(cnt, 1) > unusual_d:
			unusual_d = tot / maxf(cnt, 1)
			unusual = v2[i]
	for pair in [["lowest novelty", lowest], ["most rejections", most_rej], ["hardest (estimate)", hardest_est],
			["easiest (estimate)", easiest_est], ["most unusual fingerprint", unusual]]:
		var r = pair[1]
		s += "%-26s %s  %s / %s / %s %s  $%d  M%.1f %.0fs  diff %.2f  nov %.2f  rej %d\n" % [pair[0], r.date, r.quake, r.site, r.soil,
			r.modifier, int(r.budget), float(r.magnitude), float(r.duration), float(r.metrics.difficulty), float(r.novelty), int(r.rejected)]
	return s
