extends RefCounted
## The canonical drink database (data/drinks.json). Each drink is a Dictionary with the six
## compared attributes coerced to clean types (ordinals as int). Pure data, no UI.

const Schema = preload("res://core/schema.gd")
const PATH := "res://data/drinks.json"

const REQUIRED := ["id", "name", "family", "base", "fruit", "bubbles", "sweet", "strength", "fame", "target"]

static var _list: Array = []
static var _by_id: Dictionary = {}
static var version := 0


static func _ensure() -> void:
	if not _list.is_empty():
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(data is Dictionary, "drinks.json must parse")
	version = int(data.get("version", 0))
	for raw in data.drinks:
		var d: Dictionary = raw.duplicate(true)
		for id in Schema.ids():
			if Schema.is_ordinal(id) and d.has(id):
				d[id] = int(d[id])
		d.fame = int(d.get("fame", 2))
		d.target = bool(d.get("target", true))
		if not d.has("aliases"):
			d.aliases = []
		if not d.has("ingredients"):
			d.ingredients = []
		if not d.has("profile"):
			d.profile = []
		d.ingredient_count = d.ingredients.size()
		_list.append(d)
		_by_id[d.id] = d


static func all() -> Array:
	_ensure()
	return _list


static func size() -> int:
	return all().size()


static func get_drink(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func has(id: String) -> bool:
	_ensure()
	return _by_id.has(id)


static func name_of(id: String) -> String:
	return String(get_drink(id).get("name", id))


## Drinks that may be a daily answer (undisputed profile).
static func targets() -> Array:
	var out: Array = []
	for d in all():
		if d.target:
			out.append(d)
	return out


## The six compared values as one key: drinks with equal keys can never be told apart.
static func profile_key(d: Dictionary) -> String:
	var parts: Array = []
	for id in Schema.ids():
		parts.append(str(d.get(id)))
	return "|".join(parts)


## Schema problems in the database: missing fields, unknown values, duplicate ids/names.
## Empty when the data is sound (a test enforces this).
static func validate() -> Array:
	var errs: Array = []
	var ids := {}
	var names := {}
	for d in all():
		for f in REQUIRED:
			if not d.has(f):
				errs.append("%s: missing %s" % [d.get("id", "?"), f])
		for id in Schema.ids():
			if not Schema.valid_value(id, d.get(id)):
				errs.append("%s: bad %s value %s" % [d.id, id, str(d.get(id))])
		if ids.has(d.id):
			errs.append("duplicate id " + d.id)
		ids[d.id] = true
		var n := String(d.name).to_lower()
		if names.has(n):
			errs.append("duplicate name " + d.name)
		names[n] = true
		if not d.target and String(d.get("why", "")) == "":
			errs.append("%s: target=false needs a 'why'" % d.id)
		if d.ingredients.is_empty():
			errs.append("%s: no ingredients" % d.id)
		if d.fame < 1 or d.fame > 3:
			errs.append("%s: fame must be 1-3" % d.id)
	return errs


## Hash of everything that decides answers and difficulty (ids, profiles, target/fame flags) plus
## the schema. Pinned files record it so they can tell when the database has changed.
static func fingerprint() -> int:
	var parts: Array = [str(Schema.attrs())]
	for d in all():
		parts.append("%s=%s:%s:%d" % [d.id, profile_key(d), str(d.target), d.fame])
	return absi("\n".join(parts).hash())
