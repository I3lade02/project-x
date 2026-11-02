extends Control

const ARENA = "res://scenes/arena.tscn"

@onready var menu = $Center
@onready var start_btn = $Center/Menu/StartButton
@onready var settings_btn = $Center/Menu/SettingsButton
@onready var bonuses_btn = $Center/Menu/BonusesButton
@onready var quit_btn = $Center/Menu/QuitButton
@onready var bonuses = $BonusesPanel
@onready var bonuses_back = $BonusesPanel/Center/Panel/Margin/VBox/BackButton
@onready var settings = $Settings


func _ready():
	get_tree().paused = false
	start_btn.pressed.connect(func(): get_tree().change_scene_to_file(ARENA))
	settings_btn.pressed.connect(_open_settings)
	bonuses_btn.pressed.connect(_open_bonuses)
	quit_btn.pressed.connect(func(): get_tree().quit())
	bonuses_back.pressed.connect(_close_bonuses)
	settings.closed.connect(func():
		menu.show()
		settings_btn.grab_focus())
	start_btn.grab_focus()


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):     # Esc zavře podmenu
		if settings.visible:
			settings.close()
		elif bonuses.visible:
			_close_bonuses()


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
