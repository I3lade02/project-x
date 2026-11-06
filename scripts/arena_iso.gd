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
	"firewall": preload("res://scenes/boss_firewall.tscn"),
	"miner": preload("res://scenes/boss_miner.tscn"),
	"rootkit": preload("res://scenes/boss_rootkit.tscn"),
	"bsod": preload("res://scenes/boss_bsod.tscn"),
}
const PICKUP_SCENE = preload("res://scenes/pickup_iso.tscn")
const BLOCK_SCENE = preload("res://scenes/iso_block.tscn")
const PLATE_SCENE = preload("res://scenes/hot_plate_iso.tscn")
const FAN_SCENE = preload("res://scenes/fan_iso.tscn")
const CHIP_SCENE = preload("res://scenes/chip.tscn")
const TERMINAL_SCENE = preload("res://scenes/terminal.tscn")
const CORE_SCENE = preload("res://scenes/core.tscn")
const PLAYER_SCENE = preload("res://scenes/player_iso.tscn")
const Pickup = preload("res://scripts/pickup.gd")
const Upgrades = preload("res://scripts/upgrades.gd")
const Gen = preload("res://scripts/arena_gen.gd")
const Edges = preload("res://scripts/arena_edges.gd")
const NetSync = preload("res://scripts/net_sync.gd")

const ORIGIN = Vector2(640, 72)      # roh dlaždice (0, 0) na obrazovce
const SPAWN_INTERVAL = 0.75
const CORRIDOR_LEN = Vector2i(4, 6)
const SIZE_RANGE = Vector2i(20, 26)     # velikost sektoru v dlaždicích (min, max)
const FIRST_SIZE = Vector2i(22, 25)
const BOSS_SIZE = Vector2i(26, 26)
const VOID_LAYER = 32                # kolizní vrstva 6 = okraj sektoru / díry
const CHIPS = {"bug": 1, "drone": 1, "turret": 3, "tank": 4, "boss": 25, "firewall": 25, "miner": 25, "rootkit": 25, "bsod": 25}
# bossové (každá 5. vlna jeden, náhodně se střídají – žádný se neopakuje, dokud nepřijdou na řadu všichni)
const BOSSES = {
	"boss": {"name": "VIRUS.EXE", "color": Color(2.4, 0.5, 1.9), "hint": "Uhýbej salvám koulí, ve 3. fázi k němu nechoď blízko"},
	"firewall": {"name": "FIREWALL.SYS", "color": Color(2.6, 0.9, 0.25), "hint": "Paprsky zastaví blok, dash jimi proletí"},
	"miner": {"name": "MINER.EXE", "color": Color(2.2, 1.9, 0.3), "hint": "Uhni z dráhy nájezdu – po nárazu do zdi je zranitelný"},
	"rootkit": {"name": "ROOTKIT.DLL", "color": Color(0.5, 2.6, 1.0), "hint": "Mizí a nechává miny – sleduj, kde se objeví"},
	"bsod": {"name": "BSOD.SYS", "color": Color(0.6, 1.4, 3.0), "hint": "Rázovou vlnu proleť dashem"},
}
const REROLL_BASE = 3
const COOP_ENEMY_MULT = 1.5          # v co-opu víc nepřátel
const COOP_BOSS_HP = 1.6
const THEMES = [
	{"name": "CPU", "floor": Color(1.0, 1.1, 1.4), "edge": Color(0.3, 1.1, 1.6), "block_edge": Color(0.25, 0.9, 1.25)},
	{"name": "GPU", "floor": Color(0.9, 1.3, 1.0), "edge": Color(0.35, 1.5, 0.55), "block_edge": Color(0.3, 1.2, 0.45)},
	{"name": "RAM", "floor": Color(1.15, 0.9, 1.35), "edge": Color(1.25, 0.4, 1.6), "block_edge": Color(1.0, 0.35, 1.3)},
	{"name": "PSU", "floor": Color(1.25, 0.95, 0.75), "edge": Color(1.6, 0.7, 0.2), "block_edge": Color(1.3, 0.55, 0.18)},
	{"name": "SSD", "floor": Color(1.05, 1.05, 1.15), "edge": Color(1.35, 1.35, 1.5), "block_edge": Color(1.1, 1.1, 1.25)},
]

@onready var world = $World
@onready var player = $World/Player       # hráč 1
@onready var arenas = $Arenas
@onready var floor_template = $Floor
@onready var camera = $Camera
@onready var status = $HUD/StatusLabel
@onready var score_label = $HUD/ScoreLabel
@onready var wave_label = $HUD/WaveLabel
@onready var upgrade_screen = $UpgradeScreen
@onready var boss_label = $HUD/BossLabel
@onready var boss_bar = $HUD/BossBar
@onready var p1_hud = $HUD/P1Hud
@onready var p2_hud = $HUD/P2Hud
@onready var shop = $ShopScreen
@onready var cores_label = $HUD/CoresLabel

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
var exit_target = null            # kam ukazuje šipka na okraji obrazovky (chodba / terminál)
var players := []                 # všichni hráči (1 nebo 2)
var local_player                  # hráč na tomto počítači (kvůli kameře, HUD a míření)
var net_sync = null               # synchronizace po síti (jen v LAN)
var choosing := []                # kdo ještě vybírá upgrade po vlně
var run_cores := 0                # jádra sebraná v tomto runu (uloží se na konci)
var banked := false               # jádra už uložena
var boss_kind := "boss"           # boss aktuální / poslední bossí vlny

static var boss_bag := []         # zamíchané pořadí bossů (přežije i restart)
static var last_boss := ""


func _ready():
	floor_template.hide()
	players = [player]
	local_player = player
	if GameSettings.coop and not Net.is_online():
		GameSettings.apply_coop_bindings()
	if GameSettings.coop or Net.is_online():
		var p2 = PLAYER_SCENE.instantiate()
		p2.player_index = 1
		p2.name = "Player2"
		p2.remote_input = Net.is_host()
		world.add_child(p2)
		players.append(p2)
	if Net.is_online():
		net_sync = NetSync.new()
		net_sync.name = "NetSync"
		add_child(net_sync)
	if Net.is_client():
		_setup_client()
		return
	if Net.is_host():
		Net.peer_left.connect(_on_peer_left)
	for p in players:
		p.heat_changed.connect(func(_v): update_score())
		p.crashed.connect(func(): show_status(tag(p) + "SYSTEM CRASH - REBOOTING..."))
		p.rebooted.connect(func():
			show_status("")
			Juice.play("reboot", -4.0, 0.0))
		p.died.connect(_on_player_died.bind(p))
	p1_hud.player = player
	Progress.apply_to(player, Progress.levels)      # skill tree (hráč 1 / hostitel)
	if players.size() > 1:
		p2_hud.player = players[1]
		p2_hud.show()
	upgrade_screen.chosen.connect(_on_upgrade_chosen)
	upgrade_screen.reroll.connect(_on_reroll)

	# první sektor
	var size = Vector2i(randi_range(FIRST_SIZE.x, FIRST_SIZE.y), randi_range(FIRST_SIZE.x, FIRST_SIZE.y))
	var lay = Gen.generate(Vector2i.ZERO, size, {}, false)
	current = build_arena(lay, pick_theme())
	place_players(tile_point(lay["start"]))
	camera.targets = players if not Net.is_online() else [local_player]
	camera.snap()
	start_next_wave()


# ============================================================
#  Síť – klient (jen zobrazuje, simulace běží u hostitele)
# ============================================================

func _setup_client():
	local_player = players[1]
	for p in players:
		p.puppet = true
		p.set_physics_process(false)
		p.collision_layer = 0
		p.collision_mask = 0
	p1_hud.player = local_player
	p2_hud.player = players[0]
	p2_hud.show()
	camera.targets = [local_player]
	upgrade_screen.chosen.connect(func(u, c): net_sync.send_choice(u, c))
	upgrade_screen.reroll.connect(func(): net_sync.send_reroll())
	Net.server_left.connect(func():
		Net.last_message = "Hostitel ukončil hru."
		get_tree().paused = false
		get_tree().change_scene_to_file(Net.MENU_SCENE))
	show_status("PŘIPOJUJI SE K HOSTITELI…")


func client_init(lay: Dictionary, theme: Dictionary, name: String, sec: int):
	for k in ["current", "next_arena", "corridor"]:
		var rt = get(k)
		if not rt.is_empty():
			dissolve([rt["root"]] + rt.get("objects", []))
	current = build_arena(lay, theme, name)
	next_arena = {}
	corridor = {}
	sector = sec
	place_players(tile_point(lay["start"]))
	camera.snap()


func client_open(ex: Dictionary, lay2: Dictionary, theme: Dictionary, name: String):
	var ctiles := {}
	for t in ex["tiles"]:
		ctiles[t] = true
	next_arena = build_arena(lay2, theme, name)
	set_borders(next_arena, ctiles)
	set_borders(current, ctiles)
	corridor = build_corridor(ex, current["layout"]["walk"], lay2["walk"])
	for n in [next_arena["root"]] + next_arena["objects"]:
		n.modulate.a = 0.0
		n.create_tween().tween_property(n, "modulate:a", 1.0, 0.8)


func client_close():
	if next_arena.is_empty():
		return
	var old = current
	current = next_arena
	next_arena = {}
	set_borders(current, {})
	dissolve([old["root"]] + old["objects"])
	if not corridor.is_empty():
		dissolve([corridor["root"]])
	corridor = {}
	sector += 1


func _on_peer_left():
	if players.size() > 1:
		var p2 = players[1]
		players.erase(p2)
		p2.queue_free()
		p2_hud.hide()
	show_status("HRÁČ 2 SE ODPOJIL", 3.0)


func _exit_tree():
	bank_run(run_cores)                # odchod uprostřed runu = uložit aspoň sebraná jádra
	if GameSettings.coop:
		GameSettings.restore_bindings()


# "P1: " / "P2: " v co-opu, jinak nic
func tag(p) -> String:
	return "P%d: " % (p.player_index + 1) if players.size() > 1 else ""


func alive_players() -> Array:
	return players.filter(func(p): return not p.dead)


# postaví hráče vedle sebe na daný bod
func place_players(pos: Vector2):
	for i in players.size():
		var off = Vector2(-28, -8) if i == 0 else Vector2(28, 8)
		if players.size() == 1:
			off = Vector2.ZERO
		players[i].global_position = pos + off
		players[i].velocity = Vector2.ZERO


# --- corrupty, které mění nepřátele, se v co-opu sčítají ---
func team_mult() -> int:
	var m = 1
	for p in alive_players():
		m = maxi(m, p.multiplier())
	return m


func enemy_hp_bonus() -> int:
	var b = 0
	for p in players:
		b += p.enemy_hp_bonus
	return b


func enemy_speed_mult() -> float:
	var m = 1.0
	for p in players:
		m += p.enemy_speed_mult - 1.0
	return m


func extra_enemies() -> int:
	var n = 0
	for p in players:
		n += p.extra_enemies
	return n


func drop_mult() -> float:
	var m = 1.0
	for p in players:
		m *= p.drop_mult
	return m


func _process(delta):
	if Net.is_client():
		return
	if transition and not next_arena.is_empty():
		check_enter_next()
	if game_over or to_spawn <= 0:
		return
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_enemy()
		spawn_timer = SPAWN_INTERVAL


func _unhandled_input(event):
	if game_over and event.is_action_pressed("restart") and not Net.is_client():
		if net_sync:
			net_sync.send_restart()
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


func build_arena(lay: Dictionary, theme: Dictionary, arena_name := "") -> Dictionary:
	var root = Node2D.new()
	arenas.add_child(root)
	var fl = make_floor(lay["walk"].keys(), theme["floor"])
	root.add_child(fl)
	var ed = Edges.new()
	root.add_child(ed)
	var rt = {
		"layout": lay, "theme": theme, "root": root, "edges": ed, "void": null, "objects": [],
		"name": arena_name if arena_name != "" else "%s-%02X" % [theme["name"], randi() % 256],
		"plates": [],
	}
	set_borders(rt, {})
	for p in lay["plates"]:
		var hp = PLATE_SCENE.instantiate()
		hp.position = tile_point(p)
		hp.start_offset = randf() * 6.0
		root.add_child(hp)
		rt["plates"].append(hp)
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
	if net_sync:
		net_sync.send_sector_open(ex, lay2, next_arena["theme"], next_arena["name"])
	exit_target = tile_point(lay2["start"])

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
	var lay = next_arena["layout"]
	var e = lay["entry"]
	var edge = lay["origin"][e["axis"]] + (lay["size"][e["axis"]] - 1 if e["sign"] > 0 else 0)
	for p in alive_players():
		var c = screen_to_cell(p.global_position)
		if lay["walk"].has(c) and absi(c[e["axis"]] - edge) >= 2:
			close_transition()
			return


func close_transition():
	transition = false
	exit_target = null
	var old = current
	current = next_arena
	next_arena = {}
	set_borders(current, {})          # zavře vstup za hráčem
	if net_sync:
		net_sync.send_sector_close()
	# co-op: kdo zůstal pozadu, přesune se; mrtvý hráč se vrátí do hry
	var start = tile_point(current["layout"]["start"])
	var k = 0
	for p in players:
		var off = Vector2(-28 + 56 * k, -8 + 16 * k)
		if p.dead:
			p.revive(start + off)
			show_status(tag(p) + "ZPĚT ONLINE", 2.0)
		elif not current["layout"]["walk"].has(screen_to_cell(p.global_position)):
			p.global_position = start + off
			p.velocity = Vector2.ZERO
			Juice.burst(p.global_position + Vector2(0, -20), Color(0.6, 1.8, 2.2), 16)
		k += 1
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
	shop.reset(sector)
	term.opened.connect(func(p):
		if p.remote_input:
			net_sync.send_shop(shop.remote_data(p))
		else:
			shop.open_for(p))
	show_status("CESTA DO SEKTORU %d OTEVŘENA  ·  TERMINÁL [E]" % (sector + 1), 3.0)


# ============================================================
#  Vlny
# ============================================================

func start_next_wave():
	if game_over:
		return
	wave += 1
	if wave % 5 == 0:
		boss_kind = next_boss()
	queue = build_wave(wave)
	to_spawn = queue.size()
	spawn_timer = 1.5
	wave_label.text = "WAVE %d  ·  %s" % [wave, current["name"]]
	if wave % 5 == 0:
		show_status("!! BOSS: %s !!\n%s" % [BOSSES[boss_kind]["name"], BOSSES[boss_kind]["hint"]], 3.5)
		Juice.play("boss_spawn", 0.0, 0.0)
		Juice.shake(0.5)
		spawn_timer = 2.0
	else:
		show_status("WAVE %d" % wave, 1.5)
	for p in players:
		if p.start_nitro > 0:             # z obchodu: start s dusíkem
			p.start_nitro -= 1
			p.nitro_timer = 6.0


# složení vlny: postupně přibývají drony, turrety a tanky, každá 5. vlna je boss
func build_wave(w: int) -> Array:
	var q = []
	if w % 5 == 0:
		q.append(boss_kind)
		for i in floori(w / 5.0):
			q.append("drone")
		return q
	var n = 5 + w * 2 + extra_enemies()
	if players.size() > 1:
		n = roundi(n * COOP_ENEMY_MULT)
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
	var pos = cell_center(current["layout"]["spawns"].pick_random())
	if kind == "turret":
		pos = find_free_spot()
	elif is_boss(kind):
		pos = boss_spot()
	add_enemy(kind, pos)


func add_enemy(kind: String, pos: Vector2):
	var e = KINDS[kind].instantiate()
	e.global_position = pos
	e.speed = (110.0 + wave * 12.0) * enemy_speed_mult()
	if is_boss(kind):
		e.hp = roundi((150 + 70 * (floori(wave / 5.0) - 1) + enemy_hp_bonus() * 10) * e.hp_scale)
		if players.size() > 1:
			e.hp = roundi(e.hp * COOP_BOSS_HP)
		e.summon.connect(func(k, p):
			if k == "turret":
				p = find_free_spot()
			# přivolaný nepřítel se nesmí objevit mimo sektor
			elif not current["layout"]["walk"].has(screen_to_cell(p)):
				p = e.global_position
			add_enemy(k, p))
		e.hp_changed.connect(_on_boss_hp)
		e.phase_changed.connect(func(ph): show_status("%s – FÁZE %d" % [BOSSES[kind]["name"], ph], 1.5))
		set_boss_hud(kind)
		boss_label.show()
		boss_bar.show()
	else:
		e.hp += enemy_hp_bonus()
	if kind == "turret":
		e.burst = 1 + floori(wave / 6.0)
	e.died.connect(_on_enemy_died.bind(kind))
	world.add_child(e)
	alive += 1


func is_boss(kind: String) -> bool:
	return BOSSES.has(kind)


# další boss ze zamíchaného pytlíku
func next_boss() -> String:
	if boss_bag.is_empty():
		boss_bag = BOSSES.keys()
		boss_bag.shuffle()
		if boss_bag[0] == last_boss:          # stejný boss dvakrát po sobě ne
			boss_bag.push_back(boss_bag.pop_front())
	last_boss = boss_bag.pop_front()
	return last_boss


# jméno a barva bosse v HUD
func set_boss_hud(kind: String):
	var b = BOSSES.get(kind, BOSSES["boss"])
	boss_label.text = b["name"]
	boss_label.add_theme_color_override("font_color", b["color"])
	boss_bar.modulate = b["color"]


func _on_boss_hp(hp, max_hp):
	boss_bar.max_value = max_hp
	boss_bar.value = hp


# místo pro bosse: volné políčko s volným okolím co nejblíž středu sektoru (ať se nezasekne u kraje)
func boss_spot() -> Vector2:
	var free: Array = current["layout"]["free"]
	var is_free := {}
	var mid = Vector2.ZERO
	for c in free:
		is_free[c] = true
		mid += Vector2(c)
	mid /= free.size()
	var best = free[0]
	var best_d = INF
	for c in free:
		var open = true
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if not is_free.has(c + Vector2i(dx, dy)):
					open = false
		var d = Vector2(c).distance_to(mid)
		if open and d < best_d:
			best_d = d
			best = c
	return cell_center(best)


# volné místo pro turret: v sektoru, mimo bloky a ne těsně u hráče
func find_free_spot() -> Vector2:
	var free: Array = current["layout"]["free"]
	for attempt in 40:
		var p = cell_center(free.pick_random())
		var ok = true
		for pl in players:
			if Vector2(p.x - pl.global_position.x, (p.y - pl.global_position.y) * 2.0).length() < 220.0:
				ok = false
		if ok:
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
	score += value * team_mult()
	update_score()
	if drops >= 1.0:
		for i in int(drops) * players.size():
			spawn_pickup(pos + Vector2(randf_range(-40, 40), randf_range(-20, 20)))
	elif randf() < drops * drop_mult():
		spawn_pickup(pos)
	spawn_chips(pos, CHIPS[kind])
	if is_boss(kind):
		for i in Progress.BOSS_CORES:
			spawn_core(pos + Vector2(randf_range(-30, 30), randf_range(-15, 15)))
	elif randf() < Progress.CORE_DROP_CHANCE:
		spawn_core(pos)
	if is_boss(kind):
		boss_label.hide()
		boss_bar.hide()
	if to_spawn == 0 and alive == 0 and not game_over:
		show_status(BOSSES[kind]["name"] + " ODSTRANĚN!" if is_boss(kind) else "WAVE CLEAR!", 1.0)
		Juice.play("wave_clear", -2.0, 0.0)
		for c in get_tree().get_nodes_in_group("chips") + get_tree().get_nodes_in_group("cores"):
			c.vacuum = true                   # čipy a jádra se slétnou k hráči
		get_tree().create_timer(1.0).timeout.connect(_offer_upgrades)


func _offer_upgrades():
	if game_over:
		return
	choosing = players.duplicate()     # v co-opu vybírá každý svou kartu
	next_chooser()


# další hráč na řadě s výběrem karty (nebo otevřít cestu dál)
func next_chooser():
	while not choosing.is_empty():
		var p = choosing[0]
		var choices = Upgrades.pick(p.upgrades, 3)
		if choices.is_empty():
			choosing.pop_front()        # všechno už na maximu
			continue
		upgrade_screen.reroll_cost = 0 if p.get_meta("free_reroll", false) else REROLL_BASE
		show_cards(choices)
		return
	open_exit()


func show_cards(choices: Array):
	var p = choosing[0]
	var corrupts = []
	for id in choices:
		corrupts.append(Upgrades.pick_corrupt(id, p.corrupts))
	var title = ""
	if players.size() > 1:
		title = "HRÁČ %d – vyber upgrade (pozor na corrupt!)" % (p.player_index + 1)
	if p.remote_input:
		# hráč 2 vybírá na svém počítači, hostitel čeká
		net_sync.send_cards(choices, corrupts, title, upgrade_screen.reroll_cost)
		get_tree().paused = true
		show_status("HRÁČ 2 VYBÍRÁ UPGRADE…")
		return
	if Net.is_host():
		show_status("HRÁČ 1 VYBÍRÁ UPGRADE…")
	upgrade_screen.open(choices, corrupts, p.upgrades, p.corrupts, p, title)


# (host) volby hráče 2 ze sítě
func remote_choice(upgrade_id: String, corrupt_id: String):
	if choosing.is_empty() or not choosing[0].remote_input:
		return
	get_tree().paused = false
	show_status("")
	_on_upgrade_chosen(upgrade_id, corrupt_id)


func remote_reroll():
	if not choosing.is_empty() and choosing[0].remote_input:
		_on_reroll()


func remote_buy(id: String):
	if players.size() < 2:
		return
	var p = players[1]
	var msg = shop.purchase(p, id)
	if msg != "":
		Juice.play("buy", -2.0, 0.0)
	net_sync.send_shop(shop.remote_data(p, msg))


# reroll karet za čipy (každý další dražší)
func _on_reroll():
	var p = choosing[0]
	if p.chips < upgrade_screen.reroll_cost:
		Juice.play("jam", -4.0)
		return
	p.chips -= upgrade_screen.reroll_cost
	upgrade_screen.reroll_cost = REROLL_BASE if upgrade_screen.reroll_cost == 0 else upgrade_screen.reroll_cost + 2
	Juice.play("buy", -4.0, 0.0)
	show_cards(Upgrades.pick(p.upgrades, 3))


func _on_upgrade_chosen(upgrade_id, corrupt_id):
	Juice.play("upgrade", -2.0, 0.0)
	var p = choosing.pop_front()
	p.apply_upgrade(upgrade_id)
	p.apply_corrupt(corrupt_id)
	next_chooser()


func _on_player_died(p):
	if not alive_players().is_empty():
		show_status(tag(p) + "OFFLINE – vrátí se v dalším sektoru", 3.0)
		Juice.play("crash", -4.0)
		return
	game_over = true
	Juice.play("game_over", 0.0, 0.0)
	Juice.shake(1.0)
	Juice.hitstop(0.3)
	var hint = "R = restart (hostitel)" if Net.is_online() else "R = restart"
	var bonus = Progress.run_bonus(sector)
	bank_run(run_cores + bonus)
	status.text = "GAME OVER\nScore: %d   ·   Sektor %d\n+%d JADER  (sebráno %d + bonus %d)\n%s" % [score, sector, run_cores + bonus, run_cores, bonus, hint]


# ============================================================
#  HUD
# ============================================================

func update_score():
	score_label.text = "SCORE: %d   x%d" % [score, team_mult()]
	cores_label.text = "JÁDRA  %d" % run_cores


# ============================================================
#  Jádra (vzácná měna pro skill tree)
# ============================================================

func spawn_core(pos: Vector2):
	var c = CORE_SCENE.instantiate()
	if not current["layout"]["walk"].has(screen_to_cell(pos)):
		pos = player.global_position
	c.global_position = pos
	c.vacuum = to_spawn == 0 and alive == 0
	world.call_deferred("add_child", c)


# sebral ho kterýkoli hráč (patří celému týmu)
func collect_core():
	run_cores += 1
	update_score()
	Juice.play("core", -2.0, 0.0)
	show_status("+1 JÁDRO", 1.0)


# uloží jádra do skill tree (jen jednou za run)
func bank_run(total: int):
	if banked:
		return
	banked = true
	Progress.add_cores(total)
	if net_sync and Net.is_host():
		net_sync.send_run_end(total)


# (host) skill tree hráče 2 poslaný po síti
func apply_remote_meta(lv: Dictionary):
	if players.size() > 1:
		Progress.apply_to(players[1], lv)


# (klient) hostitel ukončil run -> uložit jádra
func client_run_end(total: int):
	if banked:
		return
	banked = true
	Progress.add_cores(total)


# zobrazí text, volitelně ho po čase zase smaže
func show_status(text, time := 0.0):
	if game_over:
		return
	status.text = text
	if time > 0:
		get_tree().create_timer(time).timeout.connect(func():
			if status.text == text:
				status.text = "")
