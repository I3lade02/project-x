extends "res://scripts/enemy_iso.gd"
## Tank – pomalý a odolný. Když umře, vybuchne (zraní bugy i ohřeje hráče).

const BLAST_RADIUS = 130.0
const BLAST_DAMAGE = 4
const BLAST_HEAT = 20.0

@onready var core = $Visual/Body/Core


func behave(_delta):
	# pod 35 % HP bliká – varování před výbuchem
	if hp <= max_hp * 0.35:
		core.modulate = Color(4, 0.5, 0.3) if int(t * 8) % 2 == 0 else Color.WHITE


func on_death():
	Juice.play("blast", -2.0)
	Juice.shake(0.6)
	Juice.burst(global_position + Vector2(0, -16), Color(3, 1.2, 0.3), 30)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and iso_dist(e.global_position, global_position) < BLAST_RADIUS:
			e.take_damage(BLAST_DAMAGE)
	if player and not player.dead and iso_dist(player.global_position, global_position) < BLAST_RADIUS:
		player.hit(BLAST_HEAT, global_position)
	# rozpínající se elipsa
	var ring = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in 32:
		var a = i * TAU / 32.0
		pts.append(Vector2(cos(a) * BLAST_RADIUS, sin(a) * BLAST_RADIUS * 0.5))
	ring.polygon = pts
	ring.color = Color(3, 1.2, 0.3, 0.5)
	ring.global_position = global_position
	ring.scale = Vector2(0.2, 0.2)
	get_tree().current_scene.add_child(ring)
	var tw = ring.create_tween()
	tw.tween_property(ring, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.4)
	tw.tween_callback(ring.queue_free)
