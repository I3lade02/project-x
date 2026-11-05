extends Control

const ARENA = "res://scenes/arena_iso.tscn"   # 2D bokovka: res://scenes/arena.tscn
const Upgrades = preload("res://scripts/upgrades.gd")

@onready var menu = $Center
@onready var start_btn = $Center/Menu/StartButton
@onready var settings_btn = $Center/Menu/SettingsButton
@onready var bonuses_btn = $Center/Menu/BonusesButton
@onready var quit_btn = $Center/Menu/QuitButton
@onready var bonuses = $BonusesPanel
@onready var bonuses_back = $BonusesPanel/Center/Panel/Margin/VBox/BackButton
@onready var upgrades_text = $BonusesPanel/Center/Panel/Margin/VBox/Tabs/Upgrady
@onready var corrupts_text = $BonusesPanel/Center/Panel/Margin/VBox/Tabs/Corrupty
@onready var settings = $Settings
@onready var mode_panel = $ModePanel
@onready var solo_btn = $ModePanel/Center/Panel/Margin/VBox/SoloButton
@onready var coop_btn = $ModePanel/Center/Panel/Margin/VBox/CoopButton
@onready var coop_hint = $ModePanel/Center/Panel/Margin/VBox/CoopHint
@onready var mode_back = $ModePanel/Center/Panel/Margin/VBox/BackButton
@onready var lan_btn = $ModePanel/Center/Panel/Margin/VBox/LanButton
@onready var lan_panel = $LanPanel
@onready var lan_host_btn = $LanPanel/Center/Panel/Margin/VBox/HostButton
@onready var lan_host_info = $LanPanel/Center/Panel/Margin/VBox/HostInfo
@onready var lan_hosts = $LanPanel/Center/Panel/Margin/VBox/Hosts
@onready var lan_ip = $LanPanel/Center/Panel/Margin/VBox/ManualRow/IpEdit
@onready var lan_join_btn = $LanPanel/Center/Panel/Margin/VBox/ManualRow/JoinButton
@onready var lan_status = $LanPanel/Center/Panel/Margin/VBox/Status
@onready var lan_back = $LanPanel/Center/Panel/Margin/VBox/BackButton
@onready var notice = $Notice


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameSettings.coop = false
	Net.leave()
	notice.text = Net.last_message
	Net.last_message = ""
	lan_btn.pressed.connect(_open_lan)
	lan_host_btn.pressed.connect(_lan_host)
	lan_join_btn.pressed.connect(func(): _lan_join(lan_ip.text.strip_edges()))
	lan_ip.text_submitted.connect(func(t): _lan_join(t.strip_edges()))
	lan_back.pressed.connect(_close_lan)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.peer_joined.connect(func():
		lan_status.text = "Hráč 2 se připojil, spouštím hru…"
		Net.start_game.rpc())
	Net.connected.connect(func(): lan_status.text = "Připojeno, hostitel spouští hru…")
	Net.connection_failed.connect(func(): lan_status.text = "Nepodařilo se připojit. Zkontroluj IP a že jste ve stejné síti.")
	start_btn.pressed.connect(_open_modes)
	solo_btn.pressed.connect(_start.bind(false))
	coop_btn.pressed.connect(_start.bind(true))
	mode_back.pressed.connect(_close_modes)
	settings_btn.pressed.connect(_open_settings)
	bonuses_btn.pressed.connect(_open_bonuses)
	quit_btn.pressed.connect(func(): get_tree().quit())
	bonuses_back.pressed.connect(_close_bonuses)
	settings.closed.connect(func():
		menu.show()
		settings_btn.grab_focus())
	_fill_help()
	start_btn.grab_focus()


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):     # Esc zavře podmenu
		if settings.visible:
			settings.close()
		elif bonuses.visible:
			_close_bonuses()
		elif lan_panel.visible:
			_close_lan()
		elif mode_panel.visible:
			_close_modes()


# ============================================================
#  LAN
# ============================================================

func _open_lan():
	mode_panel.hide()
	lan_panel.show()
	lan_host_info.hide()
	lan_host_btn.disabled = false
	lan_status.text = ""
	Net.start_discovery()
	_refresh_hosts()
	lan_host_btn.grab_focus()


func _close_lan():
	Net.stop_discovery()
	Net.leave()
	lan_panel.hide()
	mode_panel.show()
	lan_btn.grab_focus()


func _lan_host():
	var err = Net.host()
	if err != OK:
		lan_status.text = "Hru se nepodařilo založit (port %d je obsazený?)." % Net.PORT
		return
	lan_host_btn.disabled = true
	var ips = Net.local_ips()
	lan_host_info.text = "Hra založena, čekám na druhého hráče…\nTvoje IP: %s" % (", ".join(PackedStringArray(ips)) if not ips.is_empty() else "?")
	lan_host_info.show()
	lan_status.text = ""


func _lan_join(ip: String):
	if ip == "":
		lan_status.text = "Zadej IP adresu hostitele."
		return
	if Net.join(ip) != OK:
		lan_status.text = "Neplatná adresa."
		return
	lan_status.text = "Připojuji se k %s…" % ip


func _refresh_hosts():
	for c in lan_hosts.get_children():
		c.queue_free()
	var own = Net.local_ips()
	var found = 0
	for ip in Net.hosts:
		if ip in own:
			continue                       # vlastní hru nezobrazovat
		var b = Button.new()
		b.text = "%s   ·   %s" % [Net.hosts[ip]["name"], ip]
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(_lan_join.bind(ip))
		lan_hosts.add_child(b)
		found += 1
	if found == 0:
		var l = Label.new()
		l.text = "Hledám hry… (hostitel musí kliknout na ZALOŽIT HRU)"
		l.modulate = Color(0.6, 0.65, 0.85)
		lan_hosts.add_child(l)


func _open_modes():
	menu.hide()
	coop_hint.text = "Hráč 2: %s pohyb  ·  %s střelba  ·  %s dash  ·  %s overclock  ·  %s vent  ·  %s terminál.\nP2 míří automaticky na nejbližšího nepřítele." % [
		"Šipky", _key("p2_shoot"), _key("p2_dash"), _key("p2_overclock"), _key("p2_vent"), _key("p2_interact")]
	mode_panel.show()
	solo_btn.grab_focus()


func _close_modes():
	mode_panel.hide()
	menu.show()
	start_btn.grab_focus()


func _key(action: String) -> String:
	return GameSettings.event_label(GameSettings.get_binding(action))


func _exit_tree():
	Net.stop_discovery()


func _start(coop: bool):
	GameSettings.coop = coop
	get_tree().change_scene_to_file(ARENA)


# naplní záložky Upgrady a Corrupty přímo z upgrades.gd
func _fill_help():
	var txt = "[color=gray]Po každé vlně si vybereš 1 ze 3 upgradů. Dají se stackovat do limitu.[/color]\n\n"
	for id in Upgrades.LIST:
		var u = Upgrades.LIST[id]
		txt += "[b][color=#60ff80]%s[/color][/b]  [color=gray](max %d)[/color]\n%s\n\n" % [u["name"], u["max"], u["desc"]]
	upgrades_text.text = txt

	txt = "[color=gray]Každý upgrade s sebou nese náhodný corrupt (postih). Nikdy nedostaneš corrupt, který by ruší právě vybraný upgrade.[/color]\n\n"
	for id in Upgrades.CORRUPTS:
		var c = Upgrades.CORRUPTS[id]
		txt += "[b][color=#ff5050]%s[/color][/b]  [color=gray](max %d)[/color]\n%s\n\n" % [c["name"], c["max"], c["desc"]]
	corrupts_text.text = txt


func _open_settings():
	menu.hide()
	settings.open()


func _open_bonuses():
	menu.hide()
	bonuses.show()
	bonuses_back.grab_focus()


func _close_bonuses():
	bonuses.hide()
	menu.show()
	bonuses_btn.grab_focus()
