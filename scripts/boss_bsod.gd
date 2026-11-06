extends "res://scripts/boss_base.gd"
## Boss BSOD.SYS – modrá smrt. Nabije se a pošle rázovou vlnu přes celou arénu – proleť ji dashem!
## Mezitím chrlí spirálu koulí.
## 1) 1 vlna, 2) 2 vlny za sebou + 2 ramena spirály, 3) 3 vlny + vyskakovací okna (turrety).

const RING_SPEED = 360.0
const RING_MAX = 950.0
const RING_W = 20.0           # tloušťka vlny (herní jednotky)
const RING_HEAT = 26.0
const CHARGE_TIME = 1.1
const ORB_SPEED = 170.0
const MAX_POPUPS = 4
const BLUE = Color(0.6, 1.4, 3.0)

var rings := []               # [střed, poloměr, {hráč: true}]
var halt_cd := 3.0
var charging := 0.0
var pending := 0              # kolik vln ještě vyšle
var pending_cd := 0.0
var spiral := 0.0
var spiral_cd := 1.0
var popup_cd := 1.0
var home := Vector2.ZERO      # střed sektoru – vlny odtud pokryjí celou arénu

@onready var core = $Visual/Body/Core


func boss_setup():
	home = sector_center()


func desired_velocity(_delta) -> Vector2:
	return toward(home)


func boss_behave(delta):
	# spirála koulí (při nabíjení vlny se zastaví)
	spiral_cd -= delta
	if spiral_cd <= 0 and charging <= 0:
		spiral_cd = [0.0, 0.28, 0.22, 0.19][phase]
		var arms = [0, 1, 2, 2][phase]
		spiral += 0.37
		for i in arms:
			shoot_orb(to_screen(Vector2.RIGHT.rotated(spiral + i * TAU / arms)) * ORB_SPEED, 10.0)

	# SYSTEM HALT – nabití a rázové vlny
	if charging > 0:
		charging -= delta
		core.modulate = _charge_tint()
		if charging <= 0:
			pending = [0, 1, 2, 3][phase]
			pending_cd = 0.0
	elif pending == 0:
		core.modulate = Color(1, 1, 1) * (1.0 + 0.25 * sin(t * 3.0))
		halt_cd -= delta
		if halt_cd <= 0:
			charging = CHARGE_TIME
			halt_cd = [0.0, 4.5, 5.0, 5.5][phase]
			Juice.play("charge", -2.0, 0.0)
	if pending > 0:
		pending_cd -= delta
		if pending_cd <= 0:
			pending -= 1
			pending_cd = 0.45
			rings.append([global_position, 30.0, {}])
			Juice.play("shockwave", -2.0, 0.05)
			Juice.shake(0.35)

	# fáze 3: vyskakovací okna
	if phase >= 3:
		popup_cd -= delta
		if popup_cd <= 0:
			popup_cd = 11.0
			var turrets = get_tree().get_nodes_in_group("enemies").filter(func(e): return e.scene_file_path.ends_with("turret.tscn"))
			for i in mini(2, MAX_POPUPS - turrets.size()):
				summon.emit("turret", global_position)
			Juice.play("warn", -4.0, 0.0)


# obrazovka při nabíjení zesvětluje (ale ne do běla, ať je vidět obličej)
func _charge_tint() -> Color:
	var k = 1.0 - charging / CHARGE_TIME
	return Color(1, 1, 1) * (1.0 + 0.6 * k) if int(now() * 10.0) % 2 == 0 else Color(1, 1, 1) * (1.0 + 0.3 * k)


func update_fx(delta):
	for r in rings:
		r[1] += RING_SPEED * delta
		for p in alive_targets():
			if r[2].has(p):
				continue
			if absf(iso_dist(p.global_position, r[0]) - r[1]) < RING_W:
				r[2][p] = true                # každá vlna zasáhne hráče jen jednou
				p.hit(RING_HEAT, r[0])        # dash = nesmrtelnost -> proletí
	rings = rings.filter(func(r): return r[1] < RING_MAX)


func draw_ground(c: Node2D):
	for r in rings:
		var k = 1.0 - r[1] / RING_MAX
		draw_ring(c, r[0], r[1], 16.0, Color(BLUE, 0.25 * k + 0.05))
		draw_ring(c, r[0], r[1], 5.0, Color(BLUE, 0.9 * k + 0.1))
		draw_ring(c, r[0], r[1] - 14.0, 2.0, Color(2.5, 2.8, 3.5, 0.5 * k))
	if charging > 0:
		var k = 1.0 - charging / CHARGE_TIME
		draw_ring(c, global_position, 30.0 + 90.0 * (1.0 - k), 3.0, Color(BLUE, 0.3 + 0.6 * k))


func draw_air(c: Node2D):
	if charging > 0 and int(now() * 8.0) % 2 == 0:
		c.draw_string(ThemeDB.fallback_font, Vector2(-90, -150), "SYSTEM HALT", HORIZONTAL_ALIGNMENT_CENTER, 180, 20, Color(2.5, 2.8, 3.5))


func net_state() -> Array:
	var rr = []
	for r in rings:
		rr.append([r[0], r[1]])
	return [charging, rr]


func apply_net_state(s: Array):
	if s.size() >= 2:
		charging = s[0]
		rings = []
		for r in s[1]:
			rings.append([r[0], r[1], {}])
		core.modulate = _charge_tint() if charging > 0 else Color.WHITE
