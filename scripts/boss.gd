extends "res://scripts/boss_base.gd"
## Boss VIRUS.EXE – 3 fáze:
## 1) salvy žhavých koulí, 2) + přivolává bugy, 3) rychlejší + rozpálená aura.

const ORB_SPEED = 200.0
const AURA_RADIUS = 140.0
const AURA_HEAT = 18.0       # teplo/s v auře (fáze 3)

var attack_cd := 2.5
var summon_cd := 4.0
var spin := 0.0

@onready var aura = $Aura
@onready var core = $Visual/Body/Core


func boss_behave(delta):
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
		for p in alive_targets():
			if iso_dist(p.global_position, global_position) < AURA_RADIUS:
				p.add_heat(AURA_HEAT * delta)


func update_fx(_delta):
	aura.visible = phase >= 3
	aura.modulate.a = 0.6 + 0.4 * sin(now() * 6.0)


func on_phase(p):
	if p == 3:
		speed *= 1.4


func apply_net_state(_s: Array):
	update_fx(0.0)
