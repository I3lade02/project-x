extends Area2D
## Terminál (obchod). Objeví se po vlně u chodby do dalšího sektoru.
## Hráč přijde blízko a zmáčkne interakci (E).

signal opened

var near := false
var t := 0.0

@onready var prompt = $Prompt
@onready var screen = $Visual/Screen


func _ready():
	prompt.hide()
	body_entered.connect(func(b):
		if b.is_in_group("player"):
			near = true)
	body_exited.connect(func(b):
		if b.is_in_group("player"):
			near = false)
	var ev = GameSettings.get_binding("interact")
	if ev is InputEventKey:
		prompt.text = "[%s]  TERMINÁL" % OS.get_keycode_string(ev.physical_keycode)


func _process(delta):
	t += delta
	screen.modulate.a = 0.7 + 0.3 * sin(t * 4.0)
	prompt.visible = near
	if near and not get_tree().paused and Input.is_action_just_pressed("interact"):
		opened.emit()
