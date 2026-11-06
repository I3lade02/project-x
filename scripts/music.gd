extends Node
## Adaptivní hudba (synthwave). Autoload „Music“.
## Boj = 6 vrstev v jedné synchronizované smyčce, boss = 5 vrstev, menu = jedna smyčka.
## Stav si bere sama: když má aktuální scéna metodu music_state(), hraje herní hudbu, jinak menu.
##   overclock  -> hudba se „přetaktuje“ (zrychlí)
##   crash      -> hudba se přiškrtí (ztlumené výšky, zpomalení)
##   game over  -> „tape stop“ (dojede jako kazeťák)

const COMBAT = ["pad", "bass", "drums", "arp", "lead", "heat"]
const BOSS = ["pad", "bass", "drums", "arp", "lead"]
const BASE_DB = -7.0               # hudba hraje pod zvukovými efekty
const SILENT = 0.0001
const FADE = 1.6                   # rychlost změn hlasitosti vrstev (za s)

var bus := -1
var lowpass: AudioEffectLowPassFilter
var menu_player: AudioStreamPlayer
var combat_player: AudioStreamPlayer
var boss_player: AudioStreamPlayer
var combat_stream: AudioStreamSynchronized
var boss_stream: AudioStreamSynchronized

var mode := ""                     # "menu" / "game"
var combat_gain := {}              # aktuální lineární hlasitost vrstev
var boss_gain := {}
var menu_level := 0.0
var combat_level := 0.0            # celková hlasitost boje (při bossovi jde dolů)
var boss_level := 0.0
var pitch := 1.0
var cutoff := 20000.0
var fight_hold := 0.0              # boj „doznívá“ chvíli po posledním nepříteli
var lead_on := false
var heat_level := 0.0
var tape := 0.0                    # 0 = normál, 1 = úplně zastaveno (game over)


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	combat_stream = _make_sync("combat", COMBAT)
	boss_stream = _make_sync("boss", BOSS)
	combat_player = _make_player(combat_stream)
	boss_player = _make_player(boss_stream)
	var menu_stream = load("res://music/menu.ogg")
	menu_stream.loop = true
	menu_player = _make_player(menu_stream)
	for n in COMBAT:
		combat_gain[n] = SILENT
	for n in BOSS:
		boss_gain[n] = SILENT
	GameSettings.apply_volume()


func _setup_bus():
	bus = AudioServer.get_bus_index("Music")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Music")
		AudioServer.set_bus_send(bus, "Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = cutoff
	AudioServer.add_bus_effect(bus, lowpass)


func _make_sync(prefix: String, names: Array) -> AudioStreamSynchronized:
	var s = AudioStreamSynchronized.new()
	s.stream_count = names.size()
	for i in names.size():
		var st = load("res://music/%s_%s.ogg" % [prefix, names[i]])
		st.loop = true
		s.set_sync_stream(i, st)
		s.set_sync_stream_volume(i, linear_to_db(SILENT))
	return s


func _make_player(stream) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Music"
	p.volume_db = linear_to_db(SILENT)
	add_child(p)
	return p


# hlasitost hudby z nastavení (0..1)
func set_volume(v: float):
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)) + BASE_DB)
		AudioServer.set_bus_mute(bus, v <= 0.001)


func _process(delta):
	var scene = get_tree().current_scene
	var st: Dictionary = scene.music_state() if scene and scene.has_method("music_state") else {"mode": "menu"}
	if st["mode"] != mode:
		_switch(st["mode"])
	if mode == "menu":
		_menu(delta)
	else:
		_game(delta, st)
	# společné: rychlost (přetaktování / crash / tape stop) a filtr
	combat_player.pitch_scale = maxf(pitch, 0.05)
	boss_player.pitch_scale = maxf(pitch, 0.05)
	lowpass.cutoff_hz = cutoff


func _switch(new_mode: String):
	mode = new_mode
	tape = 0.0
	if mode == "menu":
		combat_player.stop()
		boss_player.stop()
		combat_level = 0.0
		boss_level = 0.0
		pitch = 1.0
		if not menu_player.playing:
			menu_player.play()
	else:
		for n in COMBAT:
			combat_gain[n] = SILENT
		combat_level = 1.0
		combat_player.play()
		lead_on = false


func _menu(delta):
	menu_level = move_toward(menu_level, 1.0, delta * 0.8)
	menu_player.volume_db = linear_to_db(maxf(menu_level, SILENT))
	cutoff = lerpf(cutoff, 20000.0, 1.0 - exp(-4.0 * delta))


func _game(delta, st: Dictionary):
	# menu dozní
	if menu_player.playing:
		menu_level = move_toward(menu_level, 0.0, delta * 1.2)
		menu_player.volume_db = linear_to_db(maxf(menu_level, SILENT))
		if menu_level <= 0.0:
			menu_player.stop()

	# --- game over: dojede jako kazeťák
	if st.get("game_over", false):
		tape = move_toward(tape, 1.0, delta / 2.2)
		pitch = lerpf(1.0, 0.25, tape * tape)
		combat_player.volume_db = linear_to_db(maxf(combat_level * (1.0 - tape), SILENT))
		boss_player.volume_db = linear_to_db(maxf(boss_level * (1.0 - tape), SILENT))
		if tape >= 1.0:
			combat_player.stop()
			boss_player.stop()
		return
	if tape > 0.0:                           # restart po game over
		tape = 0.0
		pitch = 1.0
		_switch("game")

	# --- cíle vrstev
	var fight = st.get("fight", false)
	fight_hold = 3.0 if fight else maxf(fight_hold - delta, 0.0)
	var in_fight = fight_hold > 0.0
	var inten: float = st.get("intensity", 0.0)
	if inten >= 0.6:
		lead_on = true
	elif inten < 0.3 or not in_fight:
		lead_on = false
	heat_level = move_toward(heat_level, clampf((st.get("heat", 0.0) - 0.55) / 0.3, 0.0, 1.0), delta * 0.8)
	var tgt = {
		"pad": 1.0,
		"bass": 1.0 if in_fight else 0.45,
		"drums": 1.0 if in_fight else 0.0,
		"arp": 1.0 if in_fight else 0.4,
		"lead": 1.0 if lead_on else 0.0,
		"heat": heat_level if in_fight else 0.0,
	}
	for n in COMBAT:
		combat_gain[n] = move_toward(combat_gain[n], tgt[n], delta * FADE)
		combat_stream.set_sync_stream_volume(COMBAT.find(n), linear_to_db(maxf(combat_gain[n], SILENT)))

	# --- boss: vlastní skladba, vrstvy podle fáze
	var ph: int = st.get("boss_phase", 0)
	if ph > 0 and not boss_player.playing:
		for n in BOSS:
			boss_gain[n] = SILENT
		boss_player.play()
	var btgt = {"pad": 1.0, "bass": 1.0, "drums": 1.0, "arp": 1.0 if ph >= 2 else 0.0, "lead": 1.0 if ph >= 3 else 0.0}
	for n in BOSS:
		boss_gain[n] = move_toward(boss_gain[n], btgt[n] if ph > 0 else boss_gain[n], delta * FADE)
		boss_stream.set_sync_stream_volume(BOSS.find(n), linear_to_db(maxf(boss_gain[n], SILENT)))
	boss_level = move_toward(boss_level, 1.0 if ph > 0 else 0.0, delta * (0.9 if ph > 0 else 0.5))
	combat_level = move_toward(combat_level, 0.0 if ph > 0 else 1.0, delta * 0.9)
	if boss_level <= 0.0 and boss_player.playing:
		boss_player.stop()
	combat_player.volume_db = linear_to_db(maxf(combat_level, SILENT))
	boss_player.volume_db = linear_to_db(maxf(boss_level, SILENT))

	# --- přetaktování zrychlí, crash přiškrtí, pauza ztlumí
	var target_pitch = 1.0 + 0.015 * st.get("overclock", 0)
	var target_cut = 20000.0
	if st.get("crash", false):
		target_pitch = 0.92
		target_cut = 700.0
	elif get_tree().paused:
		target_cut = 1400.0
	pitch = lerpf(pitch, target_pitch, 1.0 - exp(-3.0 * delta))
	cutoff = exp(lerpf(log(cutoff), log(target_cut), 1.0 - exp(-5.0 * delta)))
