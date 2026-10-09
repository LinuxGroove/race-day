class_name RaceNet
extends Node
## A race between devices. The host runs the rules and the AI; each device
## drives its own players' cars (so steering feels instant even online) and
## sends their state to the host, which sends every car, the timing and the
## race's events to each device with rpc_id.
##
##   _c_car       a client's car, 30 times a second (unreliable)
##   _h_cars      every car to each client, 20 times a second (unreliable)
##   _h_timing    laps, positions, gaps and the race state, 5 times a second
##   _h_event     a race event (lights, laps, penalties, flags), reliable
##   _h_next      the next session of the weekend, with the grid

const SEND_EVERY := 4
const CARS_EVERY := 6
const TIMING_EVERY := 24
## The host starts the lights once every device has the circuit loaded, or
## after this long.
const LOAD_WAIT := 20.0

var scene: RaceScene
var _tick := 0
var _wait := 0.0
## Clients: the latest state of each car driven elsewhere, extrapolated.
var _targets := {}


func setup(p_scene: RaceScene) -> void:
	scene = p_scene


func session_started() -> void:
	_targets.clear()
	_wait = 0.0
	var race := scene.race
	if Session.is_host():
		race.hold_start = race.kind == Race.Kind.RACE
	else:
		race.authority = false
		# Everyone else's cars come from the host.
		for e in race.entries:
			if e.bot or e.peer != Session.local_id():
				e.remote = true
				e.ai = null


func next_session() -> void:
	var ids := []
	for d in scene.grid_order:
		ids.append(int(d.id))
	for peer in multiplayer.get_peers():
		_h_next.rpc_id(peer, ids)


func before_step() -> void:
	if not Session.is_host():
		_extrapolate()


func after_step() -> void:
	_tick += 1
	var race := scene.race
	if Session.is_host():
		if race.hold_start:
			_wait += Race.DT
			var ready := true
			for peer in multiplayer.get_peers():
				if not Session.loaded_peers.has(peer):
					ready = false
			if ready or _wait > LOAD_WAIT:
				race.hold_start = false
		if _tick % CARS_EVERY == 0:
			_send_cars()
		if _tick % TIMING_EVERY == 0:
			_send_timing()
	elif _tick % SEND_EVERY == 0:
		for p in scene.players:
			var e: Race.Entry = p.entry
			_c_car.rpc_id(1, e.id, _pack(e))


func on_event(ev: Dictionary) -> void:
	if not Session.is_host():
		return
	for peer in multiplayer.get_peers():
		if Session.loaded_peers.has(peer):
			_h_event.rpc_id(peer, ev)


# --- Packing ------------------------------------------------------------

static func _pack(e: Race.Entry) -> Array:
	var s := e.sim
	return [s.pos, s.yaw, s.vel, s.yaw_rate, s.steer_angle, s.gear, s.rpm, e.input.throttle,
		s.compound, s.wear, s.damage, s.wing_damage, s.limiter_on, s.drs_open, e.input.brake]


func _unpack(e: Race.Entry, a: Array, snap: bool) -> void:
	var s := e.sim
	if snap:
		s.pos = a[0]
		s.yaw = a[1]
		s.track.locate(Vector2(s.pos.x, s.pos.z), s.spot.idx, s.spot)
	s.vel = a[2]
	s.yaw_rate = a[3]
	s.steer_angle = a[4]
	s.gear = a[5]
	s.rpm = a[6]
	e.input.throttle = a[7]
	s.compound = a[8]
	s.wear = a[9]
	s.damage = a[10]
	s.wing_damage = a[11]
	s.limiter_on = a[12]
	s.drs_open = a[13]
	e.input.brake = a[14]
	s.speed = s.vel.length()
	s.wheel_turn_front += s.forward_speed() / s.spec.wheel_radius * Race.DT * CARS_EVERY
	s.wheel_turn_rear = s.wheel_turn_front


## Clients move other cars on between updates and ease them onto the latest.
func _extrapolate() -> void:
	for id in _targets:
		var e: Race.Entry = scene.race.entry(id)
		if e == null:
			continue
		var t: Array = _targets[id]
		t[0] = (t[0] as Vector3) + Vector3(t[2].x, 0.0, t[2].y) * Race.DT
		t[1] = float(t[1]) + float(t[3]) * Race.DT
		var s := e.sim
		var p: Vector3 = t[0]
		if s.pos.distance_to(p) > 12.0:
			s.pos = p
			s.yaw = t[1]
		else:
			s.pos = s.pos.lerp(p, 0.18)
			s.yaw = lerp_angle(s.yaw, float(t[1]), 0.18)
		s.track.locate(Vector2(s.pos.x, s.pos.z), s.spot.idx, s.spot)
		s.pos.y = s.spot.y
		s.wheel_turn_front += s.forward_speed() / s.spec.wheel_radius * Race.DT
		s.wheel_turn_rear = s.wheel_turn_front


func _send_cars() -> void:
	var race := scene.race
	for peer in multiplayer.get_peers():
		if not Session.loaded_peers.has(peer):
			continue
		var list := []
		for e in race.entries:
			if not e.bot and e.peer == peer:
				continue
			list.append([e.id, _pack(e)])
		_h_cars.rpc_id(peer, list)


func _send_timing() -> void:
	var race := scene.race
	var rows := []
	for e in race.entries:
		rows.append([e.id, e.lap, e.lap_start, e.last_lap, e.best_lap, e.position, e.gap, e.interval,
			e.laps_down, e.finished, e.retired, e.in_pit_lane, e.pit_stop_t, e.penalty, e.s_total,
			e.lap_valid, e.drs_ok, e.blue, e.finish_time, e.stops, e.points, e.cleared, e.start_position])
	var state := [race.phase, race.time, race.lights, race.vsc, race.yellow, race.wetness, race.rain,
		race.leader_finished_t, race.fastest, race.sc, race.sc_s, race.sc_in]
	for peer in multiplayer.get_peers():
		if Session.loaded_peers.has(peer):
			_h_timing.rpc_id(peer, state, rows)


# --- RPCs ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _c_car(id: int, state: Array) -> void:
	if not Session.is_host() or scene.race == null:
		return
	var e := scene.race.entry(id)
	# A device may only move its own players' cars.
	if e == null or e.bot or e.peer != multiplayer.get_remote_sender_id():
		return
	e.remote = true
	_unpack(e, state, true)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _h_cars(list: Array) -> void:
	if scene.race == null:
		return
	for item in list:
		var id := int(item[0])
		var e := scene.race.entry(id)
		if e == null or not e.remote:
			continue
		var a: Array = item[1]
		_unpack(e, a, not _targets.has(id))
		_targets[id] = [a[0], a[1], a[2], a[3]]


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _h_timing(state: Array, rows: Array) -> void:
	var race := scene.race
	if race == null:
		return
	race.phase = state[0]
	race.time = state[1]
	race.lights = state[2]
	race.vsc = state[3]
	race.yellow = state[4]
	race.wetness = state[5]
	race.rain = state[6]
	race.leader_finished_t = state[7]
	race.fastest = state[8]
	race.sc = state[9]
	race.sc_s = state[10]
	race.sc_in = state[11]
	for r in rows:
		var e := race.entry(int(r[0]))
		if e == null:
			continue
		e.lap = r[1]
		e.lap_start = r[2]
		e.last_lap = r[3]
		e.best_lap = r[4]
		e.position = r[5]
		e.gap = r[6]
		e.interval = r[7]
		e.laps_down = r[8]
		e.finished = r[9]
		e.retired = r[10]
		e.in_pit_lane = r[11]
		e.pit_stop_t = r[12]
		e.penalty = r[13]
		e.s_total = r[14]
		e.lap_valid = r[15]
		e.drs_ok = r[16]
		e.blue = r[17]
		e.finish_time = r[18]
		e.stops = r[19]
		e.points = r[20]
		e.cleared = r[21]
		e.start_position = r[22]
		e.sim.wetness = race.wetness
	race.order.sort_custom(func(a, b): return a.position < b.position)


@rpc("authority", "call_remote", "reliable")
func _h_event(ev: Dictionary) -> void:
	scene.race.events.append(ev)


@rpc("authority", "call_remote", "reliable")
func _h_next(ids: Array) -> void:
	var by_id := {}
	for d in scene.grid_order:
		by_id[int(d.id)] = d
	var ordered := []
	for id in ids:
		if by_id.has(int(id)):
			ordered.append(by_id[int(id)])
	scene.grid_order = ordered
	scene.continue_from_host()
