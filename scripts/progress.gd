extends Node
## Trvalý postup mezi hrami: vzácná měna JÁDRA a skill tree.
## Ukládá se do user://progress.cfg (každý počítač má vlastní).

signal changed

const PATH = "user://progress.cfg"
const CORE_DROP_CHANCE = 0.02     # šance na jádro z běžného nepřítele
const BOSS_CORES = 3              # jádra z bosse

# větve stromu
const BRANCHES = {
	"cool": {"name": "CHLAZENÍ", "color": Color(0.4, 1.6, 2.0)},
	"power": {"name": "VÝKON", "color": Color(2.0, 0.9, 0.35)},
	"system": {"name": "SYSTÉM", "color": Color(0.6, 1.8, 0.8)},
}

# uzly: větev, pozice ve větvi (sloupec 0–1, řádek 0–2), předchůdce, ceny jednotlivých úrovní
const TREE = {
	"c1": {"branch": "cool", "pos": Vector2(0.5, 0), "req": "", "name": "Lepší pasta", "desc": "Chlazení +8 % za úroveň.", "cost": [1, 2, 3]},
	"c2": {"branch": "cool", "pos": Vector2(0, 1), "req": "c1", "name": "Rychlý odvod", "desc": "Chlazení začne o 0,1 s dřív za úroveň.", "cost": [2, 3]},
	"c3": {"branch": "cool", "pos": Vector2(1, 1), "req": "c1", "name": "Odolný plášť", "desc": "Dotyk nepřítele hřeje o 10 % méně za úroveň.", "cost": [2, 3]},
	"c4": {"branch": "cool", "pos": Vector2(0, 2), "req": "c2", "name": "Záložní pojistka", "desc": "Každý run začneš s pojistkou proti crashi.", "cost": [5]},
	"c5": {"branch": "cool", "pos": Vector2(1, 2), "req": "c3", "name": "Kryo jádro", "desc": "Cooldown ventu −0,5 s za úroveň.", "cost": [3, 4]},
	"p1": {"branch": "power", "pos": Vector2(0.5, 0), "req": "", "name": "Rychlá spoušť", "desc": "Rychlost palby +6 % za úroveň.", "cost": [1, 2, 3]},
	"p2": {"branch": "power", "pos": Vector2(0, 1), "req": "p1", "name": "Průrazné jádro", "desc": "Střely projdou o 1 nepřítele víc.", "cost": [4]},
	"p3": {"branch": "power", "pos": Vector2(1, 1), "req": "p1", "name": "Trénink overclocku", "desc": "Overclock hřeje o 8 % méně za úroveň.", "cost": [2, 3]},
	"p4": {"branch": "power", "pos": Vector2(1, 2), "req": "p3", "name": "Redline expert", "desc": "REDLINE začíná už od 75 %.", "cost": [4]},
	"p5": {"branch": "power", "pos": Vector2(0, 2), "req": "p2", "name": "Těžké náboje", "desc": "Poškození +1.", "cost": [8]},
	"s1": {"branch": "system", "pos": Vector2(0.5, 0), "req": "", "name": "Startovní kapitál", "desc": "Začneš s +5 čipy za úroveň.", "cost": [1, 2, 3]},
	"s2": {"branch": "system", "pos": Vector2(0, 1), "req": "s1", "name": "Silný magnet", "desc": "Čipy přitahuješ z o 25 % větší dálky za úroveň.", "cost": [2, 2]},
	"s3": {"branch": "system", "pos": Vector2(1, 1), "req": "s1", "name": "Dash modul", "desc": "+1 dash navíc.", "cost": [5]},
	"s4": {"branch": "system", "pos": Vector2(0, 2), "req": "s2", "name": "Startovní štít", "desc": "Začneš s 1 tepelným štítem za úroveň.", "cost": [3, 4]},
	"s5": {"branch": "system", "pos": Vector2(1, 2), "req": "s3", "name": "Reroll zdarma", "desc": "První reroll karet po každé vlně je zdarma.", "cost": [6]},
}

var cores := 0
var levels := {}                  # id uzlu -> úroveň


func _ready():
	load_progress()


# --- strom ---
func level(id: String) -> int:
	return levels.get(id, 0)


func max_level(id: String) -> int:
	return TREE[id]["cost"].size()


func is_unlocked(id: String) -> bool:
	var req = TREE[id]["req"]
	return req == "" or level(req) > 0


# cena další úrovně (-1 = už je na maximu)
func next_cost(id: String) -> int:
	var lv = level(id)
	return -1 if lv >= max_level(id) else TREE[id]["cost"][lv]


func can_buy(id: String) -> bool:
	var c = next_cost(id)
	return c > 0 and is_unlocked(id) and cores >= c


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	cores -= next_cost(id)
	levels[id] = level(id) + 1
	save_progress()
	changed.emit()
	return true


# kolik jader je ve stromu utraceno
func spent() -> int:
	var total = 0
	for id in levels:
		for i in levels[id]:
			total += TREE[id]["cost"][i]
	return total


# vrátí všechna utracená jádra
func reset_tree():
	cores += spent()
	levels = {}
	save_progress()
	changed.emit()


# --- měna ---
func add_cores(n: int):
	if n <= 0:
		return
	cores += n
	save_progress()
	changed.emit()


# bonus jader na konci runu podle dosaženého sektoru
func run_bonus(sector: int) -> int:
	return floori((sector - 1) / 2.0)


# --- uložení ---
func save_progress():
	var cfg = ConfigFile.new()
	cfg.set_value("meta", "cores", cores)
	cfg.set_value("meta", "levels", levels)
	cfg.save(PATH)


func load_progress():
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	cores = cfg.get_value("meta", "cores", 0)
	levels = cfg.get_value("meta", "levels", {})


# --- použití ve hře ---
# aplikuje strom na hráče na začátku runu (lv = vlastní úrovně, nebo úrovně spoluhráče po síti)
func apply_to(p, lv: Dictionary):
	var l = func(id): return lv.get(id, 0)
	p.cool_mult += 0.08 * l.call("c1")
	p.cool_delay = maxf(p.cool_delay - 0.1 * l.call("c2"), 0.2)
	p.contact_heat_mult *= 1.0 - 0.1 * l.call("c3")
	p.fuse += l.call("c4")
	p.vent_cd_time = maxf(p.vent_cd_time - 0.5 * l.call("c5"), 1.0)
	p.fire_rate_mult *= pow(0.94, l.call("p1"))
	p.pierce += l.call("p2")
	p.heat_up_mult *= 1.0 - 0.08 * l.call("p3")
	if l.call("p4") > 0:
		p.redline_start = minf(p.redline_start, 75.0)
	p.damage += l.call("p5")
	p.chips += 5 * l.call("s1")
	p.chip_magnet *= 1.0 + 0.25 * l.call("s2")
	p.extra_dashes += l.call("s3")
	p.dash_charges = p.max_dashes()
	p.shield = mini(p.shield + l.call("s4"), 3)
	p.set_meta("free_reroll", l.call("s5") > 0)
