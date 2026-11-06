extends Node
## Synchronizace hry po síti (uzel NetSync v aréně).
## Host: posílá klientovi stav světa (~30× za s) a události, přijímá vstupy hráče 2.
## Klient: zobrazuje stav (loutky), posílá vstupy, ukazuje karty upgradů a obchod.

const SEND_EVERY = 2                    # snímek stavu každý 2. fyzikální krok (30 Hz)
const BASENAME_KIND = {"enemy_iso": "bug", "drone": "drone", "turret": "turret", "tank": "tank", "boss": "boss",
	"boss_firewall": "firewall", "boss_miner": "miner", "boss_rootkit": "rootkit", "boss_bsod": "bsod"}
const BULLET_SCENE = preload("res://scenes/bullet_iso.tscn")
const ORB_SCENE = preload("res://scenes/heat_orb.tscn")
const CHIP_SCENE = preload("res://scenes/chip.tscn")
const PICKUP_SCENE = preload("res://scenes/pickup_iso.tscn")
const TERMINAL_SCENE = preload("res://scenes/terminal.tscn")
const CORE_SCENE = preload("res://scenes/core.tscn")

var arena
var client_ready := false               # (host) klient už má scénu načtenou
var _frame := 0
var _snap = null                        # (klient) poslední přijatý stav
var _puppets := {"e": {}, "b": {}, "o": {}, "c": {}, "k": {}, "t": {}, "r": {}}
var _counts := {"dash": 0, "vent": 0, "interact": 0}
var _interact_block := 0.0
var _inited := false                   # (klient) dostal už svět od hostitele
var _hello_t := 1.0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	arena = get_parent()
	if Net.is_client():
		_hello.rpc_id(1, Progress.levels)


# ============================================================
#  HOST
# ============================================================

@rpc("any_peer", "call_remote", "reliable")
func _hello(meta_levels: Dictionary):
	if not Net.is_host() or client_ready:
		return
	client_ready = true
	arena.apply_remote_meta(meta_levels)      # skill tree hráče 2
	var cur = arena.current
	_init_world.rpc(cur["layout"], cur["theme"], cur["name"], arena.sector)


func _physics_process(_delta):
	if Net.is_host():
		_frame += 1
		if client_ready and _frame % SEND_EVERY == 0:
			_snapshot.rpc(build_snapshot())
	elif Net.is_client():
		_send_input()


func build_snapshot() -> Dictionary:
	var e = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var kind = BASENAME_KIND.get(n.scene_file_path.get_file().get_basename(), "bug")
		var extra = 0.0
		if kind == "turret":
			extra = Vector2(n.gun.rotation, 1.0 - n.charging / n.CHARGE_TIME if n.charging > 0 else 0.0)
		elif n.has_method("net_extra"):
			extra = n.net_extra()
		e.append([n.get_instance_id(), n.global_position, kind, n.hp, extra])
	var b = []
	var o = []
	var c = []
	var k = []
	var t = []
	var r = []
	for n in arena.world.get_children():
		var path = n.scene_file_path
		if path.ends_with("bullet_iso.tscn"):
			b.append([n.get_instance_id(), n.global_position, n.direction, n.hot])
		elif path.ends_with("heat_orb.tscn"):
			o.append([n.get_instance_id(), n.global_position])
		elif path.ends_with("chip.tscn"):
			c.append([n.get_instance_id(), n.global_position])
		elif path.ends_with("pickup_iso.tscn"):
			k.append([n.get_instance_id(), n.global_position, n.type])
		elif path.ends_with("terminal.tscn"):
			t.append([n.get_instance_id(), n.global_position])
		elif path.ends_with("core.tscn"):
			r.append([n.get_instance_id(), n.global_position])
	var p = []
	for pl in arena.players:
		p.append(pl.net_state())
	var plates = [_plate_states(arena.current), _plate_states(arena.next_arena)]
	var ui = [arena.score_label.text, arena.wave_label.text, arena.status.text,
		arena.boss_bar.visible, arena.boss_bar.value, arena.boss_bar.max_value, arena.exit_target, arena.run_cores, arena.boss_kind]
	return {"p": p, "e": e, "b": b, "o": o, "c": c, "k": k, "t": t, "r": r, "ui": ui, "pl": plates}


func _plate_states(rt: Dictionary) -> Array:
	var out = []
	if rt.is_empty():
		return out
	for pl in rt.get("plates", []):
		if is_instance_valid(pl):
			out.append([pl.state, pl.timer])
	return out


# vstupy hráče 2
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _input_state(move: Vector2, aim: Vector2, shoot: bool, oc: bool, counts: Dictionary):
	if not Net.is_host() or arena.players.size() < 2:
		return
	arena.players[1].set_net_input(move, aim, shoot, oc, counts)


# --- události sektorů ---
func send_sector_open(ex: Dictionary, lay2: Dictionary, theme: Dictionary, name: String):
	if client_ready:
		_sector_open.rpc(ex, lay2, theme, name)


func send_sector_close():
	if client_ready:
		_sector_close.rpc()


# --- upgrady hráče 2 ---
func send_cards(choices: Array, corrupts: Array, title: String, reroll_cost: int):
	var p = arena.players[1]
	_show_cards.rpc_id(_client_id(), choices, corrupts, p.upgrades, p.corrupts, title, reroll_cost)


@rpc("any_peer", "call_remote", "reliable")
func _choose(upgrade_id: String, corrupt_id: String):
	if Net.is_host():
		arena.remote_choice(upgrade_id, corrupt_id)


@rpc("any_peer", "call_remote", "reliable")
func _reroll():
	if Net.is_host():
		arena.remote_reroll()


# --- obchod hráče 2 ---
func send_shop(data: Dictionary):
	_shop.rpc_id(_client_id(), data)


@rpc("any_peer", "call_remote", "reliable")
func _buy(id: String):
	if Net.is_host():
		arena.remote_buy(id)


# konec runu -> klient si uloží jádra
func send_run_end(total: int):
	if client_ready and is_inside_tree():
		_run_end.rpc(total)


func send_restart():
	if client_ready:
		_restart.rpc()


func _client_id() -> int:
	var peers = multiplayer.get_peers()
	return peers[0] if not peers.is_empty() else 0


# ============================================================
#  KLIENT
# ============================================================

@rpc("authority", "call_remote", "reliable")
func _init_world(lay: Dictionary, theme: Dictionary, name: String, sector: int):
	_inited = true
	arena.client_init(lay, theme, name, sector)


@rpc("authority", "call_remote", "reliable")
func _sector_open(ex: Dictionary, lay2: Dictionary, theme: Dictionary, name: String):
	arena.client_open(ex, lay2, theme, name)


@rpc("authority", "call_remote", "reliable")
func _sector_close():
	arena.client_close()


@rpc("authority", "call_remote", "reliable")
func _show_cards(choices: Array, corrupts: Array, owned: Dictionary, owned_corrupts: Dictionary, title: String, reroll_cost: int):
	arena.upgrade_screen.reroll_cost = reroll_cost
	arena.upgrade_screen.open(choices, corrupts, owned, owned_corrupts, arena.local_player, title)


@rpc("authority", "call_remote", "reliable")
func _shop(data: Dictionary):
	arena.shop.open_remote(data, func(id): _buy.rpc_id(1, id))


@rpc("authority", "call_remote", "reliable")
func _run_end(total: int):
	arena.client_run_end(total)


@rpc("authority", "call_remote", "reliable")
func _restart():
	get_tree().paused = false
	get_tree().reload_current_scene()


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(s: Dictionary):
	_snap = s


func send_choice(upgrade_id: String, corrupt_id: String):
	_choose.rpc_id(1, upgrade_id, corrupt_id)


func send_reroll():
	_reroll.rpc_id(1)


func _send_input():
	var me = arena.local_player
	if me == null:
		return
	var ui_open = get_tree().paused
	for n in get_tree().get_nodes_in_group("ui_modal"):
		if n.visible:
			ui_open = true
	if arena.shop.root.visible:
		_interact_block = 0.3
	_interact_block -= get_physics_process_delta_time()
	var move = Vector2.ZERO
	var shoot = false
	var oc = false
	if not ui_open:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		shoot = Input.is_action_pressed("shoot")
		oc = Input.is_action_pressed("overclock")
		for a in ["dash", "vent"]:
			if Input.is_action_just_pressed(a):
				_counts[a] += 1
		if Input.is_action_just_pressed("interact") and _interact_block <= 0:
			_counts["interact"] += 1
	_input_state.rpc_id(1, move, _local_aim(), shoot, oc, _counts)


func _local_aim() -> Vector2:
	var me = arena.local_player
	var origin = me.global_position + Vector2(0, -me.AIM_HEIGHT)
	var to = me.get_global_mouse_position() - origin
	return to.normalized() if to.length() > 4.0 else me.aim_dir


func _process(delta):
	if not Net.is_client():
		return
	if not _inited:                      # hostitel ještě nemusí mít scénu načtenou -> zkusit znovu
		_hello_t -= delta
		if _hello_t <= 0:
			_hello_t = 1.0
			_hello.rpc_id(1, Progress.levels)
	if _snap == null:
		return
	var s = _snap
	# hráči
	for i in mini(s["p"].size(), arena.players.size()):
		var pl = arena.players[i]
		pl.apply_net_state(s["p"][i], delta, _local_aim() if pl == arena.local_player else null)
	# entity
	_sync("e", s["e"], delta, _make_enemy, _update_enemy)
	_sync("b", s["b"], delta, _make_bullet, Callable())
	_sync("o", s["o"], delta, func(_r): return ORB_SCENE.instantiate(), Callable())
	_sync("c", s["c"], delta, func(_r): return CHIP_SCENE.instantiate(), Callable())
	_sync("k", s["k"], delta, _make_pickup, Callable())
	_sync("t", s["t"], delta, func(_r): return TERMINAL_SCENE.instantiate(), _update_terminal)
	_sync("r", s["r"], delta, func(_r): return CORE_SCENE.instantiate(), Callable())
	# UI
	var ui = s["ui"]
	arena.score_label.text = ui[0]
	arena.wave_label.text = ui[1]
	arena.status.text = ui[2]
	arena.boss_label.visible = ui[3]
	arena.boss_bar.visible = ui[3]
	arena.boss_bar.max_value = ui[5]
	arena.boss_bar.value = ui[4]
	arena.exit_target = ui[6]
	arena.run_cores = ui[7]
	arena.cores_label.text = "JÁDRA  %d" % ui[7]
	if ui[8] != arena.boss_kind:
		arena.boss_kind = ui[8]
		arena.set_boss_hud(ui[8])
	# plotny
	_apply_plates(arena.current, s["pl"][0])
	_apply_plates(arena.next_arena, s["pl"][1])


func _apply_plates(rt: Dictionary, states: Array):
	if rt.is_empty():
		return
	var list = rt.get("plates", [])
	for i in mini(list.size(), states.size()):
		var pl = list[i]
		if is_instance_valid(pl) and pl.state != states[i][0]:
			pl.state = states[i][0]
			pl.timer = states[i][1]


# vytvoří/aktualizuje/smaže loutky podle seznamu [id, pozice, ...]
func _sync(key: String, rows: Array, delta: float, make: Callable, update: Callable):
	var store: Dictionary = _puppets[key]
	var seen := {}
	for r in rows:
		var id = r[0]
		seen[id] = true
		var n = store.get(id)
		if n == null or not is_instance_valid(n):
			n = make.call(r)
			n.global_position = r[1]
			arena.world.add_child(n)
			_make_puppet(n)
			store[id] = n
		else:
			n.global_position = n.global_position.lerp(r[1], 1.0 - exp(-20.0 * delta))
		if update.is_valid():
			update.call(n, r)
	for id in store.keys():
		if not seen.has(id):
			var n = store[id]
			if is_instance_valid(n):
				n.queue_free()
			store.erase(id)


func _make_puppet(n: Node):
	n.set_physics_process(false)
	n.set_process(false)
	var nodes = n.find_children("*", "CollisionObject2D", true, false)
	if n is CollisionObject2D:
		nodes.append(n)
	for c in nodes:
		c.collision_layer = 0
		c.collision_mask = 0
		if c is Area2D:
			c.set_deferred("monitoring", false)


func _make_enemy(r: Array):
	var e = arena.KINDS[r[2]].instantiate()
	e.hp = r[3]
	return e


func _update_enemy(n, r: Array):
	if r[3] < n.hp:                       # zásah -> bílé bliknutí
		n.body.modulate = n.FLASH
		n.create_tween().tween_property(n.body, "modulate", Color.WHITE, 0.15)
	n.hp = r[3]
	if r[2] == "turret" and r[4] is Vector2:
		n.gun.rotation = r[4].x
		n.core.modulate = Color(1, 1, 1).lerp(Color(4, 1.2, 0.3), r[4].y)
	elif n.has_method("apply_net_extra"):
		n.apply_net_extra(r[4])


func _make_bullet(r: Array):
	var b = BULLET_SCENE.instantiate()
	b.direction = r[2]
	b.hot = r[3]
	return b


func _make_pickup(r: Array):
	var p = PICKUP_SCENE.instantiate()
	p.type = r[2]
	return p


func _update_terminal(n, _r):
	var me = arena.local_player
	n.prompt.visible = me != null and not me.dead and me.global_position.distance_to(n.global_position) < 50.0
