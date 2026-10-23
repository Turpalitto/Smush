extends Node
## Control experiment for the perf probe: what does an EMPTY scene cost per frame
## on this machine in headless mode? Without this number the probe's 6.90 ms could
## be the game or could be the loop's floor, and there is no way to tell.
##
## Result on this machine: an empty scene also reads 6.900 ms (144.9 fps), so the
## floor is the loop, not the game. This tries a few settings to get under it.

func _ready() -> void:
	for spec in [["max_fps=0", 0], ["max_fps=240", 240], ["max_fps=1000", 1000]]:
		Engine.max_fps = int(spec[1])
		var t0 := Time.get_ticks_usec()
		var last := t0
		var n := 0
		var total := 0.0
		while n < 300:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := float(now - last) / 1000.0
			last = now
			n += 1
			if n > 30:
				total += dt
		print("FRAME_FLOOR %s avg_ms=%.3f fps=%.1f" % [
			spec[0], total / float(n - 30), 1000.0 / (total / float(n - 30))])
	get_tree().quit(0)
