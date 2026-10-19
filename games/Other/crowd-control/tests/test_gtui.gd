extends GameTest
## Shared GameTests UI checks. Vendored into every game's tests/ by .github/scripts/sync-ui.py; edit ui/tests/.


func _main() -> Node:
	var main = await load_scene(ProjectSettings.get_setting("application/run/main_scene"))
	# wait for the first real screen (some games show a loading frame first)
	for i in 60:
		await wait_frames(1)
		if main is CanvasItem:
			main.queue_redraw()
		if i >= 2 and not GTUI.targets().is_empty():
			break
	return main


func test_gtui_palette_supplied():
	await _main()
	for k in GTUI.PALETTE_KEYS:
		assert_true(GTUI.pal.has(k), "palette has '%s' (call GTUI.setup in _ready)" % k)


func test_gtui_controls_are_registered():
	await _main()
	assert_gt(GTUI.targets().size(), 0, "the first screen draws its controls with GTUI (or GTUI.register)")


func test_gtui_touch_targets():
	await _main()
	var small := GTUI.undersized()
	assert_true(small.is_empty(), "controls under the 44 dp touch target: %s" % str(small))


func test_gtui_keyboard_focus():
	var main = await _main()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	GTUI.handle_input(tab)
	assert_ne(GTUI.focused_id(), "", "Tab focuses a control")
	var first := GTUI.focused_id()
	main.queue_redraw()
	await wait_frames(2)
	if GTUI._active_targets().size() > 1:
		GTUI.handle_input(tab)
		assert_ne(GTUI.focused_id(), first, "Tab moves to the next control")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	assert_true(GTUI.handle_input(esc).get("cancel", false), "Escape reports cancel")
