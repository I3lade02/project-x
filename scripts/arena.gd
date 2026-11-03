extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemy.tscn")
const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const Pickup = preload("res://scripts/pickup.gd")
const Upgrades = preload("res://scripts/upgrades.gd")
const SPAWN_INTERVAL = 0.8
const DROP_CHANCE = 0.25

@onready var player = $Player
@onready var heat_bar = $HUD/HeatBar
@onready var status = $HUD/StatusLabel
@onready var score_label = $HUD/ScoreLabel
@onready var wave_label = $HUD/WaveLabel
@onready var buff_label = $HUD/BuffLabel
@onready var spawn_points = $SpawnPoints
@onready var upgrade_screen = $UpgradeScreen

var score := 0
var wave := 0
var to_spawn := 0
var alive := 0
var spawn_timer := 0.0
var game_over := false


func _ready():
	player.heat_changed.connect(_on_heat_changed)
	player.crashed.connect(func(): show_status("SYSTEM CRASH - REBOOTING..."))
	player.rebooted.connect(func(): show_status(""))
	player.died.connect(_on_player_died)
	upgrade_screen.chosen.connect(_on_upgrade_chosen)
	start_next_wave()


func _process(delta):
	update_buffs()
	if game_over or to_spawn <= 0:
		return
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_enemy()
		spawn_timer = SPAWN_INTERVAL


func _unhandled_input(event):
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func start_next_wave():
	if game_over:
		return
	wave += 1
	to_spawn = 3 + wave * 2
	spawn_timer = 1.5
	wave_label.text = "WAVE %d" % wave
	show_status("WAVE %d" % wave, 1.5)


func spawn_enemy():
	var e = ENEMY_SCENE.instantiate()
	e.global_position = spawn_points.get_children().pick_random().global_position
	e.speed = 110.0 + wave * 12.0
	e.died.connect(_on_enemy_died)
	add_child(e)
	to_spawn -= 1
	alive += 1


func spawn_pickup(pos):
	var p = PICKUP_SCENE.instantiate()
	# chladič padá 2x častěji
	p.type = [Pickup.Type.DOUBLE_JUMP, Pickup.Type.COOLANT, Pickup.Type.COOLANT, Pickup.Type.NITRO].pick_random()
	p.global_position = pos
	call_deferred("add_child", p)


func _on_enemy_died(pos):
	alive -= 1
	score += 10 * player.multiplier()
	update_score()
	if randf() < DROP_CHANCE:
		spawn_pickup(pos)
	if to_spawn == 0 and alive == 0 and not game_over:
		show_status("WAVE CLEAR!", 1.0)
		get_tree().create_timer(1.0).timeout.connect(_offer_upgrades)


func _offer_upgrades():
	if game_over:
		return
	var choices = Upgrades.pick(player.upgrades, 3)
	if choices.is_empty():
		start_next_wave()           # všechno už na maximu
		return
	upgrade_screen.open(choices, player.upgrades)


func _on_upgrade_chosen(id):
	player.apply_upgrade(id)
	start_next_wave()


func _on_player_died():
	game_over = true
	status.text = "GAME OVER\nScore: %d\nR = restart" % score


func _on_heat_changed(value):
	heat_bar.value = value
	heat_bar.modulate = Color.WHITE.lerp(Color.RED, value / 100.0)
	update_score()


func update_score():
	score_label.text = "SCORE: %d   x%d" % [score, player.multiplier()]


func update_buffs():
	var parts = []
	if player.double_jump_timer > 0:
		parts.append("DOUBLE JUMP %d s" % ceil(player.double_jump_timer))
	if player.nitro_timer > 0:
		parts.append("NITRO %d s" % ceil(player.nitro_timer))
	buff_label.text = "   ".join(PackedStringArray(parts))


# zobrazí text, volitelně ho po čase zase smaže
func show_status(text, time := 0.0):
	if game_over:
		return
	status.text = text
	if time > 0:
		get_tree().create_timer(time).timeout.connect(func():
			if status.text == text:
				status.text = "")
