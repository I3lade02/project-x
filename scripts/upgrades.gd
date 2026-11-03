extends RefCounted

const LIST = {
	"cooler":    {"name": "Lepší chladič",      "desc": "Chlazení +30 %",                            "max": 5, "tag": "cool"},
	"paste":     {"name": "Teplovodivá pasta",  "desc": "Chlazení začne o 0,2 s dřív",               "max": 3, "tag": "cool"},
	"efficient": {"name": "Úsporné jádro",      "desc": "Výstřely hřejí o 25 % méně",                "max": 3, "tag": "shotheat"},
	"firerate":  {"name": "Rychlejší takt",     "desc": "Rychlost palby +20 %",                      "max": 4, "tag": "firerate"},
	"pierce":    {"name": "Průrazné střely",    "desc": "Střela projde o 1 bug víc",                 "max": 3, "tag": "pierce"},
	"multishot": {"name": "Dvojitá hlaveň",     "desc": "+1 střela navíc (vějíř)",                   "max": 3, "tag": "jam"},
	"damage":    {"name": "Tvrdší náboje",      "desc": "Poškození +1",                              "max": 3, "tag": "damage"},
	"speed":     {"name": "Rychlé nohy",        "desc": "Rychlost pohybu +10 %",                     "max": 3, "tag": "speed"},
	"jump":      {"name": "Pružiny",            "desc": "+1 skok ve vzduchu (trvale)",               "max": 1, "tag": "jump"},
	"armor":     {"name": "Chlazený plášť",     "desc": "Dotyk bugu hřeje o 30 % méně",              "max": 2, "tag": "contact"},
	"reboot":    {"name": "Rychlý reboot",      "desc": "Crash trvá o 0,7 s kratší",                 "max": 2, "tag": "crash"},
	"blast":     {"name": "Termální výbuch",    "desc": "Při crashi vybuchneš a zraníš bugy kolem",  "max": 1, "tag": "crash"},
	"heatpower": {"name": "Žár = síla",         "desc": "Nad 50 % teploty +1 poškození",             "max": 1, "tag": "damage"},
}

# postihy – corrupt se stejným tagem jako upgrade se k němu nikdy nevylosuje
const CORRUPTS = {
	"fan":       {"name": "Hlučný větrák",       "desc": "Chlazení −15 %",                        "max": 3, "tag": "cool"},
	"sensor":    {"name": "Vadný senzor",        "desc": "Overclock hřeje o 25 % víc",            "max": 3, "tag": "ocheat"},
	"fragment":  {"name": "Fragmentace",         "desc": "Výstřely hřejí o 20 % víc",             "max": 3, "tag": "shotheat"},
	"io":        {"name": "Pomalé I/O",          "desc": "Rychlost palby −10 %",                  "max": 3, "tag": "firerate"},
	"heavy":     {"name": "Těžký kód",           "desc": "Rychlost pohybu −8 %",                  "max": 3, "tag": "speed"},
	"firewall":  {"name": "Děravý firewall",     "desc": "Bugové mají +1 HP",                     "max": 3, "tag": "damage"},
	"fastbugs":  {"name": "Přetaktovaní bugové", "desc": "Bugové jsou o 10 % rychlejší",          "max": 3, "tag": "enemyspeed"},
	"leak":      {"name": "Únik paměti",         "desc": "+2 bugy v každé vlně",                  "max": 3, "tag": "enemycount"},
	"sensitive": {"name": "Tepelná citlivost",   "desc": "Dotyk bugu hřeje o 25 % víc",           "max": 2, "tag": "contact"},
	"boot":      {"name": "Pomalý boot",         "desc": "Crash trvá o 0,5 s déle",               "max": 2, "tag": "crash"},
	"packet":    {"name": "Packet loss",         "desc": "15 % výstřelů se zasekne (ale hřeje)",  "max": 2, "tag": "jam"},
	"dry":       {"name": "Vyschlé chladivo",    "desc": "Bonusy padají o 30 % méně často",       "max": 2, "tag": "drops"},
}


# vrátí až `count` náhodných upgradů, které ještě nejsou na maximu
static func pick(owned: Dictionary, count: int) -> Array:
	var pool = []
	for id in LIST:
		if owned.get(id, 0) < LIST[id]["max"]:
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, count)


# vylosuje corrupt k upgradu (nebo "" když už žádný nezbývá)
static func pick_corrupt(upgrade_id: String, owned: Dictionary) -> String:
	var tag = LIST[upgrade_id]["tag"]
	var pool = []
	for id in CORRUPTS:
		if CORRUPTS[id]["tag"] != tag and owned.get(id, 0) < CORRUPTS[id]["max"]:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool.pick_random()
