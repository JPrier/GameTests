extends SceneTree
## Prints the golden flight checksums used by tests/test_physics.gd.
##   godot --headless --path . -s tools/checksums.gd

const T = preload("res://tests/test_physics.gd")


func _init() -> void:
	print(T.golden_checksums())
	quit()
