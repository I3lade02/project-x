extends Area2D

enum State { OFF, WARN, HOT }

const OFF_TIME = 4.0
const WARN_TIME = 1.2
const HOT_TIME = 3.0
const HEAT_PER_SEC = 35.0
const ENEMY_TICK = 0.5
const COLOR_OFF = Color(0.3, 0.15, 0.1)
const COLOR_WARN = Color(1.0, 0.6, 0.1)
const COLOR_HOT = Color(1.0, 0.2, 0.05)

@export var start_offset := 0.0

var state := State.OFF
var timer := 0.0
var tick := 0.0
var t := 0.0

@onready var rect = $Rect

func _ready():
	timer = OFF_TIME + start_offset
	rect.color = COLOR_OFF
	
func _physics_process(delta):
	t += delta
	timer -= delta
	if timer <= 0:
		_next_state()
		
	match state:
		State.WARN:
			rect.color = COLOR_WARN if int(timer * 8) % 2 == 0 else COLOR_OFF
		State.HOT:
			rect.color = COLOR_HOT.lerp(COLOR_WARN, (sin(t * 10.0) + 1.0) / 4.0)
			tick -= delta
			var hurt_enemies = tick <= 0
			if hurt_enemies:
				tick = ENEMY_TICK
			for b in get_overlapping_bodies():
				if b.is_in_group("player"):
					b.add_heat(HEAT_PER_SEC * delta)
				elif hurt_enemies and b.is_in_group("enemies"):
					b.take_damage(1)
					
func _next_state():
	match state:
		State.OFF:
			state = State.WARN
			timer = WARN_TIME
		State.WARN:
			state = State.HOT
			timer = HOT_TIME
			tick = 0.0
		State.HOT:
			state = State.OFF
			timer = OFF_TIME
			rect.color = COLOR_OFF
