class_name Tyres
extends RefCounted
## The five tyre compounds: grip on a dry and a wet road, how fast they wear,
## and their colours on the timing tower.

enum { SOFT, MEDIUM, HARD, INTER, WET }

const NAMES := ["Soft", "Medium", "Hard", "Intermediate", "Wet"]
const LETTERS := ["S", "M", "H", "I", "W"]
const COLORS := [Color("ef4a3c"), Color("f4c430"), Color("f2f2f2"), Color("3fbf5f"), Color("3e8bff")]
## Grip on a dry road and on a wet one, as a share of a new soft.
const DRY_GRIP := [1.0, 0.975, 0.952, 0.86, 0.80]
const WET_GRIP := [0.55, 0.55, 0.54, 0.80, 0.84]
## Seconds of hard racing before the tyre is worn out.
const LIFE := [1500.0, 2300.0, 3200.0, 2600.0, 2400.0]
## Slicks and rain tyres: inters and wets wear quickly on a dry road.
const DRY_LIFE_SCALE := [1.0, 1.0, 1.0, 0.3, 0.2]


static func is_slick(c: int) -> bool:
	return c <= HARD


## Grip for a compound on a road `wetness` 0 (dry) to 1 (soaked), worn to
## `wear` 0 (new) to 1 (gone), at temperature `temp` 0 (cold) to 1 (working).
static func grip(c: int, wetness: float, wear: float, temp: float) -> float:
	var g := lerpf(float(DRY_GRIP[c]), float(WET_GRIP[c]), clampf(wetness, 0.0, 1.0))
	var worn := 1.0 - 0.07 * wear
	if wear > 0.7:
		worn -= (wear - 0.7) / 0.3 * 0.3
	return g * maxf(0.55, worn) * lerpf(0.9, 1.0, clampf(temp, 0.0, 1.0))


## How much faster than normal a compound wears on this road.
static func wear_rate(c: int, wetness: float) -> float:
	var life: float = LIFE[c]
	if not is_slick(c):
		life *= lerpf(float(DRY_LIFE_SCALE[c]), 1.0, clampf(wetness * 1.5, 0.0, 1.0))
	return 1.0 / life
