extends CanvasLayer
## Obchod v terminálu – utrácení čipů.

signal closed

const Upgrades = preload("res://scripts/upgrades.gd")
const ITEMS = {
	"clean_upgrade":  {"name": "Čistý upgrade",     "desc": "Náhodný upgrade BEZ corruptu", "price": 14},
	"remove_corrupt": {"name": "Odstranit corrupt", "desc": "Smaže: %s",                    "price": 10},
	"shield":         {"name": "Tepelný štít",      "desc": "Pohltí 1 zásah (max 3). Zachrání i během crashe.", "price": 6},
	"fuse":           {"name": "Pojistka",          "desc": "Místo příštího crashe se automaticky vyventuješ.", "price": 10},
	"fins":           {"name": "Chladicí žebra",    "desc": "Chlazení +15 %",               "price": 7},
	"capacitor":      {"name": "Kondenzátor",       "desc": "Dash se nabíjí o 15 % rychleji", "price": 7},
	"magnet":         {"name": "Magnet",            "desc": "Čipy přitahuješ z 1,5× větší dálky", "price": 4},
	"nitro":          {"name": "Nitro na start",    "desc": "Příští vlnu začneš s 6 s dusíku", "price": 5},
}
const RANDOM_POOL = ["shield", "fuse", "fins", "capacitor", "magnet", "nitro"]

var player
var sector := 1
var offers := []
var corrupt_target = null
var buttons := {}

@onready var root = $Root
@onready var chips_label = $Root/Center/Panel/Margin/VBox/Chips
@onready var offers_box = $Root/Center/Panel/Margin/VBox/Offers
@onready var info_label = $Root/Center/Panel/Margin/VBox/Info
@onready var close_btn = $Root/Center/Panel/Margin/VBox/CloseButton


func _ready():
	root.hide()
	close_btn.pressed.connect(close)


func _input(event):
	if root.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


# nabídka se vylosuje jednou za terminál (ne při každém otevření)
func setup(p, sec: int):
	player = p
	sector = sec
	offers = ["clean_upgrade"]
	corrupt_target = null
	if not player.corrupts.is_empty():
		corrupt_target = player.corrupts.keys().pick_random()
		offers.append("remove_corrupt")
	var pool = RANDOM_POOL.duplicate()
	if player.shield >= 3:
		pool.erase("shield")
	pool.shuffle()
	offers += pool.slice(0, 3)


func open():
	_build_rows()
	info_label.text = ""
	get_tree().paused = true
	root.show()
	close_btn.grab_focus()


func close():
	root.hide()
	get_tree().paused = false
	closed.emit()


func price(id: String) -> int:
	var p = ITEMS[id]["price"] + floori(sector / 2.0)
	if id == "remove_corrupt":
		p += player.corrupt_removals * 4
	elif id == "clean_upgrade":
		p += player.clean_bought * 3
	return p


func _build_rows():
	for c in offers_box.get_children():
		c.queue_free()
	buttons.clear()
	for id in offers:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var info = RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.custom_minimum_size = Vector2(440, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var desc = ITEMS[id]["desc"]
		if id == "remove_corrupt":
			desc = desc % Upgrades.CORRUPTS[corrupt_target]["name"]
		info.text = "[b]%s[/b]\n[color=#8d92b8]%s[/color]" % [ITEMS[id]["name"], desc]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(170, 46)
		btn.pressed.connect(_buy.bind(id))
		row.add_child(info)
		row.add_child(btn)
		offers_box.add_child(row)
		buttons[id] = btn
	_refresh()


func _refresh():
	chips_label.text = "ČIPY:  %d" % player.chips
	for id in buttons:
		var btn = buttons[id]
		if btn.has_meta("sold"):
			btn.text = "PRODÁNO"
			btn.disabled = true
		else:
			btn.text = "KOUPIT  ·  %d" % price(id)
			btn.disabled = player.chips < price(id)


func _buy(id: String):
	var p = price(id)
	if player.chips < p:
		Juice.play("jam", -4.0)
		return
	var msg := ""
	if id == "clean_upgrade":
		var pick = Upgrades.pick(player.upgrades, 1)
		if pick.is_empty():
			info_label.text = "Všechny upgrady už máš na maximu."
			return
		player.apply_upgrade(pick[0])
		player.clean_bought += 1
		msg = "Získáno: %s" % Upgrades.LIST[pick[0]]["name"]
	else:
		msg = player.apply_shop_item(id, corrupt_target)
	player.chips -= p
	buttons[id].set_meta("sold", true)
	info_label.text = msg
	Juice.play("buy", -2.0, 0.0)
	_refresh()
