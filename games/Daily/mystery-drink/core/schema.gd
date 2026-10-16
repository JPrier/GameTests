extends RefCounted
## The six compared attributes (data/schema.json): kinds, value labels, related groups.
## Pure data access, no UI.

const PATH := "res://data/schema.json"

## Feedback codes, one per attribute.
const EXACT := 0      # 🟩 same value
const PARTIAL := 1    # 🟨 different value, same group (e.g. lemon vs lime: both citrus)
const MISS := 2       # 🟥 unrelated
const HIGHER := 3     # ⬆️ ordinal: the mystery drink is higher than the guess
const LOWER := 4      # ⬇️ ordinal: the mystery drink is lower than the guess

static var _attrs: Array = []
static var _by_id: Dictionary = {}
static var _group_of: Dictionary = {}      # attr -> value -> group id
static var _group_label: Dictionary = {}   # attr -> group id -> label
static var version := 0


static func _ensure() -> void:
	if not _attrs.is_empty():
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(data is Dictionary, "schema.json must parse")
	version = int(data.get("version", 0))
	for a in data.attributes:
		_attrs.append(a)
		_by_id[a.id] = a
		var gm := {}
		var gl := {}
		for g in a.get("groups", []):
			gl[g.id] = g.label
			for m in g.members:
				gm[m] = g.id
		_group_of[a.id] = gm
		_group_label[a.id] = gl


static func attrs() -> Array:
	_ensure()
	return _attrs


static func ids() -> Array:
	_ensure()
	var out: Array = []
	for a in _attrs:
		out.append(a.id)
	return out


static func count() -> int:
	return attrs().size()


static func attr(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func kind(id: String) -> String:
	return String(attr(id).get("kind", ""))


static func label(id: String) -> String:
	return String(attr(id).get("label", id))


## Every legal value of a category/bool attribute, or every level of an ordinal one.
static func values(id: String) -> Array:
	var a := attr(id)
	match String(a.get("kind", "")):
		"category":
			return a.values.keys()
		"bool":
			return [true, false]
		"ordinal":
			var out: Array = []
			for i in a.levels.size():
				out.append(int(a.min) + i)
			return out
	return []


static func valid_value(id: String, v) -> bool:
	match kind(id):
		"category":
			return typeof(v) == TYPE_STRING and attr(id).values.has(v)
		"bool":
			return typeof(v) == TYPE_BOOL
		"ordinal":
			var a := attr(id)
			return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) == v \
				and int(v) >= int(a.min) and int(v) < int(a.min) + a.levels.size()
	return false


## Human label for a value: "Sparkling wine", "Fizzy", "Very sweet".
static func value_label(id: String, v) -> String:
	var a := attr(id)
	match String(a.get("kind", "")):
		"category":
			return String(a.values.get(v, str(v)))
		"bool":
			return String(a.values["true" if v else "false"])
		"ordinal":
			var i := int(v) - int(a.min)
			if i >= 0 and i < a.levels.size():
				return String(a.levels[i])
	return str(v)


static func group_of(id: String, v) -> String:
	_ensure()
	if typeof(v) != TYPE_STRING:
		return ""
	return String(_group_of.get(id, {}).get(v, ""))


static func group_label(id: String, g: String) -> String:
	_ensure()
	return String(_group_label.get(id, {}).get(g, g))


static func groups(id: String) -> Array:
	return attr(id).get("groups", [])


static func is_ordinal(id: String) -> bool:
	return kind(id) == "ordinal"


static func code_emoji(code: int) -> String:
	match code:
		EXACT: return "🟩"
		PARTIAL: return "🟨"
		HIGHER: return "⬆️"
		LOWER: return "⬇️"
	return "🟥"
