extends Node
## How forgiving the car is for a new player. A clumsy driver (late, heavy
## hands on the wheel, flat out whenever it isn't braking) drives the
## player's car through PlayerDriver and its assists, starting afresh every
## 200 m round each layout for a few seconds, and the check counts how many
## of those runs end in a spin, off the road or in a barrier.
##
##   godot --headless --path . tools/handling_check.tscn
##   CIRCUIT=greenfield,monte_pineta ASSISTS=none PAD=stick godot --headless --path . tools/handling_check.tscn
##
## ASSISTS is "default" (the settings' defaults), "none" or a list like
## "steering_help,abs,tc". PAD is stick, keyboard or both. OVER is how much
## faster than the AI's speeds the driver takes corners (a list: 1.0,1.15),
## HEAVY how much more lock than needed it gives, DELAY its reaction time
## in seconds, WHY=1 prints what led to each incident.

const DEFAULT_CIRCUITS := "greenfield,monte_pineta,hay_valley,port_lumen,cliffside,bellwood"
## Seconds per run, and metres between their starts.
const RUN_TIME := 7.0
const SPACING := 200.0


class Novice:
	## Seconds between seeing and reacting.
	var delay := 0.2
	## How much more lock than the corner needs.
	var heavy := 1.4
	var keyboard := false
	var _queue: Array = []
	var _key := 0.0

	func reset() -> void:
		_queue.clear()
		_key = 0.0

	## The stick or keys for a wheel angle (radians) at speed v, as a new
	## player gives it: too much, and late.
	func steer(angle: float, v: float, dt: float) -> float:
		var want := angle / deg_to_rad(16.0) * heavy
		if not keyboard:
			# Players learn the stick's curve and that it does less at speed.
			want /= lerpf(1.0, 0.55, clampf(v / 80.0, 0.0, 1.0))
			want = signf(want) * pow(minf(absf(want), 1.0), 1.0 / 1.6)
		want = clampf(want, -1.0, 1.0)
		var n := int(delay / dt)
		while _queue.size() < n:
			_queue.append(want)
		_queue.append(want)
		var out: float = _queue.pop_front()
		if not keyboard:
			return out
		# Keys: press and hold, with a little hysteresis.
		if absf(out) > 0.35:
			_key = signf(out)
		elif absf(out) < 0.15:
			_key = 0.0
		return _key


func _ready() -> void:
	var ids := OS.get_environment("CIRCUIT") if OS.has_environment("CIRCUIT") else DEFAULT_CIRCUITS
	var assists := OS.get_environment("ASSISTS") if OS.has_environment("ASSISTS") else "default"
	var pads := OS.get_environment("PAD") if OS.has_environment("PAD") else "both"
	var overs := (OS.get_environment("OVER") if OS.has_environment("OVER") else "1.0,1.15").split(",")
	var heavy := float(OS.get_environment("HEAVY")) if OS.has_environment("HEAVY") else 1.4
	var modes := ["stick", "keyboard"] if pads == "both" else [pads]
	var total := {"runs": 0, "spins": 0, "offs": 0, "hits": 0}
	print("assists: %s" % assists)
	print("%-16s %-8s %5s %5s %6s %6s %6s" % ["layout", "pad", "over", "runs", "spins", "offs", "hits"])
	for id in ids.split(","):
		var t := Circuits.track(id)
		for mode in modes:
			for o in overs:
				var r := _layout(t, id, assists, mode == "keyboard", float(o), heavy)
				print("%-16s %-8s %5.2f %5d %6d %6d %6d" % [id, mode, float(o), r.runs, r.spins, r.offs, r.hits])
				for k in total:
					total[k] += r[k]
	var runs := maxf(total.runs, 1.0)
	print("total: %d runs, %.1f%% spun, %.1f%% left the road, %.1f%% hit a barrier" % [total.runs,
		100.0 * total.spins / runs, 100.0 * total.offs / runs, 100.0 * total.hits / runs])
	get_tree().quit()


func _layout(t: Track, id: String, assists: String, keyboard: bool, over: float, heavy: float) -> Dictionary:
	var race := Race.new(t, Race.Kind.PRACTICE, 99, 1)
	var e := race.add_car(1, "You", 0, 0)
	var driver := PlayerDriver.new(LGSeat.primary(), e, race)
	for k in ["steering_help", "braking_help", "abs", "tc"]:
		if assists == "none":
			driver.overrides[k] = false
		elif assists != "default":
			driver.overrides[k] = k in assists.split(",")
	driver.refresh()
	var profile := race.speeds_for(0)
	var human := Novice.new()
	human.keyboard = keyboard
	human.heavy = heavy
	if OS.has_environment("DELAY"):
		human.delay = float(OS.get_environment("DELAY"))
	var res := {"runs": 0, "spins": 0, "offs": 0, "hits": 0}
	var s0 := 0.0
	while s0 < t.length - 1.0:
		var what := _attempt(t, driver, e, human, profile, s0, over)
		res.runs += 1
		if what != "":
			res[what] += 1
			if OS.has_environment("WHY"):
				print("    %s at %.0f m" % [id, s0])
		s0 += SPACING
	return res


## One run from s0: what it ended in ("spins", "offs" or "hits"), or "".
func _attempt(t: Track, driver: PlayerDriver, e: Race.Entry, human: Novice, profile: PackedFloat32Array, s0: float, over: float) -> String:
	var sim := e.sim
	sim.place_moving(s0, t.value_at(t.line_off, s0), t.value_at(profile, s0) * 0.95)
	sim.wing_damage = 0.0
	sim.damage = 0.0
	human.reset()
	var dt := Race.DT
	var off_t := 0.0
	var hist: Array = []
	for tick in int(RUN_TIME / dt):
		var v := absf(sim.forward_speed())
		var s := sim.spot.s
		# Aim for a point on the racing line a little way ahead (pure
		# pursuit: the wheel angle that arcs onto it).
		var look := clampf(6.0 + 0.32 * v, 8.0, 40.0)
		var ahead := t.world(t.wrap_s(s + look), t.value_at(t.line_off, t.wrap_s(s + look)))
		var to := Vector2(ahead.x, ahead.z) - Vector2(sim.pos.x, sim.pos.z)
		var err := atan2(to.dot(sim.left2()), to.dot(sim.forward2()))
		var wb := sim.spec.cg_front + sim.spec.cg_rear
		var steer := human.steer(-atan(wb * 2.0 * sin(err) / maxf(to.length(), 1.0)), v, dt)
		# Brake late for the corners ahead, flat out otherwise.
		var brake := 0.0
		var throttle := 1.0
		var d := 0.0
		while d < 220.0:
			var limit := t.value_at(profile, t.wrap_s(s + d)) * over
			if v > sqrt(limit * limit + 2.0 * 13.0 * d) + 0.5:
				brake = 1.0
				throttle = 0.0
				break
			d += 8.0
		driver.controls(dt, steer, throttle, brake, human.keyboard)
		sim.step(dt, e.input)
		hist.append([v, e.input.throttle, e.input.brake, e.input.steer, sim.rear_spin, sim.front_lock, sim.wheels_out])
		var heading := absf(angle_difference(atan2(sim.forward2().x, sim.forward2().y), atan2(sim.spot.tangent.x, sim.spot.tangent.y)))
		var what := ""
		if heading > 1.0:
			what = "spins"
		elif sim.impact > 3.0:
			what = "hits"
		elif sim.wheels_out >= 4:
			off_t += dt
			if off_t > 0.5:
				what = "offs"
		else:
			off_t = 0.0
		if what != "":
			if OS.has_environment("WHY"):
				_why(what, hist)
			return what
	return ""


## What the car was doing in the second and a half before an incident.
func _why(what: String, hist: Array) -> void:
	var line := "  %s:" % what
	for k in range(maxi(0, hist.size() - 180), hist.size(), 30):
		var h: Array = hist[k]
		line += " | v%.0f t%.1f b%.1f s%+.2f%s%s%s" % [h[0], h[1], h[2], h[3], " SPIN" if h[4] > 0.05 else "",
			" LOCK" if h[5] > 0.3 else "", " OUT%d" % h[6] if h[6] > 0 else ""]
	print(line)
