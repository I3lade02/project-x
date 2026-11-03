extends RefCounted

const LIST = {
	"cooler":    {"name": "Lepší chladič",      "desc": "Chlazení +30 %",                            "max": 5},
	"paste":     {"name": "Teplovodivá pasta",  "desc": "Chlazení začne o 0,2 s dřív",               "max": 3},
	"efficient": {"name": "Úsporné jádro",      "desc": "Výstřely hřejí o 25 % méně",                "max": 3},
	"firerate":  {"name": "Rychlejší takt",     "desc": "Rychlost palby +20 %",                      "max": 4},
	"pierce":    {"name": "Průrazné střely",    "desc": "Střela projde o 1 bug víc",                 "max": 3},
	"multishot": {"name": "Dvojitá hlaveň",     "desc": "+1 střela navíc (vějíř)",                   "max": 3},
	"damage":    {"name": "Tvrdší náboje",      "desc": "Poškození +1",                              "max": 3},
	"speed":     {"name": "Rychlé nohy",        "desc": "Rychlost pohybu +10 %",                     "max": 3},
	"jump":      {"name": "Pružiny",            "desc": "+1 skok ve vzduchu (trvale)",               "max": 1},
	"armor":     {"name": "Chlazený plášť",     "desc": "Dotyk bugu hřeje o 30 % méně",              "max": 2},
	"reboot":    {"name": "Rychlý reboot",      "desc": "Crash trvá o 0,7 s kratší",                 "max": 2},
	"blast":     {"name": "Termální výbuch",    "desc": "Při crashi vybuchneš a zraníš bugy kolem",  "max": 1},
	"heatpower": {"name": "Žár = síla",         "desc": "Nad 50 % teploty +1 poškození",             "max": 1},
}


# vrátí až `count` náhodných upgradů, které ještě nejsou na maximu
static func pick(owned: Dictionary, count: int) -> Array:
	var pool = []
	for id in LIST:
		if owned.get(id, 0) < LIST[id]["max"]:
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, count)
