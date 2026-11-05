extends "res://scripts/enemy_iso.gd"
## Boss VIRUS.EXE – každá 5. vlna. 3 fáze:
## 1) salvy žhavých koulí, 2) + přivolává bugy, 3) rychlejší + rozpálená aura.

signal summon(kind, pos)
signal hp_changed(hp, max_hp)
signal phase_changed(phase)

const ORB_SPEED = 200.0
const AURA_RADIUS = 140.0
const AURA_HEAT = 18.0       # teplo/s v auře (fáze 3)

var phase := 1
var attack_cd := 2.5
var summon_cd := 4.0
var spin := 0.0

@onready var aura = $Aura
@onready var core = $Visual/Body/Core


func setup():
	visual.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(visual, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hp_changed.emit(hp, max_hp)


func behave(delta):
	if player == null or player.dead:
		return
	core.modulate = Color(1, 1, 1) * (1.0 + 0.6 * sin(t * (4.0 + phase * 3.0)))
	visual.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * phase   # glitch třes

	# salvy koulí do kruhu
	attack_cd -= delta
	if attack_cd <= 0:
		var count = [0, 10, 14, 18][phase]
		spin += 0.3
		for i in count:
			var a = spin + i * TAU / count
			shoot_orb(Vector2(cos(a), sin(a)) * ISO * ORB_SPEED, 14.0)
		Juice.play("orb", -2.0, 0.0)
		attack_cd = [0.0, 3.0, 2.6, 2.0][phase]

	# přivolání bugů
	if phase >= 2:
		summon_cd -= delta
		if summon_cd <= 0:
			summon_cd = 7.0
			for i in 3:
				var off = Vector2.RIGHT.rotated(randf() * TAU) * Vector2(70, 35)
				summon.emit("bug", global_position + off)
			Juice.play("charge", -4.0, 0.0)

	# rozpálená aura
	if phase >= 3:
		for p in get_tree().get_nodes_in_group("player"):
			if not p.dead and iso_dist(p.global_position, global_position) < AURA_RADIUS:
				p.add_heat(AURA_HEAT * delta)
	aura.visible = phase >= 3
	aura.modulate.a = 0.6 + 0.4 * sin(t * 6.0)


func on_damaged():
	hp_changed.emit(max(hp, 0), max_hp)
	var new_phase = 1
	if hp <= max_hp * 0.33:
		new_phase = 3
	elif hp <= max_hp * 0.66:
		new_phase = 2
	if new_phase != phase and hp > 0:
		phase = new_phase
		if phase == 3:
			speed *= 1.4
		phase_changed.emit(phase)
		Juice.play("boss_phase", 0.0, 0.0)
		Juice.shake(0.7)
		Juice.hitstop(0.12)


func die():
	Juice.play("boss_die", 0.0, 0.0)
	Juice.shake(1.0)
	Juice.hitstop(0.25)
	for i in 3:
		Juice.burst(global_position + Vector2(randf_range(-40, 40), randf_range(-70, -10)), Color(2.5, 0.4, 2.0), 30)
	died.emit(global_position, score_value, drops)
	queue_free()
