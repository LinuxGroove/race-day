extends Node
## Boots the game: settings, the launch ping, the input map, the theme and
## the window, then the title screen.
##
## Developer shortcuts (after `--`):
##   --quick                 straight into a Quick Race (no qualifying)
##   --circuit=greenfield    with --quick or --tt: the layout
##   --tt                    straight into Time Trial
##   --split                 with --quick: two players in split screen
##   --laps=3                with --quick
##   --set=camera/view=cockpit   any setting, for one run

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGLaunchPing.send(GameConfig.GAME_ID)
	LGPlaytest.setup(GameConfig.GAME_ID, GameConfig.PLAYTEST)
	LGInput.register_actions(GameConfig.ACTIONS, float(LGSettings.get_value("input", "stick_deadzone")))
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	get_window().title = GameConfig.TITLE
	var args := OS.get_cmdline_user_args()
	var circuit := ""
	var laps := 3
	for a in args:
		if a.begins_with("--circuit="):
			circuit = a.trim_prefix("--circuit=")
		elif a.begins_with("--laps="):
			laps = int(a.trim_prefix("--laps="))
	if circuit == "" or Circuits.info(circuit).is_empty():
		var cal := Circuits.calendar()
		circuit = cal[0] if not cal.is_empty() else Circuits.ids()[0]
	if "--tt" in args:
		Session.start_time_trial(circuit)
		return
	if "--quick" in args:
		Session.start_solo()
		if "--split" in args:
			Session.add_local_seat(0)
		var settings: Dictionary = Session.settings.duplicate()
		settings.circuit = circuit
		settings.laps = laps
		settings.qualifying = "none"
		Session.launch(Session.make_config(Session.local_people(), settings, "quick"))
		return
	LGScenes.change_scene("res://game/ui/title.tscn")
