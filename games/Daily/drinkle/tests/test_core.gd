extends GameTest
## Pure engine: database, comparison, partial matches, arrows, candidate filtering, search,
## hints, clues, explanations, sharing.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")
const Cands = preload("res://core/candidates.gd")
const Search = preload("res://core/search.gd")
const Hints = preload("res://core/hints.gd")
const Explain = preload("res://core/explain.gd")
const Game = preload("res://core/game.gd")
const Share = preload("res://core/share.gd")

const E := 0
const P := 1
const M := 2
const UP := 3
const DN := 4


func _d(id: String) -> Dictionary:
	return DB.get_drink(id)


func _fb(g: String, t: String) -> Array:
	return Array(Cmp.compare(_d(g), _d(t)))


func test_schema_has_the_six_dimensions():
	assert_eq(Schema.ids(), ["family", "base", "fruit", "bubbles", "sweet", "strength"], "MVP dimensions in order")
	for id in Schema.ids():
		assert_true(["categorical", "exact", "approximate"].has(String(Schema.attr(id).class)), id + " is classified")


func test_database_is_valid():
	assert_eq(DB.validate(), [], "no schema errors")
	assert_true(DB.size() >= 90, "about ninety drinks")
	assert_true(DB.targets().size() >= 70, "plenty of possible answers")
	for d in DB.all():
		assert_true(d.ingredients.size() >= 2, d.id + " lists its ingredients")


func test_ordinals_are_ints():
	assert_eq(typeof(_d("mojito").sweet), TYPE_INT, "JSON numbers are coerced to int")


func test_spec_example_margarita_vs_mojito():
	# Family 🟥 (sour vs highball, different groups), base 🟥, lime 🟩, fizzy 🟥, sweetness 🟩, strength ⬇️
	assert_eq(_fb("margarita", "mojito"), [M, M, E, M, E, DN], "margarita against mojito")


func test_exact_match_is_all_green():
	for d in DB.all():
		assert_true(Cmp.all_exact(Cmp.compare(d, d)), d.id + " matches itself")


func test_partial_matches():
	# lemon vs lime: citrus
	assert_eq(_fb("whiskey_sour", "daiquiri")[2], P, "lemon vs lime is a citrus partial")
	# rum vs cachaça: sugar-cane spirits
	assert_eq(_fb("daiquiri", "caipirinha")[1], P, "rum vs cachaça is related")
	# rum vs tequila: unrelated
	assert_eq(_fb("daiquiri", "margarita")[1], M, "rum vs tequila is a miss")
	# sparkling wine vs wine
	assert_eq(_fb("mimosa", "mulled_wine")[1], P, "sparkling wine vs wine is related")
	# alcohol-free bases
	assert_eq(_fb("latte", "lemonade")[1], P, "coffee vs juice: both alcohol-free")
	# family groups
	assert_eq(_fb("margarita", "mai_tai")[0], P, "sour vs tiki: shaken & citrusy")
	assert_eq(_fb("martini", "negroni")[0], P, "martini vs lowball: spirit-forward")
	assert_eq(_fb("gin_tonic", "aperol_spritz")[0], P, "highball vs spritz: long drinks")
	# none is never partial
	assert_eq(_fb("martini", "mojito")[2], M, "no fruit vs lime is a miss")
	# bools are exact or miss
	assert_eq(_fb("mojito", "daiquiri")[3], M, "fizzy vs still")


func test_partial_is_symmetric():
	for a in DB.all():
		for b in DB.all():
			var x := Cmp.compare(a, b)
			var y := Cmp.compare(b, a)
			for i in x.size():
				if x[i] == P or y[i] == P:
					assert_eq(x[i], y[i], "partial symmetric %s/%s" % [a.id, b.id])


func test_arrows_point_toward_the_mystery():
	assert_eq(_fb("martini", "mojito")[5], DN, "strong guess, light mystery: lower")
	assert_eq(_fb("lemonade", "martini")[5], UP, "alcohol-free guess, strong mystery: higher")
	assert_eq(_fb("bloody_mary", "pina_colada")[4], UP, "dry guess, very sweet mystery: higher")
	assert_eq(_fb("pina_colada", "bloody_mary")[4], DN, "and the other way")
	assert_eq(_fb("margarita", "daiquiri")[4], E, "same sweetness")


func test_no_indistinguishable_drinks():
	var keys := {}
	for d in DB.all():
		var k := DB.profile_key(d)
		assert_false(keys.has(k), "%s has the same profile as %s" % [d.id, keys.get(k, "")])
		keys[k] = d.id


func test_candidates_always_contain_the_answer():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all := DB.all()
	for trial in 120:
		var t: Dictionary = all[rng.randi_range(0, all.size() - 1)]
		var hist: Array = []
		for k in 4:
			var g: Dictionary = all[rng.randi_range(0, all.size() - 1)]
			hist.append(Cands.entry(g.id, t))
			var left := Cands.remaining(hist)
			assert_true(Cands.ids(left).has(t.id), "answer survives filtering")
			for c in left:
				for h in hist:
					if not Cmp.all_exact(h.fb):
						assert_eq(Cmp.compare(DB.get_drink(h.id), c), h.fb, "every candidate explains all feedback")
						assert_ne(c.id, h.id, "wrong guesses are ruled out")


func test_candidate_filter_narrows():
	var t := _d("mojito")
	var h := [Cands.entry("margarita", t)]
	var left := Cands.ids(Cands.remaining(h))
	assert_true(left.has("mojito"), "mojito fits")
	assert_false(left.has("margarita"), "the guess itself is out")
	assert_false(left.has("daiquiri"), "still drinks are out (mojito is fizzy)")
	assert_true(left.size() < DB.size() / 2, "one guess removes most drinks")
	h.append(Cands.entry("mojito", t))
	assert_eq(Cands.ids(Cands.remaining(h)), ["mojito"], "a win leaves only the answer")


func test_facts_filter():
	var left := Cands.remaining([], [{"attr": "base", "value": "rum"}])
	for c in left:
		assert_eq(c.base, "rum", "fact applied")


func test_search_examples():
	assert_eq(Search.search("moj")[0], "mojito", "moj")
	assert_eq(Search.search("gin t")[0], "gin_tonic", "gin t")
	assert_eq(Search.search("espresso")[0], "espresso_martini", "espresso")
	assert_eq(Search.search("marg"), ["margarita"], "marg finds only the margarita")
	assert_eq(Search.search("pina")[0], "pina_colada", "pina without the tilde")
	assert_eq(Search.search("margerita")[0], "margarita", "one typo")
	assert_eq(Search.search("cosmo")[0], "cosmopolitan", "alias prefix")
	assert_eq(Search.search("dark n")[0], "dark_n_stormy", "apostrophes ignored")
	assert_eq(Search.search("russian white")[0], "white_russian", "any word order")
	assert_eq(Search.search("boba")[0], "bubble_tea", "boba")
	assert_ne(Search.search("sour")[0], "apple_martini", "names beat aliases")
	assert_eq(Search.search("appletini")[0], "apple_martini", "appletini")
	assert_eq(Search.resolve("LIIT"), "long_island", "liit")
	assert_eq(Search.resolve("Pimms"), "pimms_cup", "pimms without the apostrophe")
	assert_eq(Search.search("virgin").size(), 3, "three virgin drinks")
	assert_eq(Search.search(""), [], "empty query")
	assert_eq(Search.search("zzzz"), [], "no match")


func test_aliases_resolve():
	for s in ["G&T", "Gin & Tonic", "Gin and Tonic", "gin  and   tonic", "g and t", "GIN & TONIC"]:
		assert_eq(Search.resolve(s), "gin_tonic", "alias " + s)
	assert_eq(Search.resolve("Rum & Coke"), "cuba_libre", "rum & coke")
	assert_eq(Search.resolve("Glühwein"), "mulled_wine", "accents")
	assert_eq(Search.resolve("pinacolada"), "pina_colada", "no spaces")
	assert_eq(Search.resolve("mojit"), "", "partial text is not a resolve")


func test_aliases_are_unique():
	var seen := {}
	for d in DB.all():
		for s in [d.name] + Array(d.aliases):
			var n := Search.normalize(String(s))
			assert_false(seen.has(n) and seen[n] != d.id, "alias '%s' used by %s and %s" % [s, seen.get(n, ""), d.id])
			seen[n] = d.id


func test_every_name_finds_itself_first():
	for d in DB.all():
		assert_eq(Search.search(d.name)[0], d.id, "typing the full name of " + d.name)
		assert_eq(Search.resolve(d.name), d.id, "resolve " + d.name)


func test_knowledge_from_feedback():
	var t := _d("mojito")
	var k := Hints.knowledge([Cands.entry("margarita", t)])
	assert_true(k.fruit.exact, "lime confirmed")
	assert_eq(k.fruit.value, "lime", "lime")
	assert_true(k.bubbles.exact, "a bool miss pins the other value")
	assert_eq(k.bubbles.value, true, "so it's fizzy")
	assert_eq(k.strength.hi, 1, "lower than medium: at most light")
	assert_eq(Hints.known_text("strength", k.strength), "Light or less", "range text")
	assert_eq(Hints.known_text("base", k.base), "?", "base unknown")
	var k2 := Hints.knowledge([Cands.entry("whiskey_sour", _d("daiquiri"))])
	assert_eq(Hints.known_text("fruit", k2.fruit), "Citrus?", "group known")


func test_hints_are_true_and_progressive():
	for d in DB.targets():
		var g = Game.new("2026-10-20", d)
		g.guess("cuba_libre" if d.id != "cuba_libre" else "martini")
		var h1: Dictionary = g.use_hint()
		assert_eq(h1.level, 1, "first hint is level 1")
		var h2: Dictionary = g.use_hint()
		var h3: Dictionary = g.use_hint()
		assert_eq(g.hints_used, 3, "three hints")
		assert_true(g.use_hint().is_empty(), "no fourth hint")
		for f in g.facts:
			assert_eq(d.get(f.attr), f.value, "%s: hint fact %s is true" % [d.id, f.attr])
		assert_true(Cands.ids(g.remaining()).has(d.id), "answer survives hints")
		assert_ne(String(h3.text), "", "hint 3 says something")


func test_clues_after_guess_four_and_five():
	var t := _d("sidecar")
	var g = Game.new("2026-10-20", t)
	for id in ["mojito", "martini", "latte"]:
		assert_true(g.guess(id).clue.is_empty(), "no clue before guess 4")
	var r: Dictionary = g.guess("bellini")
	assert_false(r.clue.is_empty(), "clue after guess 4")
	assert_eq(t.get(r.clue.attr), r.clue.value, "clue is true")
	var r5: Dictionary = g.guess("paloma")
	assert_false(r5.clue.is_empty(), "clue after guess 5")
	assert_ne(r5.clue.attr, r.clue.attr, "a different attribute")


func test_game_rules():
	var g = Game.new("2026-10-20", _d("mojito"))
	assert_false(g.guess("nope").ok, "unknown drink rejected")
	assert_true(g.guess("margarita").ok, "guess ok")
	assert_eq(g.guess("margarita").error, "repeat", "no repeats")
	assert_eq(g.guesses.size(), 1, "repeat not counted")
	var r: Dictionary = g.guess("mojito")
	assert_true(r.solved, "solved")
	assert_true(g.finished and g.won, "won")
	assert_eq(g.result_label(), "2/6", "result")
	assert_false(g.guess("martini").ok, "no guesses after the end")


func test_losing_after_six():
	var g = Game.new("2026-10-20", _d("sidecar"))
	for id in ["mojito", "martini", "latte", "bellini", "paloma", "negroni"]:
		g.guess(id)
	assert_true(g.finished, "finished after six")
	assert_false(g.won, "lost")
	assert_eq(g.result_label(), "X/6", "loss label")
	var l := Explain.loss(g.target, g.history(), g.facts)
	assert_true(l.left.has("Sidecar"), "the answer is among what still fit")
	assert_ne(String(l.text), "", "explanation text")


func test_save_round_trip():
	var t := _d("cosmopolitan")
	var g = Game.new("2026-10-20", t)
	g.guess("margarita")
	g.use_hint()
	g.use_hint()
	var data: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2 = Game.new("2026-10-20", t)
	assert_true(g2.load_dict(data), "loads")
	assert_eq(g2.guesses, g.guesses, "guesses restored")
	assert_eq(g2.hints_used, 2, "hints restored")
	assert_eq(g2.facts.size(), g.facts.size(), "facts restored")
	for f in g2.facts:
		assert_eq(typeof(f.value), typeof(t.get(f.attr)), "fact value type restored for " + f.attr)
	var other = Game.new("2026-10-20", _d("martini"))
	assert_false(other.load_dict(data), "a save for another answer is ignored")


func test_deduction_path():
	var t := _d("mojito")
	var g = Game.new("2026-10-20", t)
	for id in ["margarita", "tom_collins", "cuba_libre", "mojito"]:
		g.guess(id)
	var p := Explain.path(g.history(), g.facts)
	assert_eq(p.size(), 4, "a line per guess")
	assert_true(" ".join(p[0].notes).contains("tequila"), "margarita rules out tequila: " + str(p[0].notes))
	assert_true(" ".join(p[0].notes).contains("lime"), "and confirms lime")
	var g2 = Game.new("2026-10-20", _d("mint_julep"))
	g2.guess("margarita")
	assert_true(" ".join(Explain.path(g2.history(), []).front().notes).contains("ruled out Sour, tequila and citrus"),
		"a red lime rules out all citrus: " + str(Explain.path(g2.history(), []).front().notes))
	assert_true(p[3].solved, "last line solved")
	for i in range(1, p.size()):
		assert_true(p[i].left <= p[i - 1].left, "candidates never grow")


func test_share_is_spoiler_free():
	var t := _d("mojito")
	var g = Game.new("2026-10-20", t)
	g.guess("margarita")
	g.use_hint()
	g.guess("tom_collins")
	g.guess("mojito")
	var s := Share.text(5, g, "https://example.com/drinkle/")
	assert_true(s.begins_with("Drinkle #5 🍸"), "header")
	assert_true(s.contains("3/6"), "score")
	assert_true(s.contains("💡 1 hint"), "hints noted")
	assert_true(s.ends_with("https://example.com/drinkle/"), "plain link last")
	var lower := s.to_lower()
	for d in DB.all():
		assert_false(lower.contains(String(d.name).to_lower()), "no drink names: " + d.name)
	for word in ["rum", "lime", "gin", "tequila", "fizzy"]:
		assert_false(lower.contains(word), "no attribute words: " + word)
	assert_eq(s.split("\n").size(), 6, "header, 3 rows, score, link")
