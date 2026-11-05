extends Node
## Síťová hra po LAN.
## Hostitel = server (simuluje celou hru), druhý hráč = klient (posílá vstupy, zobrazuje stav).
## Hry v síti se hledají automaticky (UDP broadcast), záloha je ruční zadání IP.

signal hosts_changed            # (klient) změnil se seznam nalezených her
signal connected                # (klient) připojeno k hostiteli
signal connection_failed        # (klient) připojení selhalo
signal peer_joined              # (host) připojil se hráč 2
signal peer_left                # (host) hráč 2 se odpojil
signal server_left              # (klient) hostitel ukončil hru

const PORT = 24680
const DISCOVERY_PORT = 24681
const MAGIC = "OVERCLOCK1"
const GAME_SCENE = "res://scenes/arena_iso.tscn"
const MENU_SCENE = "res://scenes/main_menu.tscn"

var role := ""                  # "", "host", "client"
var hosts := {}                 # ip -> {"name": .., "seen": ms}
var last_message := ""          # zpráva pro hlavní menu (např. "spojení ukončeno")
var _bcast: PacketPeerUDP = null
var _listen: PacketPeerUDP = null
var _bcast_t := 0.0


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(func(_id):
		if role == "host":
			peer_joined.emit())
	multiplayer.peer_disconnected.connect(func(_id):
		if role == "host":
			peer_left.emit())
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func():
		_reset()
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		_reset()
		server_left.emit())


func is_online() -> bool:
	return role != ""

func is_host() -> bool:
	return role == "host"

func is_client() -> bool:
	return role == "client"


# --- založení / připojení / odpojení ---
func host() -> int:
	leave()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = "host"
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast_t = 0.0
	return OK


func join(ip: String) -> int:
	leave()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = "client"
	return OK


func leave():
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()


func _reset():
	role = ""
	if _bcast:
		_bcast.close()
		_bcast = null


# --- spuštění hry u obou ---
@rpc("authority", "call_local", "reliable")
func start_game():
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


# --- hledání her v síti ---
func start_discovery():
	stop_discovery()
	hosts.clear()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null


func stop_discovery():
	if _listen:
		_listen.close()
		_listen = null


func local_ips() -> Array:
	var out = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func host_name() -> String:
	var n = OS.get_environment("USER")
	if n == "":
		n = OS.get_environment("USERNAME")
	return n if n != "" else "Hráč"


func _process(delta):
	# hostitel ohlašuje hru, dokud se nikdo nepřipojí
	if _bcast and role == "host" and multiplayer.get_peers().is_empty():
		_bcast_t -= delta
		if _bcast_t <= 0:
			_bcast_t = 1.0
			var msg = ("%s|%s" % [MAGIC, host_name()]).to_utf8_buffer()
			var targets = ["255.255.255.255"]
			for ip in local_ips():
				var p = ip.split(".")
				targets.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
			for t in targets:
				_bcast.set_dest_address(t, DISCOVERY_PORT)
				_bcast.put_packet(msg)
	# klient poslouchá ohlášení
	if _listen:
		var changed = false
		while _listen.get_available_packet_count() > 0:
			var data = _listen.get_packet().get_string_from_utf8()
			var ip = _listen.get_packet_ip()
			var parts = data.split("|")
			if parts.size() >= 2 and parts[0] == MAGIC:
				if not hosts.has(ip):
					changed = true
				hosts[ip] = {"name": parts[1], "seen": Time.get_ticks_msec()}
		var now = Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - hosts[ip]["seen"] > 4000:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


# --- efekty z hostitele (zvuky, třes, částice) ---
@rpc("authority", "call_remote", "unreliable_ordered")
func fx_play(sound_name: String, volume_db: float, pitch_var: float):
	Juice.play_local(sound_name, volume_db, pitch_var)

@rpc("authority", "call_remote", "unreliable_ordered")
func fx_shake(amount: float):
	Juice.shake_local(amount)

@rpc("authority", "call_remote", "unreliable_ordered")
func fx_burst(pos: Vector2, color: Color, amount: int):
	Juice.burst_local(pos, color, amount)

@rpc("authority", "call_remote", "unreliable_ordered")
func fx_hitstop(duration: float):
	Juice.hitstop_local(duration)

@rpc("authority", "call_remote", "unreliable_ordered")
func fx_ring(player_index: int, radius: float, color: Color):
	for p in get_tree().get_nodes_in_group("player"):
		if p.player_index == player_index:
			p.show_ring_local(radius, color)
