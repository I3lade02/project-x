extends Control
## HUD jednoho hráče: teplota, overclock, dash, vent, bonusy a čipy.

const OC_NAMES = ["-", "I", "II", "III"]

var player

@onready var heat_bar = $HeatBar
@onready var redline_mark = $HeatBar/RedlineMark
@onready var heat_label = $HeatLabel
@onready var chips_label = $Chips
@onready var heat_info = $HeatInfo
@onready var buffs = $Buffs


func _process(_delta):
	if player == null or not is_instance_valid(player):
		return
	heat_label.text = "P%d  HEAT" % (player.player_index + 1) if GameSettings.two_players() else "HEAT"
	heat_bar.value = player.heat
	heat_bar.modulate = Color.WHITE.lerp(Color.RED, player.heat / 100.0)
	redline_mark.position.x = heat_bar.size.x * player.redline_start / 100.0 - 1.0
	chips_label.text = "ČIPY  %d" % player.chips

	if player.dead:
		heat_info.text = "OFFLINE  ·  návrat v dalším sektoru"
		heat_info.modulate = Color(1.6, 0.45, 0.4)
		buffs.text = ""
		return

	# úroveň overclocku, dash, vent, chlazení, REDLINE
	var vent_key = GameSettings.event_label(GameSettings.get_binding(player.act("vent")))
	var txt = "OC %s   DASH %d/%d" % [OC_NAMES[player.oc_level], player.dash_charges, player.max_dashes()]
	if player.vent_cd > 0:
		txt += "   VENT %.1f s" % player.vent_cd
	elif player.heat >= player.VENT_MIN_HEAT:
		txt += "   VENT PŘIPRAVEN [%s]" % vent_key
	else:
		txt += "   VENT (min. 40 %)"
	if player.in_fan_t > 0:
		txt += "   CHLAZENÍ"
	if player.in_redline():
		txt += "   >> REDLINE <<"
		var blink = int(Time.get_ticks_msec() / 120) % 2 == 0
		heat_info.modulate = Color(3, 0.5, 0.3) if blink else Color(1.5, 0.8, 0.6)
	elif player.in_fan_t > 0:
		heat_info.modulate = Color(0.8, 2.0, 2.4)
	else:
		heat_info.modulate = Color(0.7, 1.2, 1.4)
	heat_info.text = txt

	var parts = []
	if player.double_dash_timer > 0:
		parts.append("DOUBLE DASH %d s" % ceil(player.double_dash_timer))
	if player.nitro_timer > 0:
		parts.append("NITRO %d s" % ceil(player.nitro_timer))
	if player.shield > 0:
		parts.append("ŠTÍT x%d" % player.shield)
	if player.fuse > 0:
		parts.append("POJISTKA")
	buffs.text = "   ".join(PackedStringArray(parts))
