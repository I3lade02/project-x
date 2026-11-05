extends Area2D
## Terminál (obchod). Objeví se po vlně u chodby do dalšího sektoru.
## Hráč přijde blízko a zmáčkne interakci (E).

signal opened(player)

var near := []          # hráči u terminálu
var t := 0.0

@onready var prompt = $Prompt
@onready var screen = $Visual/Screen


func _ready():
	add_to_group("terminal")
	prompt.hide()
	body_entered.connect(func(b):
		if b.is_in_group("player") and not b in near:
			near.append(b))
	body_exited.connect(func(b):
		near.erase(b))
	var keys = [GameSettings.event_label(GameSettings.get_binding("interact"))]
	if GameSettings.coop:
		keys.append(GameSettings.event_label(GameSettings.get_binding("p2_interact")))
	prompt.text = "[%s]  TERMINÁL" % " / ".join(PackedStringArray(keys))


func _process(delta):
	t += delta
	screen.modulate.a = 0.7 + 0.3 * sin(t * 4.0)
	prompt.visible = not near.is_empty()
	if get_tree().paused:
		return
	for p in near:
		if not p.dead and p.inp_just("interact"):
			opened.emit(p)
			return
