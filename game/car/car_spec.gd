class_name CarSpec
extends RefCounted
## The numbers behind one car: mass, aero, engine, gears, brakes and tyres,
## all in SI units. The defaults are a grand prix car a little gentler than a
## modern one (about 3.5 g in fast corners, 330 km/h flat out). Teams differ
## by a few percent in power and downforce; the setup sliders move the wing,
## the top gear, the brake balance and the suspension.

const AIR := 1.225
const G := 9.81

var mass := 760.0
## Distances from the centre of mass to the front and rear axles.
var cg_front := 1.85
var cg_rear := 1.55
var cg_height := 0.30
var yaw_inertia := 1050.0
var track_width := 1.6
## Downforce and drag areas (coefficient times frontal area).
var cl_a := 3.2
var cd_a := 1.05
## Share of downforce on the front axle.
var aero_front := 0.45
var power := 620000.0
var rpm_max := 12000.0
var rpm_limit := 12300.0
var rpm_idle := 4200.0
var wheel_radius := 0.33
## Overall ratios (gearbox times final drive) for gears 1 to 8.
var gears := PackedFloat32Array([14.8, 12.5, 10.55, 8.9, 7.5, 6.33, 5.34, 4.51])
var brake_force := 42000.0
## Share of braking on the front axle.
var brake_balance := 0.58
## Peak tyre grip (friction coefficient) for new soft tyres on a dry road.
var grip := 1.70
## The rear tyres are wider: a little more grip than the fronts.
var rear_grip := 1.03
## Shape of the tyre's grip curve against slip angle (a simple Pacejka curve).
var tyre_b := 12.0
var tyre_c := 1.5
## How much the suspension settles bumps: stiffer turns in quicker but
## loses a little grip over kerbs and bumps.
var stiffness := 0.5
var steer_max := deg_to_rad(16.0)
## Reduction in drag with the rear wing open.
var drs_drag := 0.2


## A team's car: power, downforce and brakes as factors of the default.
static func for_team(engine := 1.0, aero := 1.0, brakes := 1.0) -> CarSpec:
	var c := CarSpec.new()
	c.power *= engine
	c.cl_a *= aero
	c.cd_a *= lerpf(1.0, aero, 0.5)
	c.brake_force *= brakes
	return c


## Applies the car setup: wing 0 (low downforce) to 1 (high), top gear 0
## (short) to 1 (long), brake balance 0.52 to 0.64, stiffness 0 to 1.
func apply_setup(setup: Dictionary) -> CarSpec:
	var wing := float(setup.get("wing", 0.5))
	cl_a *= lerpf(0.82, 1.16, wing)
	cd_a *= lerpf(0.84, 1.14, wing)
	var top := float(setup.get("gear", 0.5))
	var scale := lerpf(1.05, 0.95, top)
	for i in gears.size():
		gears[i] *= scale
	brake_balance = clampf(float(setup.get("balance", 0.58)), 0.52, 0.64)
	stiffness = clampf(float(setup.get("stiffness", 0.5)), 0.0, 1.0)
	return self


## The three ready-made setups.
const PRESETS := {
	"low": {"wing": 0.1, "gear": 0.85, "balance": 0.57, "stiffness": 0.6},
	"balanced": {"wing": 0.5, "gear": 0.5, "balance": 0.58, "stiffness": 0.5},
	"high": {"wing": 0.9, "gear": 0.2, "balance": 0.59, "stiffness": 0.4},
}


func downforce(v: float) -> float:
	return 0.5 * AIR * cl_a * v * v


func drag(v: float) -> float:
	return 0.5 * AIR * cd_a * v * v


## Engine power (watts) at an rpm: rises to full power near the top and
## falls off a little at the limiter.
func power_at(rpm: float) -> float:
	var x := clampf(rpm / rpm_max, 0.0, 1.1)
	var shape := 0.35 + 0.65 * sin(clampf(x, 0.0, 1.0) * PI * 0.5)
	if x > 1.0:
		shape *= 1.0 - (x - 1.0) * 2.0
	return power * shape


## The top speed in the highest gear at the rpm limit (m/s).
func top_gear_speed() -> float:
	return rpm_max / 60.0 * TAU * wheel_radius / gears[gears.size() - 1]


## Speed (m/s) at max rpm in a gear (0-based).
func gear_speed(gear: int) -> float:
	return rpm_max / 60.0 * TAU * wheel_radius / gears[clampi(gear, 0, gears.size() - 1)]
