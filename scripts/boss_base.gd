extends "res://scripts/enemy_iso.gd"
## Společný základ všech bossů: 3 fáze podle HP, signály pro ukazatel HP,
## kreslení efektů na zemi (pod hráči) a ve vzduchu (nad vším) a stav pro síťovou hru.
## Konkrétní boss přepisuje háčky boss_setup / boss_behave / update_fx / draw_ground / draw_air.

signal summon(kind, pos)
signal hp_changed(hp, max_hp)
signal phase_changed(phase)

@export var hp_scale := 1.0          # násobí HP, které bossovi nastaví aréna

var phase := 1
var ground: Node2D                   # efekty na zemi (kreslí se pod hráči, globální souřadnice)
var air: Node2D                      # efekty ve vzduchu (kreslí se nad vším, souřadnice bosse)
var arena                            # aktuální scéna (sektor, volná místa)


func setup():
	add_to_group("boss")
	arena = get_tree().current_scene
	accel = 5000.0
	visual.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(visual, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ground = Node2D.new()
	ground.draw.connect(func(): draw_ground(ground))
	var layer = arena.get_node_or_null("Arenas") if arena else null
	(layer if layer else get_parent()).add_child.call_deferred(ground)
	air = Node2D.new()
	air.z_index = 2
	air.draw.connect(func(): draw_air(air))
	add_child(air)
	boss_setup()
	hp_changed.emit(hp, max_hp)


func _exit_tree():
	if is_instance_valid(ground):
		ground.queue_free()


# --- háčky pro konkrétní bosse ---
func boss_setup():
	pass

func boss_behave(_delta):            # jen když má živý cíl
	pass

func update_fx(_delta):              # vždy (miny, vlny, stopy…)
	pass

func on_phase(_new_phase):
	pass

func draw_ground(_c: Node2D):
	pass

func draw_air(_c: Node2D):
	pass

func net_state() -> Array:           # co navíc poslat klientovi
	return []

func apply_net_state(_s: Array):
	pass


func behave(delta):
	if player != null and not player.dead:
		boss_behave(delta)
	update_fx(delta)
	redraw()


func redraw():
	if is_instance_valid(ground):
		ground.queue_redraw()
	if air:
		air.queue_redraw()


func on_damaged():
	hp_changed.emit(max(hp, 0), max_hp)
	var new_phase = 1
	if hp <= max_hp * 0.33:
		new_phase = 3
	elif hp <= max_hp * 0.66:
		new_phase = 2
	if new_phase != phase and hp > 0:
		phase = new_phase
		on_phase(phase)
		phase_changed.emit(phase)
		Juice.play("boss_phase", 0.0, 0.0)
		Juice.shake(0.7)
		Juice.hitstop(0.12)


func die():
	Juice.play("boss_die", 0.0, 0.0)
	Juice.shake(1.0)
	Juice.hitstop(0.25)
	for i in 3:
		Juice.burst(global_position + Vector2(randf_range(-40, 40), randf_range(-70, -10)), burst_color, 30)
	died.emit(global_position, score_value, drops)
	queue_free()


# --- síť ---
func net_extra() -> Array:
	return [phase, net_state()]


func apply_net_extra(x):
	if not x is Array or x.size() < 2:
		return
	phase = int(x[0])
	apply_net_state(x[1])
	redraw()


# --- pomocné ---
# čas pro blikání (běží i u loutek na klientovi)
func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func alive_targets() -> Array:
	return get_tree().get_nodes_in_group("player").filter(func(p): return not p.dead)


# herní vektor -> obrazovka a zpět
static func to_screen(v: Vector2) -> Vector2:
	return v * ISO

static func to_game(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * 2.0)


# body elipsy = kruh o poloměru r v herních souřadnicích
static func ellipse(center: Vector2, r: float, n := 40) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in n:
		var a = i * TAU / n
		pts.append(center + Vector2(cos(a) * r, sin(a) * r * 0.5))
	return pts


static func draw_ring(c: CanvasItem, center: Vector2, r: float, width: float, color: Color):
	var pts = ellipse(center, r, 48)
	pts.append(pts[0])
	c.draw_polyline(pts, color, width)


static func draw_disc(c: CanvasItem, center: Vector2, r: float, color: Color):
	if r > 0.5:
		c.draw_colored_polygon(ellipse(center, r, 32), color)


# paprsek z bodu ve směru dir (herní souřadnice) – kde ho zastaví blok nebo okraj sektoru
func ray_length(from: Vector2, dir: Vector2, max_len: float) -> float:
	var q = PhysicsRayQueryParameters2D.create(from, from + to_screen(dir * max_len), 1 | 32)
	q.exclude = [get_rid()]
	var hit = get_world_2d().direct_space_state.intersect_ray(q)
	return iso_dist(hit["position"], from) if hit else max_len


# střed aktuálního sektoru (průměr volných políček)
func sector_center() -> Vector2:
	if arena and arena.get("current") and arena.current.has("layout"):
		var free: Array = arena.current["layout"]["free"]
		if not free.is_empty():
			var sum = Vector2.ZERO
			for c in free:
				sum += arena.cell_center(c)
			return sum / free.size()
	return global_position


# pohyb ke středu sektoru (bossové, kteří útočí do všech stran)
func toward(target: Vector2, slow_radius := 80.0) -> Vector2:
	var w = to_game(target - global_position)
	if w.length() < 8.0:
		return Vector2.ZERO
	return to_screen(w.normalized()) * speed * clampf(w.length() / slow_radius, 0.0, 1.0) + wall_steer * speed


# náhodné volné místo v sektoru v dané vzdálenosti od hráče
func free_spot_near(target: Vector2, min_d: float, max_d: float) -> Vector2:
	if arena and arena.get("current") and arena.current.has("layout"):
		var free: Array = arena.current["layout"]["free"]
		for attempt in 40:
			var p = arena.cell_center(free.pick_random())
			var d = iso_dist(p, target)
			if d >= min_d and d <= max_d:
				return p
	return global_position
