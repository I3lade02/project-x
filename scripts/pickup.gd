extends Area2D

enum Type { DOUBLE_JUMP, COOLANT, NITRO }

const COLORS = {
	Type.DOUBLE_JUMP: Color(0.2, 0.9, 1.0),
	Type.COOLANT: Color(0.2, 0.4, 1.0),
	Type.NITRO: Color(0.9, 0.9, 1.0),
}
const LETTERS = {
	Type.DOUBLE_JUMP: "D",       # v izo verzi = double dash
	Type.COOLANT: "C",
	Type.NITRO: "N",
}
const LIFETIME = 8.0

var type := Type.COOLANT
var life := LIFETIME
var t := 0.0
var base_y := 0.0

@onready var rect = $Rect
@onready var letter = $Letter


func _ready():
	rect.color = COLORS[type]
	letter.text = LETTERS[type]
	base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta):
	t += delta
	life -= delta
	position.y = base_y + sin(t * 4.0) * 4.0     # vznášení
	if life < 2.0:
		visible = int(life * 10) % 2 == 0          # blikání před zmizením
	if life <= 0:
		queue_free()


func _on_body_entered(b):
	if b.has_method("apply_powerup"):
		b.apply_powerup(type)
		Juice.play("pickup")
		queue_free()
