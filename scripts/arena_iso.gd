extends Node2D
## Izometrická aréna s procedurálně generovanými sektory.
## Po každé vlně (a výběru upgradu) se otevře chodba do nového, náhodně vygenerovaného sektoru.
## Hráč, nepřátelé, bloky a ventilátory žijí v uzlu World (y-sort), podlahy sektorů v uzlu Arenas.

const KINDS = {
	"bug": preload("res://scenes/enemy_iso.tscn"),
	"drone": preload("res://scenes/drone.tscn"),
	"turret": preload("res://scenes/turret.tscn"),
	"tank": preload("res://scenes/tank.tscn"),
	"boss": preload("res://scenes/boss.tscn"),
}
const PICKUP_SCENE = preload("res://scenes/pickup_iso.tscn")
const BLOCK_SCENE = preload("res://scenes/iso_block.tscn")
const PLATE_SCENE = preload("res://scenes/hot_plate_iso.tscn")
const FAN_SCENE = preload("res://scenes/fan_iso.tscn")
const CHIP_SCENE = preload("res://scenes/chip.tscn")
const TERMINAL_SCENE = preload("res://scenes/terminal.tscn")
const Pickup = preload("res://scripts/pickup.gd")
const Upgrades = preload("res://scripts/upgrades.gd")
const Gen = preload("res://scripts/arena_gen.gd")
const Edges = preload("res://scripts/arena_edges.gd")

const ORIGIN = Vector2(640, 72)      # roh dlaždice (0, 0) na obrazovce
const SPAWN_INTERVAL = 0.8
const CORRIDOR_LEN = Vector2i(4, 6)
const SIZE_RANGE = Vector2i(12, 17)
const BOSS_SIZE = Vector2i(18, 18)
const VOID_LAYER = 32                # kolizní vrstva 6 = okraj sektoru / díry
const CHIPS = {"bug": 1, "drone": 1, "turret": 3, "tank": 4, "boss": 25}
const REROLL_BASE = 3
const THEMES = [
	{"name": "CPU", "floor": Color(1.0, 1.1, 1.4), "edge": Color(0.3, 1.1, 1.6), "block_edge": Color(0.25, 0.9, 1.25)},
	{"name": "GPU", "floor": Color(0.9, 1.3, 1.0), "edge": Color(0.35, 1.5, 0.55), "block_edge": Color(0.3, 1.2, 0.45)},
	{"name": "RAM", "floor": Color(1.15, 0.9, 1.35), "edge": Color(1.25, 0.4, 1.6), "block_edge": Color(1.0, 0.35, 1.3)},
	{"name": "PSU", "floor": Color(1.25, 0.95, 0.75), "edge": Color(1.6, 0.7, 0.2), "block_edge": Color(1.3, 0.55, 0.18)},
	{"name": "SSD", "floor": Color(1.05, 1.05, 1.15), "edge": Color(1.35, 1.35, 1.5), "block_edge": Color(1.1, 1.1, 1.25)},
]

@onready var world = $World
@onready var player = $World/Player
@onready var arenas = $Arenas
@onready var floor_template = $Floor
@onready var camera = $Camera
@onready var heat_bar = $HUD/HeatBar
@onready var status = $HUD/StatusLabel
@onready var score_label = $HUD/ScoreLabel
@onready var wave_label = $HUD/WaveLabel
@onready var buff_label = $HUD/BuffLabel
@onready var heat_info = $HUD/HeatInfo
@onready var redline_mark = $HUD/HeatBar/RedlineMark
@onready var upgrade_screen = $UpgradeScreen
@onready var boss_label = $HUD/BossLabel
@onready var boss_bar = $HUD/BossBar
@onready var chips_label = $HUD/ChipsLabel
@onready var shop = $ShopScreen

var score := 0
var wave := 0
var to_spawn := 0
var queue := []                   # kdo se v této vlně ještě objeví
var alive := 0
var spawn_timer := 0.0
var game_over := false

var sector := 1
var current := {}                 # aktuální sektor (data + uzly)
var next_arena := {}              # sektor za otevřenou chodbou
var corridor := {}
var transition := false


func _ready():
	floor_template.hide()
	player.heat_changed.connect(_on_heat_changed)
	player.crashed.connect(func(): show_status("SYSTEM CRASH - REBOOTING..."))
	player.rebooted.connect(func():
		show_status("")
		Juice.play("reboot", -4.0, 0.0))
	player.died.connect(_on_player_died)
	upgrade_screen.chosen.connect(_on_upgrade_chosen)
	upgrade_screen.reroll.connect(_on_reroll)

	# první sektor
	var size = Vector2i(randi_range(14, 17), randi_range(14, 17))
	var lay = Gen.generate(Vector2i.ZERO, size, {}, false)
	current = build_arena(lay, pick_theme())
	player.global_position = tile_point(lay["start"])
	camera.target = player
	camera.snap()
	start_next_wave()


func _process(delta):
	update_buffs()
	chips_label.text = "ČIPY  %d" % player.chips
	update_heat_info()
	if transition and not next_arena.is_empty():
		check_enter_next()
	if game_over or to_spawn <= 0:
		return
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_enemy()
		spawn_timer = SPAWN_INTERVAL


func _unhandled_input(event):
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# ============================================================
#  Souřadnice
# ============================================================

# bod v dlaždicových souřadnicích (může být desetinný) -> obrazovka
func iso_point(x: float, y: float) -> Vector2:
	return ORIGIN + Vector2((x - y) * 32.0, (x + y) * 16.0)


func tile_point(v: Vector2) -> Vector2:
	return iso_point(v.x, v.y)


func cell_center(c: Vector2i) -> Vector2:
	return iso_point(c.x + 0.5, c.y + 0.5)


func screen_to_cell(p: Vector2) -> Vector2i:
	var d = p - ORIGIN
	var x = (d.x / 32.0 + d.y / 16.0) / 2.0
	var y = (d.y / 16.0 - d.x / 32.0) / 2.0
	return Vector2i(floori(x), floori(y))


# ============================================================
#  Stavba sektoru z vygenerovaných dat
# ============================================================

func pick_theme() -> Dictionary:
	var t = THEMES.pick_random()
	while not current.is_empty() and t["name"] == current["theme"]["name"]:
		t = THEMES.pick_random()
	return t


func build_arena(lay: Dictionary, theme: Dictionary) -> Dictionary:
	var root = Node2D.new()
	arenas.add_child(root)
	var fl = make_floor(lay["walk"].keys(), theme["floor"])
	root.add_child(fl)
	var ed = Edges.new()
	root.add_child(ed)
	var rt = {
		"layout": lay, "theme": theme, "root": root, "edges": ed, "void": null, "objects": [],
		"name": "%s-%02X" % [theme["name"], randi() % 256],
	}
	set_borders(rt, {})
	for p in lay["plates"]:
		var hp = PLATE_SCENE.instantiate()
		hp.position = tile_point(p)
		hp.start_offset = randf() * 6.0
		root.add_child(hp)
	for f in lay["fans"]:
		var fan = FAN_SCENE.instantiate()
		fan.position = tile_point(f)
		world.add_child(fan)
		rt["objects"].append(fan)
	for b in lay["blocks"]:
		var blk = BLOCK_SCENE.instantiate()
		blk.position = tile_point(b["center"])
		blk.size = b["size"]
		blk.height = b["height"]
		blk.edge_color = theme["block_edge"]
		world.add_child(blk)
		rt["objects"].append(blk)
	return rt


func make_floor(cells: Array, tint: Color) -> TileMapLayer:
	var fl = TileMapLayer.new()
	fl.tile_set = floor_template.tile_set
	fl.position = floor_template.position
	fl.modulate = tint
	for c in cells:
		fl.set_cell(c, 0, Vector2i(posmod(c.x + c.y, 2), 0))
	return fl


# okraje + neviditelná "zeď" kolem sektoru; open = dlaždice, které zůstanou průchozí
func set_borders(rt: Dictionary, open: Dictionary):
	rt["edges"].setup(rt["layout"]["walk"], open, rt["theme"]["edge"], ORIGIN)
	if rt["void"]:
		rt["void"].queue_free()
	rt["void"] = make_void(rt["layout"]["walk"], open)
	rt["root"].add_child(rt["void"])


func make_void(walk: Dictionary, exclude: Dictionary) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.collision_layer = VOID_LAYER
	body.collision_mask = 0
	var ring := {}
	for c in walk:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var n = c + Vector2i(dx, dy)
				if not walk.has(n) and not exclude.has(n):
					ring[n] = true
	for n in ring:
		var col = CollisionPolygon2D.new()
		col.polygon = PackedVector2Array([iso_point(n.x, n.y), iso_point(n.x + 1, n.y), iso_point(n.x + 1, n.y + 1), iso_point(n.x, n.y + 1)])
		body.add_child(col)
	return body


# ============================================================
#  Přechod do dalšího sektoru
# ============================================================

func open_exit():
	transition = true
	var lay = current["layout"]
	var ent = lay["entry"]
	var sides = [[0, 1], [0, -1], [1, 1], [1, -1]]
	sides.shuffle()
	var ex := {}
	for s in sides:
		if not ent.is_empty() and s[0] == ent["axis"] and s[1] == ent["sign"]:
			continue                       # tudy jsme přišli
		ex = Gen.find_exit(lay, s[0], s[1], randi_range(CORRIDOR_LEN.x, CORRIDOR_LEN.y))
		if not ex.is_empty():
			break
	if ex.is_empty():                       # nouzově: další vlna ve stejném sektoru
		transition = false
		start_next_wave()
		return

	# nový sektor za koncem chodby
	var boss_next = (wave + 1) % 5 == 0
	var size = BOSS_SIZE if boss_next else Vector2i(randi_range(SIZE_RANGE.x, SIZE_RANGE.y), randi_range(SIZE_RANGE.x, SIZE_RANGE.y))
	var ax: int = ex["axis"]
	var al: int = 1 - ax
	var origin = Vector2i.ZERO
	origin[ax] = ex["end"] + 1 if ex["sign"] > 0 else ex["end"] - size[ax]
	origin[al] = ex["lanes"][0] - randi_range(3, size[al] - 5)
	var entry = {"axis": ax, "sign": -ex["sign"], "lanes": ex["lanes"]}
	var lay2 = Gen.generate(origin, size, entry, boss_next)

	var ctiles := {}
	for t in ex["tiles"]:
		ctiles[t] = true
	next_arena = build_arena(lay2, pick_theme())
	set_borders(next_arena, ctiles)
	set_borders(current, ctiles)
	corridor = build_corridor(ex, lay["walk"], lay2["walk"])
	spawn_terminal(ex)

	# nový sektor se plynule objeví
	for n in [next_arena["root"]] + next_arena["objects"]:
		n.modulate.a = 0.0
		n.create_tween().tween_property(n, "modulate:a", 1.0, 0.8)
	Juice.play("charge", -2.0, 0.0)
	Juice.shake(0.2)


func build_corridor(ex: Dictionary, walk_a: Dictionary, walk_b: Dictionary) -> Dictionary:
	var root = Node2D.new()
	arenas.add_child(root)
	var tiles: Array = ex["tiles"].duplicate()
	var ax: int = ex["axis"]
	var sgn: int = ex["sign"]
	tiles.sort_custom(func(a, b): return a[ax] * sgn < b[ax] * sgn)
	var set := {}
	for t in tiles:
		set[t] = true
	var fl = make_floor([], Color(1.2, 1.2, 1.5))
	root.add_child(fl)
	var ed = Edges.new()
	root.add_child(ed)
	ed.setup(set, walk_a.merged(walk_b), Color(1.4, 1.4, 1.75), ORIGIN)
	root.add_child(make_void(set, walk_a.merged(walk_b)))

	# dlaždice chodby se postupně "vystaví"
	var tw = create_tween()
	for t in tiles:
		tw.tween_callback(fl.set_cell.bind(t, 0, Vector2i(posmod(t.x + t.y, 2), 0)))
		tw.tween_interval(0.025)

	# šipka na začátku chodby
	var dir = (Vector2(32, 16) if ax == 0 else Vector2(-32, 16)) * sgn
	var arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(-16, -14), Vector2(8, 0), Vector2(-16, 14), Vector2(-9, 0)])
	arrow.color = Color(1.7, 1.7, 2.0)
	arrow.rotation = dir.angle()
	arrow.scale = Vector2(1.0, 0.6)
	arrow.position = cell_center(tiles[0]) + dir.normalized() * 10.0
	root.add_child(arrow)
	var pulse = arrow.create_tween().set_loops()
	pulse.tween_property(arrow, "modulate:a", 0.25, 0.4)
	pulse.tween_property(arrow, "modulate:a", 1.0, 0.4)
	return {"root": root, "tiles": set}


# hráč došel do nového sektoru?
func check_enter_next():
	var c = screen_to_cell(player.global_position)
	var lay = next_arena["layout"]
	if not lay["walk"].has(c):
		return
	var e = lay["entry"]
	var edge = lay["origin"][e["axis"]] + (lay["size"][e["axis"]] - 1 if e["sign"] > 0 else 0)
	if absi(c[e["axis"]] - edge) >= 2:
		close_transition()


func close_transition():
	transition = false
	var old = current
	current = next_arena
	next_arena = {}
	set_borders(current, {})          # zavře vstup za hráčem
	dissolve([old["root"]] + old["objects"])
	dissolve([corridor["root"]])
	corridor = {}
	# bonusy, které zůstaly ve starém sektoru, zmizí
	for x in world.get_children():
		if (x.scene_file_path.ends_with("pickup_iso.tscn") or x.scene_file_path.ends_with("chip.tscn")) and not current["layout"]["walk"].has(screen_to_cell(x.global_position)):
			x.queue_free()
	sector += 1
	show_status("SEKTOR %d  ·  %s" % [sector, current["name"]], 2.0)
	Juice.play("reboot", -2.0, 0.0)
	get_tree().create_timer(1.6, false).timeout.connect(start_next_wave)


func dissolve(nodes: Array):
	for n in nodes:
		if is_instance_valid(n):
			var tw = n.create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.6)
			tw.tween_callback(n.queue_free)


# ============================================================
#  Čipy a terminál
# ============================================================

# rozdělí hodnotu do max. 6 čipů
func spawn_chips(pos: Vector2, total: int):
	var n = mini(total, 6)
	for i in n:
		var c = CHIP_SCENE.instantiate()
		c.value = floori(total / float(n)) + (1 if i < total % n else 0)
		c.global_position = pos + Vector2(randf_range(-8, 8), randf_range(-4, 4))
		c.vacuum = to_spawn == 0 and alive == 0      # poslední nepřítel vlny -> rovnou k hráči
		world.call_deferred("add_child", c)


# terminál stojí ve starém sektoru kousek od začátku chodby
func spawn_terminal(ex: Dictionary):
	var ax: int = ex["axis"]
	var sgn: int = ex["sign"]
	var first = ex["tiles"][0]
	for t in ex["tiles"]:
		if t[ax] * sgn < first[ax] * sgn:
			first = t
	var target = Vector2(first) + Vector2(0.5, 0.5)
	target[ax] -= sgn * 2.5            # zpět do sektoru
	target[1 - ax] += 2.5              # bokem od chodby
	var best = null
	var best_d = 1e9
	for c in current["layout"]["free"]:
		var d = (Vector2(c) + Vector2(0.5, 0.5)).distance_to(target)
		if d < best_d and not corridor["tiles"].has(c):
			best_d = d
			best = c
	if best == null:
		show_status("CESTA OTEVŘENA  >>  SEKTOR %d" % (sector + 1), 3.0)
		return
	var term = TERMINAL_SCENE.instantiate()
	term.position = cell_center(best)
	world.add_child(term)
	current["objects"].append(term)
	shop.setup(player, sector)
	term.opened.connect(func(): shop.open())
	show_status("CESTA DO SEKTORU %d OTEVŘENA  ·  TERMINÁL [E]" % (sector + 1), 3.0)


# ============================================================
#  Vlny
# ============================================================

func start_next_wave():
	if game_over:
		return
	wave += 1
	queue = build_wave(wave)
	to_spawn = queue.size()
	spawn_timer = 1.5
	wave_label.text = "WAVE %d  ·  %s" % [wave, current["name"]]
	if wave % 5 == 0:
		show_status("!! BOSS: VIRUS.EXE !!", 2.5)
		Juice.play("boss_spawn", 0.0, 0.0)
		Juice.shake(0.5)
		spawn_timer = 2.0
	else:
		show_status("WAVE %d" % wave, 1.5)
	if player.start_nitro > 0:            # z obchodu: start s dusíkem
		player.start_nitro -= 1
		player.nitro_timer = 6.0


# složení vlny: postupně přibývají drony, turrety a tanky, každá 5. vlna je boss
func build_wave(w: int) -> Array:
	var q = []
	if w % 5 == 0:
		q.append("boss")
		for i in floori(w / 5.0):
			q.append("drone")
		return q
	var n = 3 + w * 2 + player.extra_enemies
	var turrets = 0 if w < 3 else mini(1 + floori((w - 3) / 3.0), 3)
	var tanks = 0 if w < 4 else mini(1 + floori((w - 4) / 3.0), 4)
	var drones = 0 if w < 2 else floori(n * 0.25)
	var bugs = maxi(n - turrets - tanks - drones, 2)
	var rest = []
	for i in drones:
		rest.append("drone")
	for i in tanks:
		rest.append("tank")
	for i in bugs:
		rest.append("bug")
	rest.shuffle()
	for i in turrets:
		q.append("turret")         # turrety se rozmístí jako první
	return q + rest


func spawn_enemy():
	var kind = queue.pop_front()
	to_spawn = queue.size()
	var pos = find_free_spot() if kind == "turret" else cell_center(current["layout"]["spawns"].pick_random())
	add_enemy(kind, pos)


func add_enemy(kind: String, pos: Vector2):
	var e = KINDS[kind].instantiate()
	e.global_position = pos
	e.speed = (110.0 + wave * 12.0) * player.enemy_speed_mult
	if kind == "boss":
		e.hp = 150 + 70 * (floori(wave / 5.0) - 1) + player.enemy_hp_bonus * 10
		e.summon.connect(func(k, p):
			# přivolaný bug se nesmí objevit mimo sektor
			if not current["layout"]["walk"].has(screen_to_cell(p)):
				p = e.global_position
			add_enemy(k, p))
		e.hp_changed.connect(_on_boss_hp)
		e.phase_changed.connect(func(ph): show_status("VIRUS.EXE – FÁZE %d" % ph, 1.5))
		boss_label.show()
		boss_bar.show()
	else:
		e.hp += player.enemy_hp_bonus
	if kind == "turret":
		e.burst = 1 + floori(wave / 6.0)
	e.died.connect(_on_enemy_died.bind(kind))
	world.add_child(e)
	alive += 1


func _on_boss_hp(hp, max_hp):
	boss_bar.max_value = max_hp
	boss_bar.value = hp


# volné místo pro turret: v sektoru, mimo bloky a ne těsně u hráče
func find_free_spot() -> Vector2:
	var free: Array = current["layout"]["free"]
	for attempt in 40:
		var p = cell_center(free.pick_random())
		if Vector2(p.x - player.global_position.x, (p.y - player.global_position.y) * 2.0).length() >= 220.0:
			return p
	return cell_center(current["layout"]["spawns"].pick_random())


func spawn_pickup(pos):
	var p = PICKUP_SCENE.instantiate()
	# chladič padá 2x častěji
	p.type = [Pickup.Type.DOUBLE_JUMP, Pickup.Type.COOLANT, Pickup.Type.COOLANT, Pickup.Type.NITRO].pick_random()
	if not current["layout"]["walk"].has(screen_to_cell(pos)):
		pos = player.global_position + Vector2(randf_range(-30, 30), randf_range(-15, 15))
	p.global_position = pos
	world.call_deferred("add_child", p)


func _on_enemy_died(pos, value, drops, kind):
	alive -= 1
	score += value * player.multiplier()
	update_score()
	if drops >= 1.0:
		for i in int(drops):
			spawn_pickup(pos + Vector2(randf_range(-40, 40), randf_range(-20, 20)))
	elif randf() < drops * player.drop_mult:
		spawn_pickup(pos)
	spawn_chips(pos, CHIPS[kind])
	if kind == "boss":
		boss_label.hide()
		boss_bar.hide()
	if to_spawn == 0 and alive == 0 and not game_over:
		show_status("VIRUS.EXE ODSTRANĚN!" if kind == "boss" else "WAVE CLEAR!", 1.0)
		Juice.play("wave_clear", -2.0, 0.0)
		for c in get_tree().get_nodes_in_group("chips"):
			c.vacuum = true                   # čipy se slétnou k hráči
		get_tree().create_timer(1.0).timeout.connect(_offer_upgrades)


func _offer_upgrades():
	if game_over:
		return
	var choices = Upgrades.pick(player.upgrades, 3)
	if choices.is_empty():
		open_exit()                 # všechno už na maximu
		return
	upgrade_screen.reroll_cost = REROLL_BASE
	show_cards(choices)


func show_cards(choices: Array):
	var corrupts = []
	for id in choices:
		corrupts.append(Upgrades.pick_corrupt(id, player.corrupts))
	upgrade_screen.open(choices, corrupts, player.upgrades, player.corrupts)


# reroll karet za čipy (každý další dražší)
func _on_reroll():
	if player.chips < upgrade_screen.reroll_cost:
		Juice.play("jam", -4.0)
		return
	player.chips -= upgrade_screen.reroll_cost
	upgrade_screen.reroll_cost += 2
	Juice.play("buy", -4.0, 0.0)
	show_cards(Upgrades.pick(player.upgrades, 3))


func _on_upgrade_chosen(upgrade_id, corrupt_id):
	Juice.play("upgrade", -2.0, 0.0)
	player.apply_upgrade(upgrade_id)
	player.apply_corrupt(corrupt_id)
	open_exit()


func _on_player_died():
	game_over = true
	Juice.play("game_over", 0.0, 0.0)
	Juice.shake(1.0)
	Juice.hitstop(0.3)
	status.text = "GAME OVER\nScore: %d   ·   Sektor %d\nR = restart" % [score, sector]


# ============================================================
#  HUD
# ============================================================

func _on_heat_changed(value):
	heat_bar.value = value
	heat_bar.modulate = Color.WHITE.lerp(Color.RED, value / 100.0)
	update_score()


func update_score():
	score_label.text = "SCORE: %d   x%d" % [score, player.multiplier()]


func update_buffs():
	var parts = []
	if player.double_dash_timer > 0:
		parts.append("DOUBLE DASH %d s" % ceil(player.double_dash_timer))
	if player.nitro_timer > 0:
		parts.append("NITRO %d s" % ceil(player.nitro_timer))
	if player.shield > 0:
		parts.append("ŠTÍT x%d" % player.shield)
	if player.fuse > 0:
		parts.append("POJISTKA")
	buff_label.text = "   ".join(PackedStringArray(parts))


const OC_NAMES = ["-", "I", "II", "III"]


# řádek pod teplotou: úroveň overclocku, dash, vent, chlazení, REDLINE
func update_heat_info():
	var txt = "OC %s   DASH %d/%d" % [OC_NAMES[player.oc_level], player.dash_charges, player.max_dashes()]
	if player.vent_cd > 0:
		txt += "   VENT %.1f s" % player.vent_cd
	elif player.heat >= player.VENT_MIN_HEAT:
		txt += "   VENT PŘIPRAVEN [Q]"
	else:
		txt += "   VENT (min. 40 %)"
	if player.in_fan_t > 0:
		txt += "   CHLAZENÍ"
	if player.in_redline():
		txt += "   >> REDLINE <<"
		var blink = int(Time.get_ticks_msec() / 120) % 2 == 0
		heat_info.modulate = Color(3, 0.5, 0.3) if blink else Color(1.5, 0.8, 0.6)
	elif player.in_fan_t > 0:
		heat_info.modulate = Color(0.8, 2.0, 2.4)
	else:
		heat_info.modulate = Color(0.7, 1.2, 1.4)
	heat_info.text = txt
	redline_mark.position.x = heat_bar.size.x * player.redline_start / 100.0 - 1.0


# zobrazí text, volitelně ho po čase zase smaže
func show_status(text, time := 0.0):
	if game_over:
		return
	status.text = text
	if time > 0:
		get_tree().create_timer(time).timeout.connect(func():
			if status.text == text:
				status.text = "")
