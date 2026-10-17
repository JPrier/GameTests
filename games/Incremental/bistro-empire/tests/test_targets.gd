extends GameTest
## Every tab's controls meet the shared 44 dp touch target (see ui/VISUAL_GUIDE.md).


func test_every_tab_meets_touch_targets():
	var main = await load_scene("res://main.tscn")
	await wait_frames(2)
	main.modal = ""
	var small: Array = []
	for t in main.TABS:
		main.set_tab(t)
		for step in 4:
			main.scroll[t] = float(main.scroll_max.get(t, 0.0)) * step / 3.0
			main.queue_redraw()
			main.content.queue_redraw()
			main.overlay.queue_redraw()
			await wait_frames(2)
			for u in GTUI.undersized():
				var key := "%s:%s" % [t, u.id]
				if not small.has(key):
					small.append(key)
	assert_true(small.is_empty(), "controls under the touch target: %s" % ", ".join(small))
