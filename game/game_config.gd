class_name GameConfig
extends RefCounted
## Game-wide constants: identity, setting defaults and the input map.

const GAME_ID := "race-day"
const TITLE := "Race Day"

const SETTING_DEFAULTS := {
	"online": {
		"enabled": true,
		"host": OnlineServer.HOST,
		"port": OnlineServer.PORT,
		"scheme": OnlineServer.SCHEME,
		"server_key": OnlineServer.SERVER_KEY,
	},
}


static func version() -> String:
	return LGVersion.current()
