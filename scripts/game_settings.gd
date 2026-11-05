extends Node

const PATH = "user://settings.cfg"

# akce, které jde přebindovat : český název v menu
const REBINDABLE = {
	"move_up": "Nahoru",
	"move_down": "Dolů",
	"move_left": "Doleva",
	"move_right": "Doprava",
	"shoot": "Střelba",
	"dash": "Dash",
	"vent": "Vent",
	"overclock": "Overclock",
	"interact": "Terminál (interakce)",
}

var master_volume := 1.0
var glow := 0.5                 # intenzita záře (WorldEnvironment glow)


func _ready():
	load_settings()
	# každé nové prostředí (aréna, menu) dostane nastavenou záři
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n):
	if n is WorldEnvironment and n.environment:
		n.environment.glow_intensity = glow


func apply_glow():
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if n.environment:
			n.environment.glow_intensity = glow


func load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for action in REBINDABLE:
		var list = cfg.get_value("input", action, [])
		if list.size() > 0:
			InputMap.action_erase_events(action)
			for s in list:
				var ev = string_to_event(s)
				if ev:
					InputMap.action_add_event(action, ev)
	master_volume = cfg.get_value("audio", "master", 1.0)
	glow = cfg.get_value("video", "glow", 0.5)
	apply_volume()


func save_settings():
	var cfg = ConfigFile.new()
	for action in REBINDABLE:
		var list = []
		for ev in InputMap.action_get_events(action):
			var s = event_to_string(ev)
			if s != "":
				list.append(s)
		cfg.set_value("input", action, list)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("video", "glow", glow)
	cfg.save(PATH)


func set_binding(action, ev):
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)


func get_binding(action):
	var evs = InputMap.action_get_events(action)
	return evs[0] if evs.size() > 0 else null


func reset_defaults():
	InputMap.load_from_project_settings()
	master_volume = 1.0
	glow = 0.5
	apply_volume()
	apply_glow()
	save_settings()


func apply_volume():
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))


# --- převody pro uložení ---
func event_to_string(ev):
	if ev is InputEventKey:
		return "key:%d" % ev.physical_keycode
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


func string_to_event(s):
	var parts = s.split(":")
	if parts[0] == "key":
		var e = InputEventKey.new()
		e.physical_keycode = int(parts[1])
		return e
	if parts[0] == "mouse":
		var e = InputEventMouseButton.new()
		e.button_index = int(parts[1])
		return e
	return null


# text klávesy do menu
func event_label(ev):
	if ev == null:
		return "-"
	if ev is InputEventKey:
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode))
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Levé myši"
			MOUSE_BUTTON_RIGHT: return "Pravé myši"
			MOUSE_BUTTON_MIDDLE: return "Kolečko"
		return "Myš %d" % ev.button_index
	return ev.as_text()
