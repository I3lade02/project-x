extends Control
## Minimapa v pravém dolním rohu: plochý 2D pohled na aktuální sektor (+ chodbu a další sektor),
## nepřátelé (červeně), boss (ve své barvě), hráči, terminál, jádra a cesta dál.
## Podržením TAB se zvětší doprostřed obrazovky.

const SMALL = Vector2(250, 160)        # velikost v rohu
const MARGIN = 20.0
const PAD = 10.0
const HEADER = 16.0
const BG = Color(0.02, 0.02, 0.07, 0.78)
const FLOOR = Color(0.13, 0.15, 0.3, 1.0)
const FLOOR_NEXT = Color(0.09, 0.1, 0.2, 1.0)
const BLOCK = Color(0.42, 0.48, 0.72, 1.0)
const PLATE = Color(1.4, 0.45, 0.15, 0.8)
const ENEMY = Color(2.2, 0.35, 0.3, 1.0)
const P_COLORS = [Color(0.5, 1.8, 2.2), Color(2.2, 1.5, 0.6)]
const TERMINAL = Color(2.0, 1.6, 0.45)
const CORE = Color(1.6, 0.55, 2.3)

var arena
var big := false
var sig := []                          # podle čeho poznám, že se změnila mapa
var bmin := Vector2.ZERO
var scale_k := 1.0
var origin := Vector2.ZERO
var static_layer: Control              # podlaha a bloky (překresluje se jen při změně sektoru)
var dots_layer: Control                # nepřátelé, hráči… (každý snímek)


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not InputMap.has_action("map"):
		InputMap.add_action("map")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_TAB
		InputMap.action_add_event("map", ev)
	static_layer = _layer(_draw_static)
	dots_layer = _layer(_draw_dots)
	_apply_size()


func _layer(fn: Callable) -> Control:
	var c = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(fn.bind(c))
	add_child(c)
	return c


# malá v pravém dolním rohu / velká uprostřed (kotvy drží místo i při změně okna)
func _apply_size():
	if big:
		anchor_left = 0.19
		anchor_top = 0.15
		anchor_right = 0.81
		anchor_bottom = 0.85
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
	else:
		anchor_left = 1.0
		anchor_top = 1.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = -SMALL.x - MARGIN
		offset_top = -SMALL.y - MARGIN
		offset_right = -MARGIN
		offset_bottom = -MARGIN
	sig = []                            # přepočítat měřítko


func _process(_delta):
	if arena == null:
		arena = get_tree().current_scene
	var want_big = Input.is_action_pressed("map")
	if want_big != big:
		big = want_big
		_apply_size()
	var new_sig = [arena.current.get("root"), arena.next_arena.get("root"), arena.corridor.size(), size]
	if new_sig != sig:
		sig = new_sig
		_fit()
		static_layer.queue_redraw()
	queue_redraw()
	dots_layer.queue_redraw()


# všechna políčka, která mapa ukazuje
func _cells() -> Array:
	var out = []
	if not arena.current.is_empty():
		out.append([arena.current["layout"]["walk"], FLOOR])
	if not arena.corridor.is_empty():
		out.append([arena.corridor["tiles"], FLOOR])
	if not arena.next_arena.is_empty():
		out.append([arena.next_arena["layout"]["walk"], FLOOR_NEXT])
	return out


# měřítko, aby se vše vešlo do rámečku
func _fit():
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	for group in _cells():
		for c in group[0]:
			for p in [arena.iso_point(c.x, c.y), arena.iso_point(c.x + 1, c.y + 1), arena.iso_point(c.x + 1, c.y), arena.iso_point(c.x, c.y + 1)]:
				lo = lo.min(p)
				hi = hi.max(p)
	if lo.x == INF:
		return
	var area = size - Vector2(PAD * 2, PAD * 2 + HEADER)
	var span = (hi - lo).max(Vector2(1, 1))
	scale_k = minf(area.x / span.x, area.y / span.y)
	bmin = lo
	origin = Vector2(PAD, PAD + HEADER) + (area - span * scale_k) / 2.0


func to_map(p: Vector2) -> Vector2:
	return origin + (p - bmin) * scale_k


func _cell_poly(x: float, y: float, w := 1.0, h := 1.0) -> PackedVector2Array:
	return PackedVector2Array([to_map(arena.iso_point(x, y)), to_map(arena.iso_point(x + w, y)),
		to_map(arena.iso_point(x + w, y + h)), to_map(arena.iso_point(x, y + h))])


func _draw():
	var edge = Color(0.3, 1.1, 1.6)
	if arena and not arena.current.is_empty():
		edge = arena.current["theme"]["edge"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(BG, 0.92) if big else BG)
	draw_rect(Rect2(Vector2.ZERO, size), Color(edge, 0.8), false, 1.5)


func _draw_static(c: Control):
	if arena == null:
		return
	for group in _cells():
		for cell in group[0]:
			c.draw_colored_polygon(_cell_poly(cell.x, cell.y), group[1])
	for rt in [arena.current, arena.next_arena]:
		if rt.is_empty():
			continue
		var lay = rt["layout"]
		for p in lay["plates"]:
			c.draw_colored_polygon(_cell_poly(p.x, p.y), PLATE)
		for b in lay["blocks"]:
			var o = b["center"] - b["size"] / 2.0
			c.draw_colored_polygon(_cell_poly(o.x, o.y, b["size"].x, b["size"].y), BLOCK)


func _draw_dots(c: Control):
	if arena == null:
		return
	var font = get_theme_default_font()
	var t = Time.get_ticks_msec() / 1000.0
	var r = 1.0 if not big else 2.0            # velká mapa = větší značky
	# co je právě vidět na obrazovce
	var inv = get_viewport().get_canvas_transform().affine_inverse()
	var view = Rect2(to_map(inv * Vector2.ZERO), Vector2.ZERO).expand(to_map(inv * get_viewport_rect().size))
	view = view.intersection(Rect2(Vector2(2, PAD + HEADER - 4), size - Vector2(4, PAD + HEADER - 2)))
	if view.has_area():
		c.draw_rect(view, Color(1.6, 1.7, 2.2, 0.35), false, 1.0)
	# cesta dál
	if arena.exit_target != null:
		var e = to_map(arena.exit_target)
		var k = 5.0 * r + 2.0 * sin(t * 6.0)
		c.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -k), e + Vector2(k, 0), e + Vector2(0, k), e + Vector2(-k, 0)]), Color(1.8, 1.8, 2.2, 0.9))
	# terminál
	for term in get_tree().get_nodes_in_group("terminal"):
		var p = to_map(term.global_position)
		c.draw_rect(Rect2(p - Vector2(3, 3) * r, Vector2(6, 6) * r), TERMINAL)
	# jádra na zemi
	for core in get_tree().get_nodes_in_group("cores"):
		c.draw_circle(to_map(core.global_position), 2.0 * r, CORE)
	# nepřátelé
	var count = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var vis = e.get_node_or_null("Visual")
		if vis and vis.modulate.a < 0.4:       # skrytý rootkit se neprozradí
			continue
		count += 1
		var p = to_map(e.global_position)
		if e.is_in_group("boss"):
			var col = Color(e.burst_color, 1.0)
			c.draw_circle(p, 7.0 * r, Color(0, 0, 0, 0.8))
			c.draw_circle(p, (5.5 + 1.0 * sin(t * 5.0)) * r, col)
			c.draw_arc(p, 9.0 * r, 0, TAU, 20, Color(col, 0.5), 1.5)
		else:
			c.draw_circle(p, 3.6 * r, Color(0, 0, 0, 0.8))
			c.draw_circle(p, (2.7 + 0.4 * sin(t * 8.0 + p.x)) * r, ENEMY)
	# hráči
	for pl in arena.players:
		if pl.dead:
			continue
		var p = to_map(pl.global_position)
		var col = P_COLORS[clampi(pl.player_index, 0, 1)]
		var big_me = pl == arena.local_player
		c.draw_circle(p, (4.0 if big_me else 3.4) * r, Color(0, 0, 0, 0.8))
		c.draw_circle(p, (3.0 if big_me else 2.5) * r, col)
	# hlavička
	var txt = "NEPŘÁTELÉ  %d" % count if count > 0 else "SEKTOR ČISTÝ"
	c.draw_string(font, Vector2(PAD, PAD + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ENEMY if count > 0 else Color(0.6, 1.8, 0.9))
	c.draw_string(font, Vector2(size.x - PAD - 80, PAD + 8), "[TAB] mapa" if not big else "", HORIZONTAL_ALIGNMENT_RIGHT, 80, 11, Color(0.6, 0.65, 0.85))
