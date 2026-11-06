extends "res://scripts/boss_base.gd"
## Boss FIREWALL.SYS – kolem sebe točí ohnivé paprsky. Paprsek zastaví blok, dash jím proletí.
## 1) 2 paprsky, 2) 3 paprsky + mířené koule, 3) 4 paprsky a občas otočí směr.

const BEAM_LEN = 900.0        # délka paprsku (herní jednotky) – zastaví ho blok nebo okraj sektoru
const BEAM_WIDTH = 20.0       # zásah = vzdálenost hráče od osy paprsku
const BEAM_HEAT = 22.0
const BEAM_START = 26.0       # paprsek začíná na okraji bosse
const BEAM_HEIGHT = 36.0      # výška paprsku nad zemí (jen kreslení)
const WARMUP = 1.6            # nové paprsky nejdřív jen varovně blikají
const ORB_SPEED = 230.0
const BEAM_COLOR = Color(3.0, 0.9, 0.25)

var angle := 0.0
var spin_speed := 0.0         # aktuální rychlost otáčení (rad/s)
var spin_target := 0.55
var warm := WARMUP
var lens := PackedFloat32Array()
var orb_cd := 2.5
var flip_cd := 5.0
var home := Vector2.ZERO      # střed sektoru – tam se drží

@onready var core = $Visual/Body/Core


func beam_count() -> int:
	return [0, 2, 3, 4][clampi(phase, 1, 3)]


func beam_dir(i: int) -> Vector2:
	return Vector2.RIGHT.rotated(angle + i * TAU / beam_count())


func boss_setup():
	home = sector_center()
	angle = randf() * TAU
	if randf() < 0.5:
		spin_target = -spin_target


func desired_velocity(_delta) -> Vector2:
	return toward(home)


func boss_behave(delta):
	core.modulate = Color(1, 1, 1) * (1.2 + 0.5 * sin(t * 9.0))
	spin_speed = move_toward(spin_speed, spin_target, 0.5 * delta)
	angle = wrapf(angle + spin_speed * delta, 0.0, TAU)

	# fáze 3: občas obrátí směr (zpomalení dopředu prozradí, že se to chystá)
	if phase >= 3:
		flip_cd -= delta
		if flip_cd <= 0:
			flip_cd = randf_range(3.5, 5.5)
			spin_target = -spin_target
			Juice.play("warn", -8.0, 0.0)

	# délky paprsků (blok je zastaví)
	lens.resize(beam_count())
	for i in beam_count():
		lens[i] = ray_length(global_position, beam_dir(i), BEAM_LEN)

	if warm > 0:
		warm -= delta
		if warm <= 0:
			Juice.play("laser", -3.0, 0.0)
	else:
		_beam_hits()

	# mířené koule
	if phase >= 2:
		orb_cd -= delta
		if orb_cd <= 0:
			orb_cd = 2.4 if phase == 2 else 1.8
			var w = to_game(player.global_position - global_position).normalized()
			for i in 3:
				shoot_orb(to_screen(w.rotated((i - 1) * 0.22)) * ORB_SPEED, 12.0)
			Juice.play("orb", -6.0)


func _beam_hits():
	for p in alive_targets():
		var rel = to_game(p.global_position - global_position)
		for i in beam_count():
			var dir = beam_dir(i)
			var along = rel.dot(dir)
			if along < BEAM_START or along > lens[i]:
				continue
			if (rel - dir * along).length() < BEAM_WIDTH:
				# odhodí proti směru otáčení – paprsek hráče přejede a nevleče ho s sebou
				var sweep = Vector2(-dir.y, dir.x) * (1.0 if spin_speed >= 0 else -1.0)
				p.hit(BEAM_HEAT, p.global_position + to_screen(sweep) * 10.0)
				break


func on_phase(_p):
	warm = 1.0                    # nový paprsek se nejdřív ohlásí
	spin_speed *= 0.3
	spin_target = signf(spin_target) * [0.0, 0.55, 0.72, 0.9][phase]
	Juice.play("warn", -4.0, 0.0)


func draw_ground(c: Node2D):
	for i in mini(beam_count(), lens.size()):
		var dir = to_screen(beam_dir(i))
		var a = global_position + dir * BEAM_START
		var b = global_position + dir * lens[i]
		var col = BEAM_COLOR
		col.a = 0.12 if warm > 0 else 0.3
		c.draw_line(a, b, col, 10.0)


func draw_air(c: Node2D):
	var up = Vector2(0, -BEAM_HEIGHT)
	for i in mini(beam_count(), lens.size()):
		var dir = to_screen(beam_dir(i))
		var a = up + dir * BEAM_START
		var b = up + dir * lens[i]
		if warm > 0:
			var on = int(now() * 12.0) % 2 == 0
			c.draw_line(a, b, Color(BEAM_COLOR, 0.55 if on else 0.15), 2.0)
		else:
			var flick = 0.85 + 0.15 * sin(now() * 40.0 + i)
			c.draw_line(a, b, Color(BEAM_COLOR, 0.2 * flick), 22.0)
			c.draw_line(a, b, Color(BEAM_COLOR, 0.9 * flick), 7.0)
			c.draw_line(a, b, Color(4.0, 3.0, 2.0, 1.0), 2.0)
			c.draw_circle(b, 8.0 * flick, Color(BEAM_COLOR, 0.8))
	c.draw_circle(up, 12.0, Color(BEAM_COLOR, 0.6))


func net_state() -> Array:
	return [angle, warm, lens]


func apply_net_state(s: Array):
	if s.size() >= 3:
		angle = s[0]
		warm = s[1]
		lens = s[2]
