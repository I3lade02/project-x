extends CanvasLayer

signal chosen(id)

const Upgrades = preload("res://scripts/upgrades.gd")

@onready var root = $Root
@onready var cards = [
	$Root/Center/VBox/Cards/Card1,
	$Root/Center/VBox/Cards/Card2,
	$Root/Center/VBox/Cards/Card3,
]

var choices := []


func _ready():
	root.hide()
	for i in cards.size():
		cards[i].pressed.connect(_on_card_pressed.bind(i))


func open(new_choices: Array, owned: Dictionary):
	choices = new_choices
	for i in cards.size():
		if i < choices.size():
			var u = Upgrades.LIST[choices[i]]
			var lvl = owned.get(choices[i], 0) + 1
			cards[i].text = "%s\n\n%s\n\n(%d/%d)" % [u["name"], u["desc"], lvl, u["max"]]
			cards[i].show()
		else:
			cards[i].hide()
	get_tree().paused = true
	root.show()
	cards[0].grab_focus()


func is_open():
	return root.visible


func _on_card_pressed(i):
	root.hide()
	get_tree().paused = false
	chosen.emit(choices[i])
