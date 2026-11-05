extends CanvasLayer
## Obchod v terminálu – utrácení čipů. V co-opu má každý hráč vlastní nabídku i čipy.

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

var player                      # kdo právě nakupuje
var sector := 1
var offers := []
var corrupt_target = null
var buttons := {}
# nabídka se losuje jednou za terminál pro každého hráče zvlášť
var offers_by := {}
var corrupt_by := {}
var sold_by := {}

@onready var root = $Root
@onready var title = $Root/Center/Panel/Margin/VBox/Title
@onready var chips_label = $Root/Center/Panel/Margin/VBox/Chips
@onready var offers_box = $Root/Center/Panel/Margin/VBox/Offers
@onready var info_label = $Root/Center/Panel/Margin/VBox/Info
@onready var close_btn = $Root/Center/Panel/Margin/VBox/CloseButton


func _ready():
	root.hide()
	root.add_to_group("ui_modal")
	close_btn.pressed.connect(close)


func _input(event):
	if not root.visible:
		return
	var key = player.act("interact") if player and not remote_send.is_valid() else "interact"
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(key):
		close()
		get_viewport().set_input_as_handled()


# nový terminál = nové nabídky
func reset(sec: int):
	sector = sec
	offers_by = {}
	corrupt_by = {}
	sold_by = {}


func _roll(p):
	var list = ["clean_upgrade"]
	var target = null
	if not p.corrupts.is_empty():
		target = p.corrupts.keys().pick_random()
		list.append("remove_corrupt")
	var pool = RANDOM_POOL.duplicate()
	if p.shield >= 3:
		pool.erase("shield")
	pool.shuffle()
	list += pool.slice(0, 3)
	offers_by[p] = list
	corrupt_by[p] = target
	sold_by[p] = {}


func prepare(p):
	if not offers_by.has(p):
		_roll(p)


func open_for(p):
	player = p
	prepare(p)
	offers = offers_by[p]
	corrupt_target = corrupt_by[p]
	title.text = "TERMINÁL · P%d" % (p.player_index + 1) if GameSettings.two_players() else "TERMINÁL"
	_build_rows()
	info_label.text = ""
	get_tree().paused = true
	root.show()
	close_btn.grab_focus()


func close():
	root.hide()
	if not remote_send.is_valid():
		get_tree().paused = false
	remote_send = Callable()
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
		if sold_by[player].has(id):
			btn.text = "PRODÁNO"
			btn.disabled = true
		else:
			btn.text = "KOUPIT  ·  %d" % price(id)
			btn.disabled = player.chips < price(id)


func _buy(id: String):
	if remote_send.is_valid():          # klient: nákup řeší hostitel
		remote_send.call(id)
		return
	var msg = purchase(player, id)
	if msg == "":
		Juice.play("jam", -4.0)
		return
	info_label.text = msg
	Juice.play("buy", -2.0, 0.0)
	_refresh()


# provede nákup pro hráče p, vrací text (prázdný = nešlo)
func purchase(p, id: String) -> String:
	player = p
	prepare(p)
	offers = offers_by[p]
	corrupt_target = corrupt_by[p]
	if sold_by[p].has(id) or not id in offers:
		return ""
	var pr = price(id)
	if p.chips < pr:
		return ""
	var msg := ""
	if id == "clean_upgrade":
		var pick = Upgrades.pick(p.upgrades, 1)
		if pick.is_empty():
			return "Všechny upgrady už máš na maximu."
		p.apply_upgrade(pick[0])
		p.clean_bought += 1
		msg = "Získáno: %s" % Upgrades.LIST[pick[0]]["name"]
	else:
		msg = p.apply_shop_item(id, corrupt_target)
	p.chips -= pr
	sold_by[p][id] = true
	return msg


# ============================================================
#  Síť: obchod hráče 2 běží u hostitele, klient jen zobrazuje
# ============================================================

var remote_send := Callable()
var _remote_rows := []

# (host) data pro UI klienta
func remote_data(p, info := "") -> Dictionary:
	prepare(p)
	player = p
	offers = offers_by[p]
	corrupt_target = corrupt_by[p]
	var rows = []
	for id in offers:
		var desc = ITEMS[id]["desc"]
		if id == "remove_corrupt":
			desc = desc % Upgrades.CORRUPTS[corrupt_target]["name"]
		rows.append({"id": id, "name": ITEMS[id]["name"], "desc": desc, "price": price(id), "sold": sold_by[p].has(id)})
	return {"chips": p.chips, "title": "TERMINÁL · P%d" % (p.player_index + 1), "rows": rows, "info": info}


# (klient) otevře / obnoví obchod podle dat od hostitele
func open_remote(data: Dictionary, send: Callable):
	remote_send = send
	update_remote(data)
	if not root.visible:
		root.show()
		close_btn.grab_focus()


func update_remote(data: Dictionary):
	title.text = data["title"]
	chips_label.text = "ČIPY:  %d" % data["chips"]
	info_label.text = data["info"]
	for c in offers_box.get_children():
		c.queue_free()
	for r in data["rows"]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var info = RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.scroll_active = false
		info.custom_minimum_size = Vector2(440, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.text = "[b]%s[/b]\n[color=#8d92b8]%s[/color]" % [r["name"], r["desc"]]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(170, 46)
		if r["sold"]:
			btn.text = "PRODÁNO"
			btn.disabled = true
		else:
			btn.text = "KOUPIT  ·  %d" % r["price"]
			btn.disabled = data["chips"] < r["price"]
		btn.pressed.connect(_buy.bind(r["id"]))
		row.add_child(info)
		row.add_child(btn)
		offers_box.add_child(row)
