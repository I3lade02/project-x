extends CanvasLayer

const MAIN_MENU = "res://scenes/main_menu.tscn"

@onready var root = $Root
@onready var continue_btn = $Root/Center/Panel/Margin/Menu/ContinueButton
@onready var restart_btn = $Root/Center/Panel/Margin/Menu/RestartButton
@onready var settings_btn = $Root/Center/Panel/Margin/Menu/SettingsButton
@onready var main_menu_btn = $Root/Center/Panel/Margin/Menu/MainMenuButton
@onready var desktop_btn = $Root/Center/Panel/Margin/Menu/DesktopButton
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
		else:
			pause()
		get_viewport().set_input_as_handled()


func pause():
	get_tree().paused = true
	root.show()
	continue_btn.grab_focus()


func resume():
	get_tree().paused = false
	root.hide()


func _restart():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_settings():
	root.hide()
	settings.open()


func _to_main_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
