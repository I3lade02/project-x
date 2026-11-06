extends Control
## Skill tree v hlavním menu – trvalé upgrady za JÁDRA.

signal closed

const NODE_SIZE = Vector2(176, 70)
const BRANCH_W = 400.0          # šířka jedné větve
const COL_GAP = 190.0           # rozestup sloupců uvnitř větve
const ROW_H = 125.0             # rozestup řádků
const TOP = 46.0                # místo na název větve

var buttons := {}
var _confirm_reset := false

@onready var tree_area = $Tree
@onready var lines = $Tree/Lines
@onready var cores_label = $Cores
@onready var info = $Info
@onready var reset_btn = $Buttons/ResetButton
@onready var back_btn = $Buttons/BackButton


func _ready():
	hide()
	lines.draw.connect(_draw_lines)
	reset_btn.pressed.connect(_on_reset)
	back_btn.pressed.connect(close)
	Progress.changed.connect(refresh)
	_build()


func open():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_reset = false
	show()
	refresh()
	info.text = "Najeď na uzel pro popis, kliknutím ho koupíš. Jádra padají z bosse, vzácně z nepřátel a jako bonus na konci runu."
	back_btn.grab_focus()


func close():
	hide()
	closed.emit()


# levý horní roh tlačítka uzlu
func _node_pos(id: String) -> Vector2:
	var d = Progress.TREE[id]
	var b = Progress.BRANCHES.keys().find(d["branch"])
	var x = b * BRANCH_W + BRANCH_W / 2.0 + (d["pos"].x - 0.5) * COL_GAP - NODE_SIZE.x / 2.0
	return Vector2(x, TOP + d["pos"].y * ROW_H)


func _build():
	var i = 0
	for key in Progress.BRANCHES:
		var br = Progress.BRANCHES[key]
		var l = Label.new()
		l.text = br["name"]
		l.add_theme_font_size_override("font_size", 22)
		l.modulate = br["color"]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(i * BRANCH_W, 0)
		l.size = Vector2(BRANCH_W, 30)
		tree_area.add_child(l)
		i += 1
	for id in Progress.TREE:
		var b = Button.new()
		b.position = _node_pos(id)
		b.custom_minimum_size = NODE_SIZE
		b.size = NODE_SIZE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_pressed.bind(id))
		b.mouse_entered.connect(_show_info.bind(id))
		b.focus_entered.connect(_show_info.bind(id))
		tree_area.add_child(b)
		buttons[id] = b


func refresh():
	cores_label.text = "JÁDRA:  %d" % Progress.cores
	for id in buttons:
		var b = buttons[id]
		var d = Progress.TREE[id]
		var lv = Progress.level(id)
		var mx = Progress.max_level(id)
		var cost = Progress.next_cost(id)
		var state = "MAX" if cost < 0 else "%d JADER" % cost
		b.text = "%s\n%d/%d  ·  %s" % [d["name"], lv, mx, state]
		var col = Progress.BRANCHES[d["branch"]]["color"]
		if not Progress.is_unlocked(id):
			b.modulate = Color(0.45, 0.45, 0.5)       # zamčeno
		elif lv >= mx:
			b.modulate = col                          # hotovo
		elif lv > 0:
			b.modulate = Color.WHITE.lerp(col, 0.5)   # rozpracováno
		else:
			b.modulate = Color.WHITE
	if _confirm_reset:
		reset_btn.text = "OPRAVDU? KLIKNI ZNOVU"
	else:
		reset_btn.text = "RESET STROMU  (vrátí %d)" % Progress.spent()
	reset_btn.disabled = Progress.spent() == 0
	lines.queue_redraw()


func _show_info(id: String):
	var d = Progress.TREE[id]
	var txt = "%s – %s" % [d["name"], d["desc"]]
	if not Progress.is_unlocked(id):
		txt += "   (nejdřív odemkni: %s)" % Progress.TREE[d["req"]]["name"]
	info.text = txt


func _on_pressed(id: String):
	if Progress.buy(id):
		Juice.play("upgrade", -2.0, 0.0)
		_show_info(id)
	else:
		Juice.play("jam", -4.0)


func _on_reset():
	if not _confirm_reset:
		_confirm_reset = true
		refresh()
		return
	_confirm_reset = false
	Progress.reset_tree()
	Juice.play("buy", -4.0, 0.0)


# čáry mezi uzly (barevné, když je uzel koupený)
func _draw_lines():
	for id in Progress.TREE:
		var req = Progress.TREE[id]["req"]
		if req == "":
			continue
		var a = _node_pos(req) + Vector2(NODE_SIZE.x / 2.0, NODE_SIZE.y)
		var b = _node_pos(id) + Vector2(NODE_SIZE.x / 2.0, 0)
		var col = Progress.BRANCHES[Progress.TREE[id]["branch"]]["color"] if Progress.level(id) > 0 else Color(0.3, 0.3, 0.4)
		lines.draw_line(a, b, col, 3.0)
