class_name Teams
extends RefCounted
## The ten teams and twenty drivers of the championship. Each team has its
## own chassis shape and livery, the way real teams build their own cars,
## and a car a few percent quicker or slower than the next.
##
## Chassis: "race" and "future" are Car Kit's formula cars, "racer" is
## Racing Kit v2's, "classic" the Racing Kit's own raceCar.

## id, name, colours (main, accent), chassis, model variant, engine, aero, brakes
const TEAMS := [
	{"id": "meridian", "name": "Meridian Racing", "short": "MER", "main": Color("d9dde3"), "accent": Color("17b2a2"), "chassis": "future", "variant": "", "engine": 1.025, "aero": 1.03, "brakes": 1.0},
	{"id": "ardent", "name": "Ardent GP", "short": "ARD", "main": Color("d42a20"), "accent": Color("f6f2ea"), "chassis": "racer", "variant": "red", "engine": 1.02, "aero": 1.025, "brakes": 1.0},
	{"id": "northstar", "name": "Northstar Racing", "short": "NOR", "main": Color("1d2f6b"), "accent": Color("f2b632"), "chassis": "race", "variant": "", "engine": 1.015, "aero": 1.02, "brakes": 1.0},
	{"id": "volta", "name": "Volta Motorsport", "short": "VOL", "main": Color("ff7a1a"), "accent": Color("1f2430"), "chassis": "classic", "variant": "Orange", "engine": 1.01, "aero": 1.01, "brakes": 1.0},
	{"id": "kestrel", "name": "Kestrel Racing", "short": "KES", "main": Color("2f8f4a"), "accent": Color("f2f2f2"), "chassis": "racer", "variant": "green", "engine": 1.005, "aero": 1.005, "brakes": 1.0},
	{"id": "solaris", "name": "Solaris GP", "short": "SOL", "main": Color("f2c81d"), "accent": Color("1f2430"), "chassis": "racer", "variant": "yellow", "engine": 1.0, "aero": 1.0, "brakes": 1.0},
	{"id": "bluewater", "name": "Bluewater Racing", "short": "BLU", "main": Color("2f7fd6"), "accent": Color("f2f2f2"), "chassis": "racer", "variant": "blue", "engine": 0.995, "aero": 0.995, "brakes": 1.0},
	{"id": "hartmann", "name": "Hartmann Racing", "short": "HAR", "main": Color("f4f4f4"), "accent": Color("d42a20"), "chassis": "classic", "variant": "White", "engine": 0.99, "aero": 0.985, "brakes": 1.0},
	{"id": "redline", "name": "Redline Motorsport", "short": "RED", "main": Color("b31f3a"), "accent": Color("2b2b2b"), "chassis": "classic", "variant": "Red", "engine": 0.985, "aero": 0.98, "brakes": 1.0},
	{"id": "tankco", "name": "Tankco Racing", "short": "TNK", "main": Color("4f8c3a"), "accent": Color("f0e6c8"), "chassis": "classic", "variant": "Green", "engine": 0.975, "aero": 0.97, "brakes": 1.0},
]

## name, short code, nationality (Flag Pack code), team index, skill (0-1),
## and traits: quali (one-lap pace), tyres (kindness), wet, defend.
const DRIVERS := [
	{"name": "Alessia Moretti", "code": "MOR", "nat": "IT", "team": 0, "skill": 0.98, "traits": ["quali"]},
	{"name": "Jonas Lindqvist", "code": "LIN", "nat": "SE", "team": 0, "skill": 0.95, "traits": ["tyres"]},
	{"name": "Rafael Duarte", "code": "DUA", "nat": "BR", "team": 1, "skill": 0.97, "traits": ["wet"]},
	{"name": "Emma Whitfield", "code": "WHI", "nat": "GB", "team": 1, "skill": 0.94, "traits": ["defend"]},
	{"name": "Kenji Arakawa", "code": "ARA", "nat": "JP", "team": 2, "skill": 0.95, "traits": ["quali"]},
	{"name": "Lucas Ferrand", "code": "FER", "nat": "FR", "team": 2, "skill": 0.93, "traits": ["tyres"]},
	{"name": "Mia Kowalski", "code": "KOW", "nat": "PL", "team": 3, "skill": 0.93, "traits": ["wet"]},
	{"name": "Tomás Ibarra", "code": "IBA", "nat": "AR", "team": 3, "skill": 0.91, "traits": ["defend"]},
	{"name": "Niamh Gallagher", "code": "GAL", "nat": "IE", "team": 4, "skill": 0.92, "traits": ["tyres"]},
	{"name": "Felix Brandt", "code": "BRA", "nat": "DE", "team": 4, "skill": 0.9, "traits": ["quali"]},
	{"name": "Sofia Navarro", "code": "NAV", "nat": "ES", "team": 5, "skill": 0.91, "traits": ["defend"]},
	{"name": "Oliver Grant", "code": "GRA", "nat": "AU", "team": 5, "skill": 0.89, "traits": ["wet"]},
	{"name": "Daniel Okafor", "code": "OKA", "nat": "ZA", "team": 6, "skill": 0.9, "traits": ["tyres"]},
	{"name": "Hannah Becker", "code": "BEC", "nat": "AT", "team": 6, "skill": 0.88, "traits": ["quali"]},
	{"name": "Mateo Rossi", "code": "ROS", "nat": "CH", "team": 7, "skill": 0.88, "traits": ["defend"]},
	{"name": "Lea van Dijk", "code": "VDI", "nat": "NL", "team": 7, "skill": 0.87, "traits": ["wet"]},
	{"name": "Carlos Mendes", "code": "MEN", "nat": "PT", "team": 8, "skill": 0.87, "traits": ["tyres"]},
	{"name": "Aiko Tanaka", "code": "TAN", "nat": "JP", "team": 8, "skill": 0.86, "traits": ["quali"]},
	{"name": "Sam Carter", "code": "CAR", "nat": "US", "team": 9, "skill": 0.86, "traits": ["defend"]},
	{"name": "Ines Laurent", "code": "LAU", "nat": "BE", "team": 9, "skill": 0.85, "traits": ["wet"]},
]

## Championship points for the top ten.
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]

## Car numbers by driver index.
const NUMBERS := [1, 4, 7, 11, 3, 23, 9, 27, 14, 31, 5, 22, 10, 18, 16, 77, 8, 44, 2, 12]


static func team(i: int) -> Dictionary:
	return TEAMS[clampi(i, 0, TEAMS.size() - 1)]


static func team_index(id: String) -> int:
	for i in TEAMS.size():
		if TEAMS[i].id == id:
			return i
	return TEAMS.size() - 1


static func points_for(position: int) -> int:
	return POINTS[position - 1] if position >= 1 and position <= POINTS.size() else 0


## A team's car, with any career upgrades (levels 0 to 5 each).
static func spec_for(team_i: int, upgrades := {}) -> CarSpec:
	var t := team(team_i)
	var engine := float(t.engine) + 0.006 * int(upgrades.get("engine", 0))
	var aero := float(t.aero) + 0.007 * int(upgrades.get("aero", 0))
	var brakes := float(t.brakes) + 0.02 * int(upgrades.get("brakes", 0))
	return CarSpec.for_team(engine, aero, brakes)


static func flag_texture(code: String) -> Texture2D:
	var path := "res://assets/kenney/flags/%s.png" % code
	return load(path) if ResourceLoader.exists(path) else null


## How fast an AI driver is at a difficulty of 0 to 110: pace on the limit
## at 100 for the best driver, gentler below.
static func ai_pace(skill: float, difficulty: float) -> float:
	var base := lerpf(0.84, 1.0, clampf(difficulty, 0.0, 100.0) / 100.0)
	if difficulty > 100.0:
		base += (difficulty - 100.0) * 0.0015
	return base * lerpf(0.975, 1.0, clampf((skill - 0.85) / 0.13, 0.0, 1.0))
