extends CanvasLayer

signal chosen(upgrade_id, corrupt_id)
signal reroll

const Upgrades = preload("res://scripts/upgrades.gd")

@onready var root = $Root
@onready var cards = [
	$Root/Center/VBox/Cards/Card1,
	$Root/Center/VBox/Cards/Card2,
	$Root/Center/VBox/Cards/Card3,
]

var choices := []
var corrupts := []
var reroll_cost := 3           # cena rerollu v čipech (nastavuje aréna)

@onready var reroll_btn = $Root/Center/VBox/RerollButton


func _ready():
	root.hide()
	for i in cards.size():
		cards[i].pressed.connect(_on_card_pressed.bind(i))
	reroll_btn.pressed.connect(func(): reroll.emit())


func open(new_choices: Array, new_corrupts: Array, owned: Dictionary, owned_corrupts: Dictionary):
	choices = new_choices
	corrupts = new_corrupts
	for i in cards.size():
		if i >= choices.size():
			cards[i].hide()
			continue
		var u = Upgrades.LIST[choices[i]]
		var lvl = owned.get(choices[i], 0) + 1
		var txt = "[center][b]%s[/b]\n%s\n(%d/%d)" % [u["name"], u["desc"], lvl, u["max"]]
		if corrupts[i] != "":
			var c = Upgrades.CORRUPTS[corrupts[i]]
			var clvl = owned_corrupts.get(corrupts[i], 0) + 1
			txt += "\n\n[color=#ff5050][b]CORRUPT: %s[/b]\n%s\n(%d/%d)[/color]" % [c["name"], c["desc"], clvl, c["max"]]
		txt += "[/center]"
		cards[i].get_node("Text").text = txt
		cards[i].show()
	# reroll za čipy (jen ve hře, kde hráč čipy má)
	var p = get_tree().get_first_node_in_group("player")
	var chips = p.get("chips") if p else null
	reroll_btn.visible = chips != null
	if chips != null:
		reroll_btn.text = "REROLL  ·  %d ČIPŮ   (máš %d)" % [reroll_cost, chips]
		reroll_btn.disabled = chips < reroll_cost
	get_tree().paused = true
	root.show()
	cards[0].grab_focus()


func is_open():
	return root.visible


func _on_card_pressed(i):
	root.hide()
	get_tree().paused = false
	chosen.emit(choices[i], corrupts[i])
