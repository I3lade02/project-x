extends RefCounted
## Procedurální generátor sektoru. Vrací jen data (dlaždice, bloky, plotny, ventilátory, spawny),
## uzly z nich staví arena_iso.gd.
## Souřadnice = dlaždice izo mřížky: osa 0 ("i") jde na obrazovce doprava dolů, osa 1 ("j") doleva dolů.

const DIRS4 = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BLOCK_SIZES = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]
const SHAPES = ["corners", "cross", "pit", "ragged", "ragged", "plain", "corners"]
const BOSS_SHAPES = ["plain", "corners", "ragged"]


# origin = levý horní roh obdélníku v dlaždicích, size = velikost,
# entry = {} (první sektor) nebo {"axis", "sign", "lanes"} – strana, kudy přichází chodba
static func generate(origin: Vector2i, size: Vector2i, entry: Dictionary, boss: bool) -> Dictionary:
	var best := {}
	for attempt in 8:
		var lay = _try_generate(origin, size, entry, boss)
		if lay["walk"].size() >= size.x * size.y * 0.5:
			return lay
		if best.is_empty() or lay["walk"].size() > best["walk"].size():
			best = lay
	return best


static func _try_generate(origin: Vector2i, size: Vector2i, entry: Dictionary, boss: bool) -> Dictionary:
	# 1) tvar
	var walk := {}
	for i in size.x:
		for j in size.y:
			walk[origin + Vector2i(i, j)] = true
	var shapes = BOSS_SHAPES if boss else SHAPES
	for k in 1 + randi() % 2:
		_apply_shape(walk, origin, size, shapes.pick_random())
	if not boss:
		for k in randi() % 3:     # malé díry
			_set_rect(walk, origin + Vector2i(randi_range(3, size.x - 5), randi_range(3, size.y - 5)), Vector2i(2, 2), false)

	# 2) vstup + "páteř" ke středu (zaručí, že sektor jde projít)
	var pad := {}
	var start := Vector2.ZERO
	var center = origin + size / 2
	if entry.is_empty():
		for di in range(-2, 3):
			for dj in range(-2, 3):
				var c = center + Vector2i(di, dj)
				walk[c] = true
				pad[c] = true
		start = Vector2(center) + Vector2(0.5, 0.5)
	else:
		var ax: int = entry["axis"]
		var al: int = 1 - ax
		var sgn: int = entry["sign"]
		var lane0: int = entry["lanes"][0]
		var edge = origin[ax] + (size[ax] - 1 if sgn > 0 else 0)
		var depth_to_center = absi(center[ax] - edge)
		for depth in depth_to_center + 1:
			for lane in range(lane0 - 1, lane0 + 3):
				if lane < origin[al] or lane >= origin[al] + size[al]:
					continue
				var c = Vector2i.ZERO
				c[ax] = edge - sgn * depth
				c[al] = lane
				walk[c] = true
				if depth < 3:
					pad[c] = true
		start[ax] = edge - sgn * 1 + 0.5
		start[al] = lane0 + 1.0
	var start_cell = Vector2i(floori(start.x), floori(start.y))
	walk = _flood(walk, {}, start_cell)      # jen to, co je dosažitelné
	var cells = walk.keys()

	# 3) bloky (kryt) – nikdy nesmí odříznout část sektoru
	var occupied := {}
	var blocks := []
	var target = randi_range(2, 4) if boss else randi_range(5, 10)
	for attempt in 90:
		if blocks.size() >= target:
			break
		var bs: Vector2i = BLOCK_SIZES.pick_random()
		var c: Vector2i = cells.pick_random()
		var fp = _footprint(c, bs)
		if not _area_ok(fp, walk, occupied, pad, 1):
			continue
		for f in fp:
			occupied[f] = true
		if _flood(walk, occupied, start_cell).size() != walk.size() - occupied.size():
			for f in fp:
				occupied.erase(f)
			continue
		blocks.append({"center": Vector2(c) + Vector2(bs) / 2.0, "size": Vector2(bs), "height": randf_range(28.0, 90.0)})

	# 4) žhavé plotny a ventilátory
	var hazard := {}
	var plates := []
	var fans := []
	var n_plates = randi_range(0, 2) if boss else randi_range(0, 3)
	var n_fans = randi_range(1, 2) if boss else randi_range(0, 2)
	for attempt in 60:
		if plates.size() >= n_plates:
			break
		var c: Vector2i = cells.pick_random()
		var fp = _footprint(c, Vector2i(3, 2))
		if _area_ok(fp, walk, occupied, pad, 0) and _area_ok(fp, walk, hazard, {}, 1):
			for f in fp:
				hazard[f] = true
			plates.append(Vector2(c) + Vector2(1.5, 1.0))
	for attempt in 60:
		if fans.size() >= n_fans:
			break
		var c: Vector2i = cells.pick_random()
		var fp = _footprint(c, Vector2i(2, 2))
		if _area_ok(fp, walk, occupied, pad, 1) and _area_ok(fp, walk, hazard, {}, 1):
			for f in fp:
				hazard[f] = true
			fans.append(Vector2(c) + Vector2(1.0, 1.0))

	# 5) volná místa a spawny nepřátel (u okraje, daleko od hráče)
	var free := []
	for c in walk:
		if not occupied.has(c) and not hazard.has(c):
			free.append(c)
	var cands := []
	for c in free:
		if Vector2(c).distance_to(start) >= 6.0 and _near_edge(c, walk):
			cands.append(c)
	cands.shuffle()
	var spawns := []
	for c in cands:
		if spawns.size() >= 5:
			break
		var ok := true
		for s in spawns:
			if Vector2(s).distance_to(Vector2(c)) < 4.0:
				ok = false
		if ok:
			spawns.append(c)
	if spawns.size() < 2:
		var far = free.duplicate()
		far.sort_custom(func(a, b): return Vector2(a).distance_to(start) > Vector2(b).distance_to(start))
		for k in mini(3, far.size()):
			spawns.append(far[k])

	return {
		"origin": origin, "size": size, "entry": entry, "walk": walk,
		"blocks": blocks, "plates": plates, "fans": fans,
		"spawns": spawns, "free": free, "start": start,
	}


# najde místo pro chodbu na dané straně sektoru (axis 0/1, sign ±1)
static func find_exit(lay: Dictionary, ax: int, sgn: int, length: int) -> Dictionary:
	var al = 1 - ax
	var ext := {}                 # pruh -> nejkrajnější dlaždice v tomto směru
	for c in lay["walk"]:
		var lane = c[al]
		if not ext.has(lane) or (c[ax] - ext[lane]) * sgn > 0:
			ext[lane] = c[ax]
	var mid = lay["origin"][al] + lay["size"][al] / 2.0
	var cands := []
	for a in ext:
		if not ext.has(a + 1) or absi(ext[a] - ext[a + 1]) > 1:
			continue
		var t0 = Vector2i.ZERO
		t0[ax] = ext[a]
		t0[al] = a
		var t1 = Vector2i.ZERO
		t1[ax] = ext[a + 1]
		t1[al] = a + 1
		if not lay["free"].has(t0) or not lay["free"].has(t1):
			continue
		cands.append([absf(a + 0.5 - mid) + randf() * 3.0, a])
	if cands.is_empty():
		return {}
	cands.sort_custom(func(p, q): return p[0] < q[0])
	var a: int = cands[0][1]
	var edge = lay["origin"][ax] + (lay["size"][ax] - 1 if sgn > 0 else 0)
	var end = (maxi(ext[a], ext[a + 1]) if sgn > 0 else mini(ext[a], ext[a + 1])) + sgn * length
	end = maxi(end, edge + 2) if sgn > 0 else mini(end, edge - 2)   # nový sektor nesmí překrýt starý
	var tiles := []
	for lane in [a, a + 1]:
		var v = ext[lane] + sgn
		while (end - v) * sgn >= 0:
			var t = Vector2i.ZERO
			t[ax] = v
			t[al] = lane
			tiles.append(t)
			v += sgn
	return {"lanes": [a, a + 1], "tiles": tiles, "end": end, "axis": ax, "sign": sgn}


# --- pomocné ---
static func _apply_shape(walk: Dictionary, origin: Vector2i, size: Vector2i, shape: String):
	match shape:
		"corners":
			for k in 4:
				if randf() < 0.6:
					var cs = Vector2i(randi_range(2, maxi(2, floori(size.x / 3.0))), randi_range(2, maxi(2, floori(size.y / 3.0))))
					_cut_corner(walk, origin, size, k, cs)
		"cross":
			for k in 4:
				_cut_corner(walk, origin, size, k, Vector2i(floori(size.x / 3.0), floori(size.y / 3.0)))
		"pit":
			var ps = Vector2i(randi_range(2, 4), randi_range(2, 4))
			_set_rect(walk, origin + size / 2 - ps / 2, ps, false)
		"ragged":
			for p in 2:
				var rem := []
				for c in walk:
					if _is_border(c, walk) and randf() < 0.35:
						rem.append(c)
				for c in rem:
					walk.erase(c)
			var lone := []
			for c in walk:
				var cnt := 0
				for d in DIRS4:
					if walk.has(c + d):
						cnt += 1
				if cnt < 2:
					lone.append(c)
			for c in lone:
				walk.erase(c)


static func _cut_corner(walk: Dictionary, origin: Vector2i, size: Vector2i, k: int, cs: Vector2i):
	var x = origin.x if k % 2 == 0 else origin.x + size.x - cs.x
	var y = origin.y if k < 2 else origin.y + size.y - cs.y
	_set_rect(walk, Vector2i(x, y), cs, false)


static func _set_rect(walk: Dictionary, pos: Vector2i, sz: Vector2i, value: bool):
	for i in sz.x:
		for j in sz.y:
			var c = pos + Vector2i(i, j)
			if value:
				walk[c] = true
			else:
				walk.erase(c)


static func _footprint(c: Vector2i, sz: Vector2i) -> Array:
	var out := []
	for i in sz.x:
		for j in sz.y:
			out.append(c + Vector2i(i, j))
	return out


# všechny dlaždice pochozí, mimo pad a s mezerou `gap` od obsazených
static func _area_ok(fp: Array, walk: Dictionary, occupied: Dictionary, pad: Dictionary, gap: int) -> bool:
	for f in fp:
		if not walk.has(f) or pad.has(f):
			return false
		for dx in range(-gap, gap + 1):
			for dy in range(-gap, gap + 1):
				if occupied.has(f + Vector2i(dx, dy)):
					return false
	return true


static func _is_border(c: Vector2i, walk: Dictionary) -> bool:
	for d in DIRS4:
		if not walk.has(c + d):
			return true
	return false


static func _near_edge(c: Vector2i, walk: Dictionary) -> bool:
	for d in DIRS4:
		if not walk.has(c + d) or not walk.has(c + d * 2):
			return true
	return false


static func _flood(walk: Dictionary, blocked: Dictionary, start: Vector2i) -> Dictionary:
	var out := {}
	if not walk.has(start) or blocked.has(start):
		return out
	var stack := [start]
	out[start] = true
	while not stack.is_empty():
		var c = stack.pop_back()
		for d in DIRS4:
			var n = c + d
			if walk.has(n) and not blocked.has(n) and not out.has(n):
				out[n] = true
				stack.append(n)
	return out
