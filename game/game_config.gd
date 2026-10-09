class_name GameConfig
extends RefCounted
## Game-wide constants: identity, player limits, setting defaults and the
## input map.

const GAME_ID := "race-day"
const TITLE := "Race Day"
## Bump PROTOCOL whenever network messages change; mismatched builds are told
## to update instead of desyncing.
const PROTOCOL := 1
## People in one race (AI drivers fill the rest of the grid).
const MAX_PLAYERS := 8
const MIN_PLAYERS := 1
## Players on one device: two in split screen.
const MAX_LOCAL := 2
## Quick match fills the grid with AI drivers up to a size in this range.
const QUICK_MATCH_SIZE := Vector2i(12, 20)
## Cars on a full grid.
const GRID_SIZE := 20

const SETTING_DEFAULTS := {
	"online": {
		"enabled": true,
		"host": OnlineServer.HOST,
		"port": OnlineServer.PORT,
		"scheme": OnlineServer.SCHEME,
		"server_key": OnlineServer.SERVER_KEY,
	},
	"tutorial": {
		"welcomed": false,
		"hints": true,
	},
	"player": {
		# The team the player drives for outside the career.
		"team": 9,
		"number": 21,
	},
	"camera": {
		# cockpit, tcam, chase_near or chase_far.
		"view": "chase_near",
		"fov": 70.0,
		# Comfort: the defaults are the calm ones.
		"horizon_lock": true,
		"shake": false,
		# How far the driver's head moves with g-forces: 0 none, 1 full.
		"g_head": 0.0,
		"speed_fov": false,
		# How softly the chase cameras follow: 0.6 very soft, 1.0 normal, 1.4 tight.
		"chase_softness": 1.0,
	},
	"assists": {
		# off, corners or full.
		"braking_line": "corners",
		"braking_help": false,
		"steering_help": false,
		"abs": true,
		"tc": true,
		# auto or manual.
		"gears": "auto",
		"pit": true,
		"rewind": true,
	},
	"race": {
		# AI difficulty 0 to 110.
		"difficulty": 70,
		# Share of a full race distance: 0.05 (short) to 1.0.
		"distance": 0.1,
		"damage": 1,
		"tyre_wear": 1.0,
		# none, one_lap or timed.
		"qualifying": "one_lap",
		# dry, mixed, wet or random.
		"weather": "random",
		"grid": 20,
	},
	"hud": {
		"units": "kmh",
		"tower": true,
		"map": true,
		"radio": true,
	},
	"play": {
		"ghost": true,
	},
	"video": {
		# 0 low, 1 medium, 2 high scenery.
		"detail": 1,
	},
}

const MENU_MUSIC := ""

## Every in-game action, with keyboard and controller bindings (see LGInput).
## Each local player reads them through their own LGSeat.
const ACTIONS := {
	"steer_left": ["key:A", "key:Left", "axis:lx-"],
	"steer_right": ["key:D", "key:Right", "axis:lx+"],
	"throttle": ["key:W", "key:Up", "axis:rt+"],
	"brake": ["key:S", "key:Down", "axis:lt+"],
	"shift_up": ["key:E", "joy:a"],
	"shift_down": ["key:Q", "joy:x"],
	"drs": ["key:F", "joy:y"],
	"limiter": ["key:L", "joy:rb"],
	"look_back": ["key:B", "joy:b"],
	"look_left": ["key:Z", "axis:rx-"],
	"look_right": ["key:X", "axis:rx+"],
	"camera": ["key:C", "joy:back"],
	"rewind": ["key:R", "joy:lb"],
	"pit": ["key:P", "joy:down"],
	"tower": ["key:Tab", "joy:up"],
	"pause": ["key:Escape", "joy:start"],
}
## Actions each seat tracks for just_pressed.
const SEAT_ACTIONS := ["shift_up", "shift_down", "limiter", "camera", "rewind", "tower", "pit"]

## The four cameras, in the order the camera button cycles them.
const CAMERAS := ["chase_near", "chase_far", "tcam", "cockpit"]
const CAMERA_NAMES := {"cockpit": "Cockpit", "tcam": "T-cam", "chase_near": "Chase", "chase_far": "Far chase"}


static func version() -> String:
	return LGVersion.current()


static func speed_text(mps: float) -> String:
	if str(LGSettings.get_value("hud", "units")) == "mph":
		return "%d" % roundi(mps * 2.23694)
	return "%d" % roundi(mps * 3.6)


static func speed_unit() -> String:
	return "MPH" if str(LGSettings.get_value("hud", "units")) == "mph" else "KM/H"


## A lap or race time as 1:23.456 (or 23.456 under a minute).
static func time_text(t: float, decimals := 3) -> String:
	if t <= 0.0 or is_inf(t) or is_nan(t):
		return "--:--.---"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	var fmt := "%0" + str(3 + decimals) + "." + str(decimals) + "f"
	if m > 0:
		return ("%d:" + fmt) % [m, s]
	return ("%." + str(decimals) + "f") % s


## A gap as +1.234 (or +1 lap).
static func gap_text(t: float) -> String:
	return "+%.3f" % t
