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


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	start_btn.pressed.connect(func(): get_tree().change_scene_to_file(ARENA))
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
