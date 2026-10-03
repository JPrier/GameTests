extends SceneTree
## Works out which parts of the Godot engine a game uses, so CI can build a web
## engine that contains exactly those parts and nothing else.
##
##   godot --headless --path games/<name> --script res://../../.github/engine/detect-features.gd \
##     -- --modules=modules.json --out=features.json
##
## (Any absolute path to this file works for --script.)
##
## It scans every file Godot would see (skipping .godot/ and folders with a
## .gdignore) and treats a word as "used" when it is the name of an engine class:
##   * scenes, resources, project and import files: every word, quoted or not
##     (scenes name their node types in quotes: type="Sprite2D");
##   * GDScript: code only, with comments and strings removed, so a check such as
##     n.is_class("Node3D") doesn't pull 3D in. Exception: a script that mentions
##     ClassDB also has its quoted class names counted, for ClassDB.instantiate("X").
## Over-including is cheap and under-including breaks the game, so every rule
## below leans towards keeping a feature. The browser tests in CI are the safety
## net for anything this misses; a game can force things in with engine.json:
##   {"include": ["AudioStreamPlayer"], "flags": ["module_noise_enabled=yes"]}
## or opt out entirely with {"engine": "stock"}.

const TEXT_EXT := ["gd", "tscn", "tres", "godot", "cfg", "import", "json", "csv", "po", "gdshader", "txt", "md"]
# Plain data files: scanned for non-Latin text, but their words (names in a data
# set, say) are not engine class references.
const DATA_EXT := ["json", "csv", "po", "txt", "md"]
const COMPLEX_SCRIPT_RANGES := [
	[0x0590, 0x08FF],  # Hebrew, Arabic, Syriac, Thaana, NKo, ...
	[0x0900, 0x0DFF],  # Indic scripts
	[0x0E00, 0x0FFF],  # Thai, Lao, Tibetan
	[0x1000, 0x109F],  # Myanmar
	[0x1780, 0x18AF],  # Khmer, Mongolian
	[0xFB1D, 0xFDFF],  # Hebrew/Arabic presentation forms
	[0xFE70, 0xFEFF],
]
const PHYSICS_2D_ROOTS := ["CollisionObject2D", "CollisionPolygon2D", "CollisionShape2D", "Joint2D",
	"PhysicsServer2D", "PhysicsServer2DManager", "ShapeCast2D", "RayCast2D", "TouchScreenButton", "Shape2D",
	"PhysicsDirectSpaceState2D", "PhysicsRayQueryParameters2D", "PhysicsShapeQueryParameters2D",
	"PhysicsPointQueryParameters2D", "PhysicsTestMotionParameters2D", "PhysicsMaterial"]
const PHYSICS_3D_ROOTS := ["CollisionObject3D", "CollisionPolygon3D", "CollisionShape3D", "CSGShape3D",
	"GPUParticlesAttractor3D", "GPUParticlesCollision3D", "Joint3D", "PhysicalBoneSimulator3D",
	"PhysicsServer3D", "PhysicsServer3DManager", "RayCast3D", "SoftBody3D", "SpringArm3D", "VehicleWheel3D",
	"Shape3D", "PhysicsDirectSpaceState3D", "PhysicsRayQueryParameters3D", "PhysicsShapeQueryParameters3D",
	"PhysicsPointQueryParameters3D"]
# Classes removed by disable_advanced_gui (scene/register_scene_types.cpp).
const ADVANCED_GUI := ["AcceptDialog", "CharFXTransform", "CodeEdit", "CodeHighlighter", "ColorPicker",
	"ColorPickerButton", "ConfirmationDialog", "FileDialog", "FoldableContainer", "FoldableGroup", "GraphEdit",
	"GraphElement", "GraphFrame", "GraphNode", "HSplitContainer", "MenuBar", "MenuButton", "OptionButton",
	"PopupMenu", "RichTextEffect", "RichTextLabel", "SpinBox", "SplitContainer", "SubViewportContainer",
	"SyntaxHighlighter", "TextEdit", "Tree", "TreeItem", "VSplitContainer", "VirtualJoystick"]
const TLS_CLASSES := ["Crypto", "CryptoKey", "X509Certificate", "HMACContext", "TLSOptions", "StreamPeerTLS",
	"DTLSServer", "PacketPeerDTLS"]
# Image loaders that only matter when a game decodes images at runtime.
const IMAGE_LOADERS := {
	"load_svg_from_buffer": "svg", "load_svg_from_string": "svg",
	"load_webp_from_buffer": "webp", "save_webp": "webp", "save_webp_to_buffer": "webp",
	"load_jpg_from_buffer": "jpg", "save_jpg": "jpg", "save_jpg_to_buffer": "jpg",
	"load_bmp_from_buffer": "bmp", "load_tga_from_buffer": "tga", "load_ktx_from_buffer": "ktx",
	"save_exr": "tinyexr", "save_exr_to_buffer": "tinyexr",
}

var _word_re := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var report := detect(str(args.get("modules", "")))
	var text := JSON.stringify(report, "  ", true)
	if args.get("out", "") != "":
		var f := FileAccess.open(args.out, FileAccess.WRITE)
		f.store_string(text + "\n")
	else:
		print(text)
	quit(0)


func detect(modules_path: String) -> Dictionary:
	var override := _read_json("res://engine.json")
	var files: Array[String] = []
	_walk("res://", files)

	var words := {}
	var exts := {}
	var import_text := ""
	var complex_text := false
	for path in files:
		var ext := path.get_extension().to_lower()
		exts[ext] = true
		if not TEXT_EXT.has(ext):
			continue
		var text := FileAccess.get_file_as_string(path)
		if ext == "import":
			import_text += text + "\n"
		if not complex_text and _has_complex_script(text):
			complex_text = true
		if ext == "gd":
			var parts := _split_gdscript(text)
			_add_words(parts[0], words)
			if parts[0].contains("ClassDB"):
				_add_words(parts[1], words)
		elif not DATA_EXT.has(ext):
			_add_words(text, words)

	# Engine classes the game names, plus everything they inherit from.
	var all_classes := {}
	for c in ClassDB.get_class_list():
		all_classes[c] = true
	var used := {}
	for w in words:
		if all_classes.has(w):
			_add_with_parents(w, used)
	for c in override.get("include", []):
		if ClassDB.class_exists(c):
			_add_with_parents(c, used)

	var modules := {"gdscript": true, "freetype": true}
	var f := {}  # feature -> reason (first class or file that needed it)
	var reason := func(feature: String, why: String) -> void:
		if not f.has(feature):
			f[feature] = why

	for c in used:
		if c.ends_with("3D") or ClassDB.is_parent_class(c, "Node3D") or ["Environment", "Sky", "WorldEnvironment"].has(c):
			reason.call("3d", c)
		if _descends(c, PHYSICS_2D_ROOTS) or (c.begins_with("Physics") and c.ends_with("2D")):
			reason.call("physics_2d", c)
		if _descends(c, PHYSICS_3D_ROOTS) or (c.begins_with("Physics") and c.ends_with("3D")):
			reason.call("physics_3d", c)
		if c.begins_with("Navigation") and (c.ends_with("2D") or c == "NavigationPolygon"):
			reason.call("navigation_2d", c)
		if c.begins_with("Navigation") and (c.ends_with("3D") or c == "NavigationMesh"):
			reason.call("navigation_3d", c)
		if c.begins_with("XR") or c.begins_with("OpenXR") or c == "WebXRInterface" or c == "MobileVRInterface":
			reason.call("xr", c)
		if _descends(c, ADVANCED_GUI):
			reason.call("advanced_gui", c)
		if c == "Control" or ClassDB.is_parent_class(c, "Control"):
			reason.call("svg (default theme icons)", c)
			modules["svg"] = true
		if TLS_CLASSES.has(c):
			modules["mbedtls"] = true

	# Modules that register classes: on when any of their classes is used.
	var module_map := _read_json(modules_path)
	for m in module_map:
		for c in module_map[m].get("classes", []):
			if used.has(c):
				modules[m] = true
				break
	for word in IMAGE_LOADERS:
		if words.has(word):
			modules[IMAGE_LOADERS[word]] = true
	if import_text.contains("importer=\"texture\"") or import_text.contains("importer=\"texture_atlas\""):
		modules["webp"] = true  # imported textures may be stored as WebP
	if import_text.contains("multichannel_signed_distance_field=true"):
		modules["msdfgen"] = true
	if import_text.contains("importer=\"csv_translation\"") or exts.has("po") or exts.has("translation"):
		complex_text = true  # translations: keep full text shaping to be safe
	if complex_text or used.has("TextServerAdvanced"):
		modules["text_server_adv"] = true
		reason.call("text_server_adv", "non-Latin text or translations")
	else:
		modules["text_server_fb"] = true

	if f.has("physics_2d"):
		modules["godot_physics_2d"] = true
	if f.has("physics_3d"):
		var engine := str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
		modules["jolt_physics" if engine == "Jolt Physics" else "godot_physics_3d"] = true
	if f.has("navigation_2d"):
		modules["navigation_2d"] = true
	if f.has("navigation_3d"):
		modules["navigation_3d"] = true

	# Pull in module dependencies (e.g. vorbis needs ogg).
	var changed := true
	while changed:
		changed = false
		for m in modules.keys():
			for d in module_map.get(m, {}).get("deps", []):
				if not modules.has(d):
					modules[d] = true
					changed = true

	var flags := [
		"modules_enabled_by_default=no",
		"disable_3d=%s" % ("no" if f.has("3d") else "yes"),
		"disable_physics_2d=%s" % ("no" if f.has("physics_2d") else "yes"),
		"disable_physics_3d=%s" % ("no" if f.has("physics_3d") else "yes"),
		"disable_navigation_2d=%s" % ("no" if f.has("navigation_2d") else "yes"),
		"disable_navigation_3d=%s" % ("no" if f.has("navigation_3d") else "yes"),
		"disable_xr=%s" % ("no" if f.has("xr") else "yes"),
		"disable_advanced_gui=%s" % ("no" if f.has("advanced_gui") else "yes"),
		"minizip=%s" % ("yes" if modules.has("zip") else "no"),
	]
	for m in modules:
		flags.append("module_%s_enabled=yes" % m)
	for extra in override.get("flags", []):
		flags.append(str(extra))
	flags.sort()

	var v := Engine.get_version_info()
	var version := "%d.%d.%d" % [v.major, v.minor, v.patch]
	var engine_kind := str(override.get("engine", "slim"))
	return {
		"project": ProjectSettings.get_setting("application/config/name", ""),
		"godot": version,
		"engine": engine_kind,
		"key": ("stock-" + version) if engine_kind == "stock" else ("%s-%s" % [version, ("|".join(flags)).sha256_text().substr(0, 12)]),
		"flags": flags,
		"features": f,
		"modules": modules.keys(),
		"classes": used.size(),
	}


## Splits GDScript source into [code, string contents], dropping comments.
func _split_gdscript(text: String) -> Array:
	var code := PackedStringArray()
	var strs := PackedStringArray()
	var i := 0
	var n := text.length()
	var start := 0
	while i < n:
		var ch := text[i]
		if ch == "#":
			code.append(text.substr(start, i - start))
			while i < n and text[i] != "\n":
				i += 1
			start = i
		elif ch == "\"" or ch == "'":
			code.append(text.substr(start, i - start))
			var triple := text.substr(i, 3) == ch + ch + ch
			var q := ch + ch + ch if triple else ch
			var j := i + q.length()
			while j < n:
				if text[j] == "\\":
					j += 2
					continue
				if text.substr(j, q.length()) == q:
					break
				if not triple and text[j] == "\n":
					break
				j += 1
			strs.append(text.substr(i + q.length(), j - i - q.length()))
			i = j + q.length()
			start = i
			code.append(" ")
			continue
		i += 1
	code.append(text.substr(start))
	return ["".join(code), " ".join(strs)]


func _walk(dir: String, out: Array[String]) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		_walk(dir.path_join(d), out)
	for file in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file))


func _add_words(text: String, into: Dictionary) -> void:
	for m in _word_re.search_all(text):
		into[m.get_string()] = true


func _add_with_parents(c: StringName, used: Dictionary) -> void:
	while c != &"" and not used.has(c):
		used[c] = true
		c = ClassDB.get_parent_class(c)


func _descends(c: String, roots: Array) -> bool:
	for r in roots:
		if c == r or (ClassDB.class_exists(r) and ClassDB.is_parent_class(c, r)):
			return true
	return false


func _has_complex_script(text: String) -> bool:
	for i in text.length():
		var u := text.unicode_at(i)
		if u < 0x0590:
			continue
		for r in COMPLEX_SCRIPT_RANGES:
			if u >= r[0] and u <= r[1]:
				return true
	return false


func _read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}
