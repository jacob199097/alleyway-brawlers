extends Node
## Opens the post-match screen with made-up results, to look at (or record) the Victory and
## Defeat reveals without playing a match. Offline, so nothing reaches the server.
## Run:  godot --path godot res://tests/post_match_preview.tscn -- [win|loss]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var won := args.is_empty() or args[0] != "loss"
	Game.offline = true
	var mvp_card: Dictionary = CardDB.get_card("card_nebu_009")
	Game.match_result = {
		"result": "win" if won else "loss", "player_morale": 2400 if won else 0, "opponent_morale": 0 if won else 1800,
		"turns": 9, "cards_played": 14, "match_id": "", "snapshot": null, "tutorial": false, "reason": "morale",
		"mvp": {"card": mvp_card, "damage": 4200, "owner": "player"} if not mvp_card.is_empty() else {},
	}
	Game.go("post_match")
