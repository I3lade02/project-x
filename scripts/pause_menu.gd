extends CanvasLayer

const MAIN_MENU = "res://scenes/main_menu.tscn"
const Upgrades = preload("res://scripts/upgrades.gd")

@onready var root = $Root
@onready var continue_btn = $Root/Center/Panel/Margin/Menu/ContinueButton
@onready var restart_btn = $Root/Center/Panel/Margin/Menu/RestartButton
@onready var settings_btn = $Root/Center/Panel/Margin/Menu/SettingsButton
@onready var main_menu_btn = $Root/Center/Panel/Margin/Menu/MainMenuButton
@onready var desktop_btn = $Root/Center/Panel/Margin/Menu/DesktopButton
@onready var build_text = $Root/BuildPanel/Margin/VBox/BuildText
@onready var settings = $Settings


func _ready():
	root.hide()
	settings.hide()
	continue_btn.pressed.connect(resume)
	restart_btn.pressed.connect(_restart)
	settings_btn.pressed.connect(_open_settings)
	main_menu_btn.pressed.connect(_to_main_menu)
	desktop_btn.pressed.connect(func(): get_tree().quit())
	settings.closed.connect(func():
		root.show()
		settings_btn.grab_focus())


func _unhandled_input(event):
	if event.is_action_pressed("pause"):
		if settings.visible:
			settings.close()          # Esc v nastavení = zpět do pauzy
		elif root.visible:
			resume()
		elif not get_tree().paused:   # nepauzuj, když je otevřený výběr upgradu
			pause()
		get_viewport().set_input_as_handled()


func pause():
	get_tree().paused = true
	refresh_build()
	root.show()
	continue_btn.grab_focus()


func resume():
	get_tree().paused = false
	root.hide()


# přehled upgradů a corruptů hráče
func refresh_build():
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		build_text.text = ""
		return
	var txt = _build_section("UPGRADY", "#60ff80", player.upgrades, Upgrades.LIST)
	txt += "\n"
	txt += _build_section("CORRUPTY", "#ff5050", player.corrupts, Upgrades.CORRUPTS)
	build_text.text = txt


func _build_section(title, color, owned: Dictionary, data: Dictionary):
	var txt = "[b][color=%s]%s[/color][/b]\n" % [color, title]
	if owned.is_empty():
		return txt + "[color=gray]  zatím nic[/color]\n"
	for id in owned:
		var d = data[id]
		txt += "[color=%s]• %s  x%d[/color]\n" % [color, d["name"], owned[id]]
		txt += "[color=gray]   %s[/color]\n" % d["desc"]
	return txt


func _restart():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_settings():
	root.hide()
	settings.open()


func _to_main_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
