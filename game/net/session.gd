extends Node
## The lobby and transport for one play session (autoload: Session), and the
## way into every race.
##
## Every mode runs the same host-authoritative weekend:
##   SOLO     this device hosts, AI drivers fill the grid, no network
##   LAN      ENet on the local network, found by LanBeacon or a join code
##   ONLINE   Nakama relay through the shared game server, joined by room code
## Peer 1 is always the host. AI drivers exist only on the host.
##
## Each device can bring two players (split screen): the keyboard or first
## controller, and a second controller. A player's actor id is
## peer * 4 + seat, so it is the same on every device.
##
## Single-player modes (Championship, Career, Time Trial, Racing School) start
## a SOLO session and launch a race straight away.

signal roster_changed
signal settings_changed
signal seats_changed
signal hosts_found(hosts: Array)
signal joined
signal left(reason: String)
signal status(text: String)
## Host: a player's device has loaded the circuit and can receive the race.
signal peer_loaded(id: int)

enum Mode { NONE, SOLO, LAN_HOST, LAN_CLIENT, ONLINE_HOST, ONLINE_CLIENT }

const HELLO_TIMEOUT := 6.0
## Quick match looks this long for other players before racing the AI.
const QUICK_SEARCH_SECONDS := 60.0
## Then the first race starts by itself after this long in the lobby.
const QUICK_COUNTDOWN := 15.0
const SEATS_PER_PEER := 4
const RACE_SCENE := "res://game/play/race_scene.tscn"
const TITLE_SCENE := "res://game/ui/title.tscn"
const LOBBY_SCENE := "res://game/ui/lobby.tscn"

## The lobby's race settings (the host's choice).
const DEFAULT_SETTINGS := {
	"circuit": "greenfield",
	"laps": 5,
	"qualifying": "one_lap",
	"difficulty": 70,
	"weather": "random",
	"grid": 20,
	"damage": 1,
	"tyre_wear": 1.0,
}

var mode := Mode.NONE
## actor id -> {"name", "team", "number", "peer", "seat", "bot": false}
var players := {}
var settings := DEFAULT_SETTINGS.duplicate()
var join_code := ""
var lan_address := ""
var in_match := false
var match_config := {}
## Host: peers whose race scene is ready, so race messages can reach them.
var loaded_peers := {}
var races_played := 0
## This lobby came from quick match: AI drivers get made-up names, and a
## countdown starts the first race so nobody waits on a stranger.
var quick := false
## What launched the current race: quick, championship, career, time_trial,
## school or multiplayer.
var play_mode := "quick"
var _quick_start_msec := 0
var _quick_target := 0
## This device's players: [{"pad", "name", "team", "number"}]. Seat 0 is the
## keyboard player (pad LGSeat.ANY_FREE_PAD); seat 1 owns a controller.
var local_seats: Array = []

var _beacon: LanBeacon
var _pending_hello := {}
var _seat_inputs := {}


func _ready() -> void:
	_beacon = LanBeacon.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	_beacon.hosts_changed.connect(_on_beacon_hosts)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	_load_lobby_settings()
	_reset_seats()


func is_host() -> bool:
	return mode in [Mode.SOLO, Mode.LAN_HOST, Mode.ONLINE_HOST, Mode.NONE]


func is_online() -> bool:
	return mode in [Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]


## A race other devices take part in.
func is_networked() -> bool:
	return mode in [Mode.LAN_HOST, Mode.LAN_CLIENT, Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]


func local_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func player_name() -> String:
	var n := str(LGSettings.get_value("player", "name")).strip_edges()
	return n if n != "" else "Driver"


func player_team() -> int:
	return clampi(int(LGSettings.get_value("player", "team")), 0, Teams.TEAMS.size() - 1)


static func actor_id(peer: int, seat: int) -> int:
	return peer * SEATS_PER_PEER + seat


# --- Split screen seats ---------------------------------------------------

## The controls for this device's seat `index`.
func seat_input(index: int) -> LGSeat:
	if not _seat_inputs.has(index):
		if index == 0 or index >= local_seats.size():
			_seat_inputs[index] = LGSeat.primary()
		else:
			_seat_inputs[index] = LGSeat.for_pad(index, int(local_seats[index].pad))
		_seat_inputs[index].deadzone = float(LGSettings.get_value("input", "stick_deadzone"))
	return _seat_inputs[index]


## Adds a player on controller `pad`. Returns the new seat index, or -1.
func add_local_seat(pad: int) -> int:
	if local_seats.size() >= GameConfig.MAX_LOCAL or in_match:
		return -1
	for s in local_seats:
		if int(s.pad) == pad:
			return -1
	var index := local_seats.size()
	# Player 2 drives for the other car of player 1's team.
	local_seats.append({"pad": pad, "name": "Player %d" % (index + 1), "team": player_team(), "number": 22})
	LGInput.claim_pad(pad, index)
	_seats_updated()
	return index


func remove_local_seat(index: int) -> void:
	if index <= 0 or index >= local_seats.size() or in_match:
		return
	LGInput.release_pad(int(local_seats[index].pad))
	local_seats.remove_at(index)
	_seats_updated()


func set_seat_value(index: int, key: String, value: Variant) -> void:
	if index < 0 or index >= local_seats.size():
		return
	local_seats[index][key] = value
	if index == 0 and key == "team":
		LGSettings.set_value("player", "team", value)
	_seats_updated()


func seat_for_pad(pad: int) -> int:
	for i in range(1, local_seats.size()):
		if int(local_seats[i].pad) == pad:
			return i
	return -1


func _reset_seats() -> void:
	for i in range(1, local_seats.size()):
		LGInput.release_pad(int(local_seats[i].pad))
	local_seats = [{"pad": LGSeat.ANY_FREE_PAD, "name": player_name(), "team": player_team(), "number": int(LGSettings.get_value("player", "number"))}]
	_seat_inputs.clear()


func _seats_updated() -> void:
	_seat_inputs.clear()
	local_seats[0].name = player_name()
	if is_host() and mode != Mode.NONE:
		_apply_seats(1, _seat_payload())
	elif mode != Mode.NONE:
		_c_seats.rpc_id(1, _seat_payload())
	seats_changed.emit()


func _seat_payload() -> Array:
	var out := []
	for s in local_seats:
		out.append([str(s.name), int(s.team), int(s.number)])
	return out


## Host: replaces a peer's players with the seats it sent.
func _apply_seats(peer: int, seats: Array) -> void:
	for id in players.keys():
		if int(players[id].peer) == peer:
			players.erase(id)
	for i in mini(seats.size(), GameConfig.MAX_LOCAL):
		if players.size() >= GameConfig.MAX_PLAYERS:
			break
		var s: Array = seats[i]
		players[actor_id(peer, i)] = {
			"name": _unique_name(str(s[0]).strip_edges().left(16)),
			"team": clampi(int(s[1]), 0, Teams.TEAMS.size() - 1),
			"number": clampi(int(s[2]), 0, 99),
			"peer": peer, "seat": i, "bot": false,
		}
	_broadcast_roster()


# --- Starting single-player races ---------------------------------------

## Quick Race, Championship, Career, Time Trial and the Racing School all
## run as a solo session on this device.
func start_solo() -> void:
	leave()
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_apply_seats(1, _seat_payload())
	joined.emit()
	roster_changed.emit()


## Launches a race weekend with this config (see RaceScene). Solo only; the
## lobby uses start_match().
func launch(config: Dictionary) -> void:
	if mode != Mode.SOLO:
		start_solo()
	play_mode = str(config.get("mode", "quick"))
	in_match = true
	match_config = config
	LGInput.filter_claimed_pads = false
	LGScenes.change_scene(RACE_SCENE, _setup_race.bind(config))


func _setup_race(node: Node, config: Dictionary) -> void:
	node.set("config", config)


## A race config from the lobby settings for these people.
func make_config(people: Array, p_settings: Dictionary, p_mode: String, seed := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
		seed = rng.randi()
	rng.seed = seed
	var circuit := str(p_settings.get("circuit", "greenfield"))
	if Circuits.info(circuit).is_empty():
		circuit = Circuits.ids()[0]
	var i := Circuits.info(circuit)
	var difficulty := float(p_settings.get("difficulty", 70))
	var drivers := Grid.build(people, int(p_settings.get("grid", GameConfig.GRID_SIZE)), difficulty, seed)
	if quick:
		var used := []
		for d in drivers:
			used.append(d.name)
		for d in drivers:
			if bool(d.bot):
				d.name = LGNameMaker.make(used, rng)
				d.code = Grid.code_for(d.name)
				used.append(d.name)
	var weather := Weather.make(str(p_settings.get("weather", "random")), float(i.get("rain", 0.2)), rng)
	return {
		"mode": p_mode,
		"circuit": circuit,
		"laps": int(p_settings.get("laps", 5)),
		"qualifying": str(p_settings.get("qualifying", "one_lap")),
		"drivers": drivers,
		"forecast": weather.forecast,
		"wet": weather.wet,
		"seed": seed,
		"difficulty": difficulty,
		"damage": int(p_settings.get("damage", 1)),
		"tyre_wear": float(p_settings.get("tyre_wear", 1.0)),
		"title": str(i.get("name", circuit)),
	}


## People for a race from this device's seats (solo).
func local_people() -> Array:
	var out := []
	for i in local_seats.size():
		var s: Dictionary = local_seats[i]
		out.append({"id": actor_id(1, i), "name": str(s.name) if i > 0 else player_name(), "team": int(s.team), "number": int(s.number), "peer": 1, "seat": i})
	return out


func start_time_trial(layout: String) -> void:
	start_solo()
	var people := [local_people()[0]]
	var config := make_config(people, {"circuit": layout, "grid": 1, "weather": "dry"}, "time_trial")
	config.drivers = Grid.build(people, 1, 100.0)
	config.forecast = []
	config.wet = 0.0
	config.qualifying = "none"
	launch(config)


## The race scene's end: where to go after the results.
func weekend_done(config: Dictionary, results: Array) -> void:
	in_match = false
	match str(config.get("mode", "quick")):
		"championship":
			Progress.record_championship_round(config, results)
			LGScenes.change_scene(TITLE_SCENE, func(n): n.set("open_page", "championship"))
		"career":
			Progress.record_career_round(config, results)
			LGScenes.change_scene(TITLE_SCENE, func(n): n.set("open_page", "career"))
		"multiplayer":
			if is_host():
				report_race(results)
				return_to_lobby()
		"time_trial", "school":
			var page := str(config.mode)
			leave()
			LGScenes.change_scene(TITLE_SCENE, func(n): n.set("open_page", page))
		_:
			if mode == Mode.SOLO and local_seats.size() > 1:
				LGScenes.change_scene(LOBBY_SCENE)
			else:
				leave()
				LGScenes.change_scene(TITLE_SCENE)


## Leaves a race for the menus.
func quit_race() -> void:
	if is_networked():
		if is_host():
			return_to_lobby()
		else:
			leave("You left the race.")
			LGScenes.change_scene(TITLE_SCENE)
		return
	in_match = false
	var back := play_mode
	leave()
	LGScenes.change_scene(TITLE_SCENE, func(n): n.set("open_page", back))


## A Time Trial lap for the online board (fire and forget).
func submit_time_trial(layout: String, lap: float) -> void:
	if not LGOnline.is_enabled() or not LGNetwork.is_up():
		return
	_submit_async(layout, lap)


func _submit_async(layout: String, lap: float) -> void:
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		return
	await LGOnline.rpc_async("core.score_submit", {"board": "lap_%s" % layout.replace("-", "_"), "score": int(roundf(lap * 1000.0))})


# --- Network play ---------------------------------------------------------

func host_lan() -> bool:
	leave()
	var port := int(LGSettings.get_value("lan", "port"))
	var peer := LanNet.create_host(port, GameConfig.MAX_PLAYERS - 1)
	if peer == null:
		status.emit("Couldn't host on port %d. Is another game already hosting?" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_HOST
	lan_address = LanNet.local_address()
	join_code = JoinCode.encode(lan_address, port, port) if lan_address != "" else ""
	_apply_seats(1, _seat_payload())
	_beacon.start_advertising(_beacon_info(), int(LGSettings.get_value("lan", "beacon_port")))
	joined.emit()
	roster_changed.emit()
	return true


func browse_lan() -> void:
	_beacon.start_listening(int(LGSettings.get_value("lan", "beacon_port")))


func stop_browsing() -> void:
	if mode == Mode.NONE:
		_beacon.stop()


func join_lan(address: String, port: int) -> bool:
	leave()
	var peer := LanNet.create_client(address, port)
	if peer == null:
		status.emit("Couldn't reach %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_CLIENT
	status.emit("Connecting to %s..." % address)
	return true


func join_lan_code(code: String) -> bool:
	var port := int(LGSettings.get_value("lan", "port"))
	var target := JoinCode.decode(code, port)
	if target.is_empty():
		status.emit("That code doesn't look right.")
		return false
	return join_lan(target.ip, target.port)


func host_online() -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	var code: String = await LGOnline.host_room_async(GameConfig.GAME_ID)
	if code == "":
		status.emit(LGOnline.last_error)
		return false
	mode = Mode.ONLINE_HOST
	join_code = code
	_apply_seats(1, _seat_payload())
	joined.emit()
	roster_changed.emit()
	return true


func join_online(code: String) -> bool:
	if not LGOnline.is_valid_code(code):
		status.emit("Type the room code shown on the host's screen.")
		return false
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	if not await LGOnline.join_room_async(GameConfig.GAME_ID, code):
		var shown := LGOnline.normalize_code(code)
		if LGOnline.last_error == LGOnline.NO_ROOM:
			status.emit("No room with code %s. Check the code with the host." % shown)
		elif LGOnline.last_error.begins_with("room_full"):
			status.emit("Room %s is full." % shown)
		else:
			status.emit("Couldn't join room %s." % shown)
		return false
	mode = Mode.ONLINE_CLIENT
	join_code = LGOnline.normalize_code(code)
	# connected_to_server has already sent the hello: the bridge announced
	# the host while joining.
	return true


## Quick match: finds other players looking for a race, or races the AI if
## nobody turns up in time. Returns "lobby" (go there now), "joining" (wait
## for `joined` or `left`) or "" when it was cancelled or failed.
func quick_match() -> String:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return ""
	quick = true
	status.emit("Looking for players...")
	var role: String = await LGOnline.find_match_async(2, GameConfig.MAX_PLAYERS, QUICK_SEARCH_SECONDS)
	match role:
		"host":
			mode = Mode.ONLINE_HOST
			join_code = ""
			_apply_seats(1, _seat_payload())
			_begin_quick_countdown()
			joined.emit()
			roster_changed.emit()
			return "lobby"
		"guest":
			mode = Mode.ONLINE_CLIENT
			join_code = ""
			return "joining"
	quick = false
	if LGOnline.last_error == LGOnline.NO_MATCH:
		start_quick_solo()
		status.emit("Nobody else is looking right now, so it's you against the AI.")
		return "lobby"
	if LGOnline.last_error != LGOnline.CANCELLED:
		status.emit("Couldn't find a race: %s" % LGOnline.last_error)
	return ""


func cancel_quick_match() -> void:
	LGOnline.cancel_matchmaking()


## Quick match with nobody else around: this device against the AI.
func start_quick_solo() -> void:
	start_solo()
	quick = true
	_begin_quick_countdown()


func quick_seconds_left() -> float:
	if _quick_start_msec == 0:
		return 0.0
	return maxf(0.0, (_quick_start_msec - Time.get_ticks_msec()) / 1000.0)


func _begin_quick_countdown() -> void:
	_quick_target = randi_range(GameConfig.QUICK_MATCH_SIZE.x, GameConfig.QUICK_MATCH_SIZE.y)
	settings.grid = _quick_target
	settings.circuit = Circuits.ids()[randi() % Circuits.ids().size()]
	_quick_start_msec = Time.get_ticks_msec() + int(QUICK_COUNTDOWN * 1000.0)


func _process(_delta: float) -> void:
	if _quick_start_msec != 0 and is_host() and not in_match and quick_seconds_left() <= 0.0:
		_quick_start_msec = 0
		if LGScenes.is_busy():
			_quick_start_msec = Time.get_ticks_msec()
			return
		start_match()


func leave(reason := "") -> void:
	var was := mode
	get_tree().paused = false
	_beacon.stop()
	if is_online() or LGOnline.bridge:
		LGOnline.leave_room()
	elif multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players.clear()
	join_code = ""
	in_match = false
	match_config = {}
	loaded_peers.clear()
	races_played = 0
	quick = false
	_quick_start_msec = 0
	_quick_target = 0
	_pending_hello.clear()
	if was != Mode.NONE:
		left.emit(reason)


# --- Host: the lobby ------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	settings[key] = value
	_save_lobby_settings()
	_broadcast_roster()


func human_count() -> int:
	return players.size()


func can_start() -> bool:
	return is_host() and players.size() >= GameConfig.MIN_PLAYERS and not in_match


func start_blocker() -> String:
	return "" if players.size() >= GameConfig.MIN_PLAYERS else "Waiting for drivers."


## Host: deals out the weekend and tells everyone to load the circuit.
func start_match() -> void:
	if not can_start():
		return
	var people := []
	for id in players:
		var p: Dictionary = players[id]
		people.append({"id": id, "name": p.name, "team": p.team, "number": p.number, "peer": p.peer, "seat": p.seat})
	people.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var config := make_config(people, settings, "multiplayer" if mode != Mode.SOLO else "quick")
	_beacon.update_info({"state": "racing"})
	loaded_peers.clear()
	for peer_id in multiplayer.get_peers():
		if not _pending_hello.has(peer_id):
			_h_start_match.rpc_id(peer_id, config)
	_h_start_match(config)


## Host: everyone goes back to the lobby after a race.
func return_to_lobby() -> void:
	if not is_host() or LGScenes.is_busy():
		return
	get_tree().paused = false
	_beacon.update_info({"state": "lobby"})
	for peer_id in multiplayer.get_peers():
		_h_return_to_lobby.rpc_id(peer_id)
	_h_return_to_lobby()


## Host of an online room: reports the race to the game server for stats and
## leaderboards. Each device's first player is the signed-in account; AI
## drivers and split-screen guests aren't reported.
func report_race(results: Array) -> void:
	if mode != Mode.ONLINE_HOST or LGOnline.bridge == null or results.is_empty():
		return
	races_played += 1
	var reported := []
	for row in results:
		var id := int(row.id)
		var p: Dictionary = match_config.get("players_by_id", {}).get(id, players.get(id, {}))
		if bool(row.get("bot", true)) or p.is_empty() or int(p.get("seat", 0)) != 0:
			continue
		var uid := LGOnline.user_id_for_peer(int(p.peer))
		if uid == "":
			continue
		reported.append({
			"user_id": uid,
			"position": int(row.position),
			"won": int(row.position) == 1 and str(row.status) != "Retired",
			"podium": int(row.position) <= 3 and str(row.status) != "Retired",
			"pole": int(row.get("start", 0)) == 1,
			"fastest": bool(row.get("fastest", false)),
		})
	if reported.is_empty():
		return
	LGOnline.rpc_async("%s.race_report" % GameConfig.GAME_ID, {
		"match_id": LGOnline.bridge.match_id,
		"round": races_played,
		"circuit": str(match_config.get("circuit", "")),
		"players": reported,
	})


func report_loaded() -> void:
	if is_host():
		loaded_peers[1] = true
		peer_loaded.emit(1)
	else:
		_c_match_loaded.rpc_id(1)


# --- Network events -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_hello[id] = Time.get_ticks_msec()
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(_check_hello.bind(id))


func _check_hello(id: int) -> void:
	if _pending_hello.has(id):
		_pending_hello.erase(id)
		_kick(id, "No hello from this game version.")


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	if not is_host():
		if id == 1 and is_online():
			leave.call_deferred("The host left the race.")
		return
	var names := []
	for aid in players.keys():
		if int(players[aid].peer) == id:
			names.append(players[aid].name)
			players.erase(aid)
	loaded_peers.erase(id)
	if names.is_empty():
		return
	_broadcast_roster()
	status.emit("%s left." % " and ".join(names))
	var scene := get_tree().current_scene
	if in_match and scene and scene.has_method("on_player_left"):
		scene.on_player_left(id)


func _on_connected_to_server() -> void:
	_send_hello()


func _send_hello() -> void:
	local_seats[0].name = player_name()
	_c_hello.rpc_id(1, GameConfig.version(), GameConfig.PROTOCOL, _seat_payload())


func _on_connection_failed() -> void:
	status.emit("Couldn't connect to the host.")
	leave("Couldn't connect to the host.")


func _on_server_disconnected() -> void:
	leave("The host left the race.")


func _on_beacon_hosts(hosts: Array) -> void:
	hosts_found.emit(hosts.filter(_is_our_game))


func _is_our_game(h: Dictionary) -> bool:
	return str(h.get("game", "")) == GameConfig.GAME_ID


## A split-screen player's controller was unplugged: they leave their seat
## (between races; mid-race their car slows to a stop until it's back).
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or in_match:
		return
	var seat := seat_for_pad(device)
	if seat > 0:
		remove_local_seat(seat)
		status.emit("A controller was disconnected, so Player %d left." % (seat + 1))


# --- RPCs ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(version: String, protocol: int, seats: Array) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_hello.erase(id)
	if protocol != GameConfig.PROTOCOL:
		_kick(id, "This game is version %s. Update Race Day to race together." % GameConfig.version())
		return
	if in_match:
		_kick(id, "A race is already under way. Join after it ends.")
		return
	if players.size() >= GameConfig.MAX_PLAYERS:
		_kick(id, "This race is full.")
		return
	_apply_seats(id, seats)
	if _quick_start_msec != 0:
		_h_countdown.rpc_id(id, quick_seconds_left())
	var names := []
	for aid in players:
		if int(players[aid].peer) == id:
			names.append(players[aid].name)
	status.emit("%s joined." % " and ".join(names))
	if version != GameConfig.version():
		status.emit("%s has version %s (you have %s)." % [names[0] if not names.is_empty() else "A player", version, GameConfig.version()])


@rpc("any_peer", "reliable")
func _c_seats(seats: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and not in_match and not _pending_hello.has(id) and players.values().any(_peer_is.bind(id)):
		_apply_seats(id, seats)


func _peer_is(p: Dictionary, id: int) -> bool:
	return int(p.peer) == id


@rpc("any_peer", "reliable")
func _c_match_loaded() -> void:
	if is_host() and in_match:
		var id := multiplayer.get_remote_sender_id()
		loaded_peers[id] = true
		peer_loaded.emit(id)


@rpc("authority", "reliable")
func _h_roster(p_players: Dictionary, p_settings: Dictionary, p_code: String) -> void:
	var first := players.is_empty()
	players = p_players
	settings = p_settings
	join_code = p_code
	if first:
		joined.emit()
	roster_changed.emit()
	settings_changed.emit()


## Quick match: the first race starts by itself in this many seconds.
@rpc("authority", "reliable")
func _h_countdown(seconds: float) -> void:
	quick = true
	_quick_start_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	roster_changed.emit()


@rpc("authority", "reliable")
func _h_kicked(reason: String) -> void:
	leave(reason)
	LGScenes.change_scene(TITLE_SCENE)


@rpc("authority", "reliable")
func _h_start_match(config: Dictionary) -> void:
	in_match = true
	_quick_start_msec = 0
	match_config = config
	play_mode = str(config.get("mode", "multiplayer"))
	LGInput.filter_claimed_pads = false
	LGScenes.change_scene(RACE_SCENE, _setup_race.bind(config))


@rpc("authority", "reliable")
func _h_return_to_lobby() -> void:
	in_match = false
	match_config = {}
	LGScenes.change_scene(LOBBY_SCENE)


func _broadcast_roster() -> void:
	if not is_host():
		return
	if mode != Mode.SOLO and mode != Mode.NONE:
		for peer_id in multiplayer.get_peers():
			if not _pending_hello.has(peer_id):
				_h_roster.rpc_id(peer_id, players, settings, join_code)
	_beacon.update_info({"players": players.size()})
	roster_changed.emit()
	settings_changed.emit()


func _kick(id: int, reason: String) -> void:
	_h_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(_disconnect_peer.bind(id))


func _disconnect_peer(id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _unique_name(name: String) -> String:
	if name == "":
		name = "Driver"
	var names := []
	for p in players.values():
		names.append(p.name)
	var out := name
	var n := 2
	while out in names:
		out = "%s %d" % [name, n]
		n += 1
	return out


func _beacon_info() -> Dictionary:
	return {
		"game": GameConfig.GAME_ID,
		"version": GameConfig.version(),
		"protocol": GameConfig.PROTOCOL,
		"name": "%s's race" % player_name(),
		"port": int(LGSettings.get_value("lan", "port")),
		"players": players.size(),
		"max": GameConfig.MAX_PLAYERS,
		"state": "lobby",
		"code": join_code,
	}


## The lobby settings are remembered between runs.
func _load_lobby_settings() -> void:
	var saved = LGSettings.get_value("lobby", "settings", {})
	if saved is Dictionary:
		for k in saved:
			if settings.has(k):
				settings[k] = saved[k]


func _save_lobby_settings() -> void:
	LGSettings.set_value("lobby", "settings", settings.duplicate())
