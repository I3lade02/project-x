extends Control

signal closed

@onready var grid = $Center/Panel/Margin/VBox/Bindings
@onready var volume_slider = $Center/Panel/Margin/VBox/VolumeRow/VolumeSlider
@onready var glow_slider = $Center/Panel/Margin/VBox/GlowRow/GlowSlider
@onready var reset_btn = $Center/Panel/Margin/VBox/ButtonsRow/ResetButton
@onready var back_btn = $Center/Panel/Margin/VBox/ButtonsRow/BackButton

var waiting_action := ""
var buttons := {}


func _ready():
	for action in GameSettings.REBINDABLE:
		var l = Label.new()
		l.text = GameSettings.REBINDABLE[action]
		grid.add_child(l)
		var b = Button.new()
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(_on_bind_pressed.bind(action))
		grid.add_child(b)
		buttons[action] = b
	volume_slider.value_changed.connect(_on_volume_changed)
	glow_slider.value_changed.connect(_on_glow_changed)
	reset_btn.pressed.connect(_on_reset)
	back_btn.pressed.connect(close)
	refresh()


func open():
	# skrytý panel nemusí mít po změně velikosti okna správný rozměr (export na Macu) -> roztáhnout znovu
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show()
	refresh()
	volume_slider.value = GameSettings.master_volume
	glow_slider.value = GameSettings.glow
	back_btn.grab_focus()


func close():
	waiting_action = ""
	GameSettings.save_settings()
	hide()
	closed.emit()


func refresh():
	for action in buttons:
		buttons[action].text = GameSettings.event_label(GameSettings.get_binding(action))


func _on_bind_pressed(action):
	waiting_action = action
	buttons[action].text = "Stiskni klávesu..."


# zachytí novou klávesu
func _input(event):
	if waiting_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:     # Esc = zrušit
			var e = InputEventKey.new()
			e.physical_keycode = event.physical_keycode
			GameSettings.set_binding(waiting_action, e)
		_finish_binding()
	elif event is InputEventMouseButton and event.pressed:
		var e = InputEventMouseButton.new()
		e.button_index = event.button_index
		GameSettings.set_binding(waiting_action, e)
		_finish_binding()


func _finish_binding():
	waiting_action = ""
	refresh()
	GameSettings.save_settings()
	get_viewport().set_input_as_handled()


func _on_glow_changed(value):
	GameSettings.glow = value
	GameSettings.apply_glow()


func _on_volume_changed(value):
	GameSettings.master_volume = value
	GameSettings.apply_volume()


func _on_reset():
	GameSettings.reset_defaults()
	volume_slider.value = GameSettings.master_volume
	glow_slider.value = GameSettings.glow
	refresh()
