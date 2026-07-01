# main.gd
# God Doodle - Faithful Godot replica of Terry Davis' God Doodle from TempleOS
# Features interactive space-bar entropy feeding, progressive geometric drawing,
# smoothing, and PNG export.

extends Control

const DOODLE_W := 640
const DOODLE_H := 480

# EGA-like 16 color palette (TempleOS style)
var palette: Array[Color] = [
	Color(0.0, 0.0, 0.0),        # 0 BLACK
	Color(0.0, 0.0, 0.67),       # 1 BLUE
	Color(0.0, 0.67, 0.0),       # 2 GREEN
	Color(0.0, 0.67, 0.67),      # 3 CYAN
	Color(0.67, 0.0, 0.0),       # 4 RED
	Color(0.67, 0.0, 0.67),      # 5 MAGENTA
	Color(0.67, 0.33, 0.0),      # 6 BROWN
	Color(0.67, 0.67, 0.67),     # 7 LTGRAY
	Color(0.33, 0.33, 0.33),     # 8 DKGRAY
	Color(0.33, 0.33, 1.0),      # 9 LTBLUE
	Color(0.33, 1.0, 0.33),      #10 LTGREEN
	Color(0.33, 1.0, 1.0),       #11 LTCYAN
	Color(1.0, 0.33, 0.33),      #12 LTRED
	Color(1.0, 0.33, 1.0),       #13 LTMAGENTA
	Color(1.0, 1.0, 0.33),       #14 YELLOW
	Color(1.0, 1.0, 1.0),        #15 WHITE
]

# Runtime doodle state
var color_indices: PackedByteArray
var doodle_texture: ImageTexture
var rgb_image: Image   # cached for display/export

var current_color: int = 0

# Generation state (ported from GodDoodle.HC)
var bit_fifo: Array = []  # Array[int] 0/1  LSB first insert order
var gen_layer: int = 0
var gen_prim: int = 0
var gen_fill: int = 0
var gen_phase: int = 0   # 0=prim outlines, 1=fills, 2=done layer smooth
var doodle_done: bool = false
var generating: bool = false

# UI refs (set in _ready)
@onready var doodle_rect: TextureRect = $CenterContainer/DoodlePanel/DoodleRect
@onready var status_label: Label = $StatusLabel
@onready var title_label: Label = $TitleLabel
@onready var file_dialog: FileDialog = $FileDialog
@onready var timestamp_label: Label = $TimestampLabel

var blink_timer: float = 0.0

func _ready() -> void:
	# Setup initial UI
	if title_label:
		title_label.text = "GOD DOODLE"
	
	# Make doodle rect keep aspect and use nearest for retro pixel feel
	if doodle_rect:
		doodle_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		doodle_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	
	# File dialog setup
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = ["*.png ; PNG Images"]
		file_dialog.file_selected.connect(_on_file_selected)
	
	# Initial empty doodle
	clear_doodle()
	update_display()
	update_status("Press SPACE to start a new God Doodle")

	# Keyboard focus
	set_process_input(true)
	set_process(true)

	# Prime the visible holy timing clock (universe time)
	if timestamp_label:
		timestamp_label.text = "%d" % get_universe_ms()

func _process(delta: float) -> void:   
	blink_timer += delta
	if not generating and not doodle_done and status_label:
		# Very subtle blink for initial instruction (only while idle)
		var alpha: float = 0.85 + 0.15 * sin(blink_timer * 3.0)
		status_label.modulate.a = alpha
	else:
		if status_label:
			status_label.modulate.a = 1.0
	if timestamp_label:
		timestamp_label.text = "%d" % get_universe_ms()

func clear_doodle() -> void:
	color_indices = PackedByteArray()
	color_indices.resize(DOODLE_W * DOODLE_H)
	for i in range(color_indices.size()):
		color_indices[i] = 15  # WHITE
	current_color = 15
	doodle_done = false
	generating = false
	bit_fifo.clear()
	gen_layer = 0
	gen_prim = 0
	gen_fill = 0
	gen_phase = 0
	rgb_image = null
	update_display()

func dc_fill(col_idx: int) -> void:
	current_color = col_idx
	for i in range(color_indices.size()):
		color_indices[i] = col_idx
	mark_dirty()

func set_color(col_idx: int) -> void:
	current_color = clamp(col_idx, 0, 15)

func get_idx(x: int, y: int) -> int:
	if x < 0 or x >= DOODLE_W or y < 0 or y >= DOODLE_H:
		return -1
	return color_indices[y * DOODLE_W + x]

func set_idx(x: int, y: int, c: int) -> void:
	if x < 0 or x >= DOODLE_W or y < 0 or y >= DOODLE_H:
		return
	color_indices[y * DOODLE_W + x] = clamp(c, 0, 15) as int
	mark_dirty()

func mark_dirty() -> void:
	# Will rebuild on update_display
	pass

func plot(x: int, y: int) -> void:
	set_idx(x, y, current_color)

# Bresenham line (doodle pixel buffer, not CanvasItem)
func doodle_draw_line(x0: int, y0: int, x1: int, y1: int) -> void:
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		plot(x0, y0)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func draw_border(x1: float, y1: float, x2: float, y2: float) -> void:
	var ix1: int = int(round(x1))
	var iy1: int = int(round(y1))
	var ix2: int = int(round(x2))
	var iy2: int = int(round(y2))
	doodle_draw_line(ix1, iy1, ix2, iy1)
	doodle_draw_line(ix2, iy1, ix2, iy2)
	doodle_draw_line(ix2, iy2, ix1, iy2)
	doodle_draw_line(ix1, iy2, ix1, iy1)

# Parametric ellipse/circle (good enough for doodle fidelity)
func doodle_draw_ellipse(cx: float, cy: float, rx: float, ry: float) -> void:
	if rx <= 1.0 and ry <= 1.0:
		plot(int(round(cx)), int(round(cy)))
		return
	var steps: int = int(max(32, max(rx, ry) * 4.0))
	var prev_x: int = 0
	var prev_y: int = 0
	for i in range(steps + 1):
		var ang: float = (TAU * i) / steps
		var px: float = cx + rx * cos(ang)
		var py: float = cy + ry * sin(ang)
		var ix: int = int(round(px))
		var iy: int = int(round(py))
		if i > 0:
			# connect to reduce gaps
			doodle_draw_line(prev_x, prev_y, ix, iy)
		prev_x = ix
		prev_y = iy

func doodle_draw_circle(cx: float, cy: float, r: float) -> void:
	doodle_draw_ellipse(cx, cy, r, r)

# Flood fill (4-connected, replaces seed color with current)
func flood_fill(seed_x: int, seed_y: int) -> void:
	var target: int = get_idx(seed_x, seed_y)
	if target < 0 or target == current_color:
		return
	var q: Array[Vector2i] = [Vector2i(seed_x, seed_y)]
	var visited: Dictionary = {}  # use dict for visited to be safe
	while q.size() > 0:
		var p: Vector2i = q.pop_front()
		var x: int = p.x
		var y: int = p.y
		var key: int = y * DOODLE_W + x
		if visited.has(key): 
			continue
		visited[key] = true
		if x < 0 or x >= DOODLE_W or y < 0 or y >= DOODLE_H:
			continue
		if get_idx(x, y) != target:
			continue
		set_idx(x, y, current_color)
		q.append(Vector2i(x + 1, y))
		q.append(Vector2i(x - 1, y))
		q.append(Vector2i(x, y + 1))
		q.append(Vector2i(x, y - 1))

# The key smoothing ported exactly: most common neighbor color in window
func god_doodle_smooth(num: int) -> void:
	var copy_indices: PackedByteArray = color_indices.duplicate()
	var old_c: int = current_color
	var w: int = DOODLE_W
	var h: int = DOODLE_H
	for y in range(h):
		for x in range(w):
			var histogram: Array = []
			histogram.resize(16)
			histogram.fill(0)
			for y1 in range(y - num, y + num + 1):
				for x1 in range(x - num, x + num + 1):
					if x1 >= 0 and x1 < w and y1 >= 0 and y1 < h:
						var c: int = copy_indices[y1 * w + x1]
						if c >= 0 and c <= 15:
							histogram[c] += 1
			var best: int = 0
			var best_cnt: int = -1
			for i in range(16):
				if histogram[i] > best_cnt:
					best = i
					best_cnt = histogram[i]
			color_indices[y * w + x] = best
	current_color = old_c
	mark_dirty()

# Bit fifo management - matches TempleOS fifo behavior
func feed_bits(num_bits: int, n: int) -> void:
	# Insert LSB first like original: n&1 then >>=
	for i in range(num_bits):
		bit_fifo.append(n & 1)
		n >>= 1

func get_bits_safe(num_bits: int) -> int:
	var res: int = 0
	for _i in range(num_bits):
		if bit_fifo.size() == 0:
			return -1  # signal need more
		var b: int = bit_fifo.pop_front()
		res = (res << 1) + b
	return res

func get_entropy() -> int:
	# "Time in the universe": real wall-clock milliseconds since Unix epoch.
	# This is the true cosmic timing (not engine uptime) for Holy Spirit puppetry.
	# Lower/middle bits of the absolute ms timestamp give the entropy on each SPACE.
	var t: int = int(Time.get_unix_time_from_system() * 1000.0)
	return (t >> 4) & 0xFFFFFF   # 24 bits worth

func get_universe_ms() -> int:
	# Current real time in milliseconds since the epoch (for the visible clock and entropy).
	return int(Time.get_unix_time_from_system() * 1000.0)

func feed_entropy(num: int = 24) -> void:
	feed_bits(num, get_entropy())
	# Status is managed by caller / start / main messages; avoid flash on every press.

# Core generation stepper - one "action" per call (after feed)
func try_advance_generation() -> bool:
	if doodle_done or not generating:
		return false
	var w: float = float(DOODLE_W)
	var h: float = float(DOODLE_H)
	var min_bits_needed: int = 12  # conservative
	if bit_fifo.size() < min_bits_needed:
		return false

	if gen_layer >= 3:
		_finish_doodle()
		return true

	if gen_phase == 0:
		# Draw outlines (29 primitives)
		if gen_prim < 29:
			if bit_fifo.size() < 24:
				return false
			var b3: int = get_bits_safe(3)
			if b3 < 0:
				return false
			set_color(4)  # RED
			if b3 == 0:
				# Ellipse: cx,cy, rx,ry   5+5+5+5
				var bx: int = get_bits_safe(5); if bx < 0: return false
				var by: int = get_bits_safe(5); if by < 0: return false
				var brx: int = get_bits_safe(5); if brx < 0: return false
				var bry: int = get_bits_safe(5); if bry < 0: return false
				var cx: float = (w - 1.0) * bx / 15.5 - w / 2.0
				var cy: float = (h - 1.0) * by / 15.5 - h / 2.0
				var rx: float = (w - 1.0) * brx / 15.5
				var ry: float = (h - 1.0) * bry / 15.5
				doodle_draw_ellipse(cx, cy, rx, ry)
			elif b3 == 1:
				# Circle
				var bx: int = get_bits_safe(5); if bx < 0: return false
				var by: int = get_bits_safe(5); if by < 0: return false
				var br: int = get_bits_safe(5); if br < 0: return false
				var cx: float = (w - 1.0) * bx / 15.5 - w / 2.0
				var cy: float = (h - 1.0) * by / 15.5 - h / 2.0
				var r: float = (w - 1.0) * br / 15.5
				doodle_draw_circle(cx, cy, r)
			elif b3 == 2:
				# Border
				var bx: int = get_bits_safe(5); if bx < 0: return false
				var by: int = get_bits_safe(5); if by < 0: return false
				var bx2: int = get_bits_safe(5); if bx2 < 0: return false
				var by2: int = get_bits_safe(5); if by2 < 0: return false
				var cx: float = (w - 1.0) * bx / 15.5 - w / 2.0
				var cy: float = (h - 1.0) * by / 15.5 - h / 2.0
				var x2: float = (w - 1.0) * bx2 / 15.5
				var y2: float = (h - 1.0) * by2 / 15.5
				draw_border(cx, cy, x2, y2)
			else:
				# Line (most common)
				var bx1: int = get_bits_safe(4); if bx1 < 0: return false
				var by1: int = get_bits_safe(4); if by1 < 0: return false
				var bx2: int = get_bits_safe(4); if bx2 < 0: return false
				var by2: int = get_bits_safe(4); if by2 < 0: return false
				var x1: float = (w - 1.0) * bx1 / 15.0
				var y1: float = (h - 1.0) * by1 / 15.0
				var x2: float = (w - 1.0) * bx2 / 15.0
				var y2: float = (h - 1.0) * by2 / 15.0
				doodle_draw_line(int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2)))
			gen_prim += 1
			update_display()
			return true
		else:
			gen_phase = 1
			gen_fill = 0
			return try_advance_generation()

	elif gen_phase == 1:
		# 6 flood fills
		if gen_fill < 6:
			if bit_fifo.size() < 12:
				return false
			var bx: int = get_bits_safe(5); if bx < 0: return false
			var by: int = get_bits_safe(5); if by < 0: return false
			var bc: int = get_bits_safe(2); if bc < 0: return false
			var fx: float = (w - 1.0) * bx / 31.0 + w / 64.0
			var fy: float = (h - 1.0) * by / 31.0 + h / 64.0
			match bc:
				0: set_color(0)   # BLACK
				1: set_color(8)   # DKGRAY
				2: set_color(7)   # LTGRAY
				_: set_color(15)  # WHITE
			flood_fill(int(round(fx)), int(round(fy)))
			gen_fill += 1
			update_display()
			return true
		else:
			# Smooth after fills
			god_doodle_smooth(3)
			update_display()
			gen_layer += 1
			gen_prim = 0
			gen_fill = 0
			gen_phase = 0
			if gen_layer >= 3:
				_finish_doodle()
			return true

	return false

func _finish_doodle() -> void:
	doodle_done = true
	generating = false
	bit_fifo.clear()
	update_status("God Doodle complete! CTRL+S=save, SHIFT+ESC=discard")
	update_display()

func start_new_doodle() -> void:
	clear_doodle()
	generating = true
	doodle_done = false
	
	# Initial message
	update_status("The Holy Spirit can puppet you. Press SPACE repeatedly until it finishes.")
	
	# Draw first bits immediately
	for _i in range(4):
		feed_entropy(24)
		try_advance_generation()
	update_display()

func update_display() -> void:
	# Rebuild rgb image from indices
	if rgb_image == null or rgb_image.get_width() != DOODLE_W:
		rgb_image = Image.create(DOODLE_W, DOODLE_H, false, Image.FORMAT_RGB8)
	
	for y in range(DOODLE_H):
		for x in range(DOODLE_W):
			var idx: int = color_indices[y * DOODLE_W + x]
			rgb_image.set_pixel(x, y, palette[idx])
	
	if doodle_texture == null:
		doodle_texture = ImageTexture.create_from_image(rgb_image)
	else:
		doodle_texture.update(rgb_image)
	
	if doodle_rect:
		doodle_rect.texture = doodle_texture

func update_status(text: String) -> void:
	if status_label:
		status_label.text = text
		status_label.modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		var shifted: bool = event.shift_pressed
		
		if kc == KEY_SPACE:
			if generating:
				feed_entropy(24)
				# Advance as far as current bits allow (usually ~1 primitive)
				var advanced: int = 0
				while advanced < 3 and try_advance_generation():
					advanced += 1
				update_display()
			elif not doodle_done:
				start_new_doodle()
			# else: doodle_done -- do nothing until explicitly discard (SHIFT+ESC) or (after save) discard to start new. Prevents accidental clear.
			get_viewport().set_input_as_handled()
			return
		
		if kc == KEY_ENTER or kc == KEY_KP_ENTER:
			if generating:
				# Clear like \n in original
				dc_fill(15)
				bit_fifo.clear()
				update_display()
				update_status("Canvas cleared. Keep pressing SPACE.")
			get_viewport().set_input_as_handled()
			return
		
		if kc >= KEY_0 and kc <= KEY_9:
			if generating or doodle_done:
				var num: int = kc - KEY_0
				god_doodle_smooth(num)
				update_display()
				update_status("Smoothed (level %d)" % num)
			get_viewport().set_input_as_handled()
			return
		
		if kc == KEY_ESCAPE:
			if generating:
				# Treat as done early? or cancel
				_finish_doodle()
			elif doodle_done and shifted:
				# SHIFT-ESC : discard (clear for new)
				clear_doodle()
				update_display()
				update_status("Discarded. Press SPACE for new God Doodle.")
			elif not doodle_done:
				clear_doodle()
				update_display()
			# plain ESC when done: do nothing (redundant, use save or discard; key consumed)
			get_viewport().set_input_as_handled()
			return
		
		if (kc == KEY_S or kc == KEY_S) and event.ctrl_pressed:
			_export_png()
			get_viewport().set_input_as_handled()
			return

func _export_png() -> void:
	if not rgb_image:
		update_status("No doodle to export yet!")
		return
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var suggested: String = "god_doodle_%s.png" % ts
	if file_dialog:
		file_dialog.current_file = suggested
		file_dialog.popup_centered_ratio(0.6)
	else:
		# fallback direct
		var path: String = OS.get_user_data_dir().path_join(suggested)
		_save_to_path(path)

func _on_file_selected(path: String) -> void:
	_save_to_path(path)

func _save_to_path(path: String) -> void:
	if rgb_image:
		var err: Error = rgb_image.save_png(path)
		if err == OK:
			if doodle_done:
				update_status("Saved: " + path + "  (SHIFT+ESC to discard for new)")
			else:
				update_status("Saved: " + path)
		else:
			update_status("Failed to save PNG (error %d)" % err)

# Optional: allow clicking on canvas area to feed too (nice UX)
func _on_doodle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if generating:
			feed_entropy(24)
			var adv: int = 0
			while adv < 2 and try_advance_generation():
				adv += 1
			update_display()
		elif not doodle_done:
			start_new_doodle()
