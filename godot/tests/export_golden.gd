extends SceneTree
## Records CPU-vs-CPU games on the Godot rules (decks, every action, every event) so the
## server's JavaScript rules can replay them and prove they match (shared/duel/engine.test.mjs).
## Run:  godot --headless --path godot --script res://tests/export_golden.gd -- <out.json> [games]
## Games 4, 10, 16, ... are 4-player free-for-alls and 5, 11, 17, ... 3-player ones (seats p1..p4).

const MAX_ACTIONS := 1500
# Odd-numbered games give every character one of these data effects (Card Forge building
# blocks) instead of its hand-written one, so both engines are checked on every block.
## The weekly challenges' rules (shared/challenges.js TWISTS)
const TWIST_RULES := [{"start_authority": 3}, {"start_morale": 3000}, {"opening_hand": 7}, {"pierce": true}]

const FX_SAMPLES := [
	# Only ones with a status / in DEF; REWIND, JAM, BARRICADE; chains that remove what they aim at
	[{"when": "attack", "do": "ko", "target": "enemy", "only": "statused"}, {"when": "deploy", "do": "poison", "target": "enemy", "amount": 100}],
	[{"when": "deploy", "do": "bounce", "target": "enemies", "only": "def"}, {"when": "turn_start", "do": "force_def", "target": "enemy"}],
	[{"when": "turn_start", "do": "rewind", "target": "enemies"}, {"when": "deploy", "do": "buff", "target": "allies", "atk": 400, "until": "forever"}],
	[{"when": "deploy", "do": "buff", "target": "allies", "atk": 500, "until": "forever"}, {"when": "attack", "do": "rewind", "target": "enemy"}],
	[{"when": "turn_start", "do": "buff", "target": "self", "atk": 200, "def": 200, "until": "forever"}, {"when": "defend", "do": "rewind", "target": "attacker"}],
	[{"when": "deploy", "do": "jam"}, {"when": "turn_end", "do": "barricade", "amount": 600}],
	[{"when": "foe_ko", "do": "ko", "target": "enemies", "once": true}, {"when": "attack", "do": "bounce", "target": "enemies"}],
	# Cleanse (allies at the start of the turn; itself when attacked)
	[{"when": "turn_start", "do": "cleanse", "target": "allies"}, {"when": "deploy", "do": "stasis", "target": "enemy"}],
	[{"when": "defend", "do": "cleanse", "target": "self"}, {"when": "deploy", "do": "poison", "target": "enemies", "amount": 200}],
	# Top of the deck, loot, exile, swapped ATK / DEF, lifesteal, bounties
	[{"when": "deploy", "do": "topdeck", "target": "enemy"}, {"when": "ko", "do": "loot", "amount": 1}],
	[{"when": "deploy", "do": "loot", "amount": 2, "discard_n": 1}, {"when": "turn_end", "do": "loot", "amount": 1, "discard_n": 0}],
	[{"when": "deploy", "do": "exile", "target": "enemy", "if": "foe_downed"}, {"when": "passive", "do": "lifesteal"}],
	[{"when": "attack", "do": "swap", "target": "enemies", "until": "turn"}],
	[{"when": "deploy", "do": "bounty", "target": "enemies", "amount": 1}, {"when": "passive", "do": "lifesteal"}],
	[{"when": "turn_start", "do": "swap", "target": "self", "until": "turn", "luck": "coin"}],
	# Luck: a coin flip (and what happens on tails), a die per pip, a die needing 4+
	[{"when": "deploy", "do": "down", "target": "enemy", "luck": "coin"}, {"when": "deploy", "do": "draw", "amount": 1, "if_luck": "lost"}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 150, "per": "roll"}],
	[{"when": "turn_start", "do": "damage", "amount": 400, "luck": "die", "luck_on": 4}],
	[{"when": "defend", "do": "buff", "target": "self", "def": 600, "luck": "coin"}],
	[{"when": "ko", "do": "heal", "amount": 100, "luck": "die", "per": "roll"}],
	# Destroying face-up Continuous / Equip cards (shatter), and face-down ones (break_ambush)
	[{"when": "deploy", "do": "shatter", "amount": 2}, {"when": "ko", "do": "break_ambush", "amount": 1}],
	[{"when": "deploy", "do": "wreck", "amount": 1}],
	# CHARM (take control for the turn), UNDEAD (rises once), PROMOTE one of your Strivers, a Heavy's
	# tribute damage, "that character" (the one just deployed)
	[{"when": "deploy", "do": "charm", "target": "enemy"}],
	[{"when": "passive", "do": "undead"}, {"when": "attack", "do": "buff", "target": "self", "atk": 200}],
	[{"when": "activate", "do": "promote_ally", "target": "ally"}],
	[{"when": "deploy", "do": "tribute_damage"}, {"when": "passive", "do": "undead"}],
	[{"when": "foe_deployed", "do": "swap", "target": "deployed", "until": "turn"}],
	[{"when": "ally_deployed", "do": "charm", "target": "enemy", "once": true}],
	# Underworld: give UNDEAD, raise from the enemy's Gutter, exile Gutter cards (effect and Activate cost),
	# the enemy's Gutter as a condition / "for each"
	[{"when": "deploy", "do": "give_undead", "target": "ally"}],
	[{"when": "deploy", "do": "revive", "from": "foe"}],
	[{"when": "turn_end", "do": "exile_gutter", "amount": 2}],
	[{"when": "activate", "do": "damage", "amount": 400, "cost": "exile_gutter", "cost_n": 2}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 100, "per": "foe_gutter"}],
	[{"when": "turn_start", "do": "drain", "amount": 300, "if": "foe_gutter_ge", "n": 3}],
	# Set stats: ATK / DEF become a number (this turn, or for good)
	[{"when": "deploy", "do": "set_stats", "target": "enemy", "atk": 100, "def": 100, "until": "turn"}],
	[{"when": "defend", "do": "set_stats", "target": "attacker", "atk": 100, "until": "forever"}],
	# Wildcard: DOUBLE OR NOTHING, and LOADED DICE (a lost flip or roll tried again, once a turn)
	[{"when": "deploy", "do": "damage", "amount": 300, "luck": "double"}, {"when": "deploy", "do": "draw", "amount": 1, "if_luck": "lost"}],
	[{"when": "passive", "do": "loaded"}, {"when": "turn_start", "do": "buff", "target": "self", "atk": 300, "until": "turn", "luck": "die", "luck_on": 5}],
	[{"when": "deploy", "do": "buff", "target": "ally", "atk": 500}],
	[{"when": "deploy", "do": "down", "target": "enemy"}],
	[{"when": "deploy", "do": "buff", "target": "enemies", "atk": -300, "until": "next_turn"}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 400}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 600, "if": "vs_def"}],
	[{"when": "ko", "do": "draw", "amount": 1}],
	[{"when": "down", "do": "discard", "amount": 1}],
	[{"when": "ko", "do": "attack_again", "if": "vs_downed"}],
	[{"when": "turn_start", "do": "heal", "amount": 300}],
	[{"when": "deploy", "do": "damage", "amount": 200}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 300, "if": "allies", "n": 1}],
	[{"when": "passive", "do": "buff", "target": "allies", "def": 200, "clan": "nebula"}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 400, "if": "adjacent"}],
	[{"when": "passive", "do": "pierce"}, {"when": "passive", "do": "double_attack"}],
	[{"when": "passive", "do": "guard"}, {"when": "passive", "do": "no_down"}],
	[{"when": "passive", "do": "untargetable"}, {"when": "passive", "do": "immune"}],
	[{"when": "passive", "do": "cost_down", "amount": 1}],
	[{"when": "passive", "do": "cost_down", "amount": 2, "clan": "nebula", "if": "allies", "n": 1}],
	[{"when": "passive", "do": "buff", "target": "enemies", "atk": -300}],
	[{"when": "passive", "do": "guard", "if": "foe_downed"}, {"when": "deploy", "do": "poison", "target": "enemies", "amount": 200}],
	[{"when": "down", "do": "promote"}],
	[{"when": "down", "do": "promote", "times": 2}],
	[{"when": "ko", "do": "draw", "amount": 1, "times": 2}],
	[{"when": "deploy", "do": "down", "target": "enemies", "if": "foe_downed"}],
	[{"when": "attack", "do": "draw", "amount": 1}, {"when": "deploy", "do": "buff", "target": "self", "def": 300}],
	[{"when": "defend", "do": "buff", "target": "self", "atk": 300, "def": 500}],
	[{"when": "defend", "do": "stun", "target": "attacker"}],
	[{"when": "defend", "do": "bounce", "target": "attacker", "if": "vs_atk"}],
	[{"when": "direct", "do": "draw", "amount": 1}, {"when": "direct", "do": "mill", "amount": 2}],
	[{"when": "self_downed", "do": "damage", "amount": 300}],
	[{"when": "self_ko", "do": "buff", "target": "allies", "atk": 300, "until": "next_turn"}],
	[{"when": "self_ko", "do": "recover", "kind": "gang_member"}],
	[{"when": "ally_deployed", "do": "heal", "amount": 200, "once": true}],
	[{"when": "ally_deployed", "do": "buff", "target": "self", "atk": 200, "clan": "nebula"}],
	[{"when": "turn_end", "do": "shield", "target": "self", "once": true}],
	[{"when": "turn_end", "do": "stand", "target": "allies"}],
	[{"when": "deploy", "do": "ko", "target": "enemy", "if": "enemies_ge", "n": 2}],
	[{"when": "deploy", "do": "force_def", "target": "enemies"}],
	[{"when": "deploy", "do": "search", "kind": "gang_member"}, {"when": "turn_start", "do": "authority", "amount": 1, "if": "hand_le", "n": 3}],
	[{"when": "attack", "do": "pierce"}, {"when": "ko", "do": "drain", "amount": 200}],
	[{"when": "turn_start", "do": "heal", "amount": 400, "if": "morale_le", "n": 3000}, {"when": "deploy", "do": "damage", "amount": 300, "if": "foe_morale_le", "n": 4000}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 500, "if": "alone"}, {"when": "turn_start", "do": "draw", "if": "gutter_ge", "n": 4, "once": true}],
	[{"when": "passive", "do": "buff", "target": "self", "def": 400, "if": "leader_dormant"}, {"when": "deploy", "do": "stun", "target": "enemies"}],
	[{"when": "deploy", "do": "shield", "target": "ally"}, {"when": "deploy", "do": "bounce", "target": "enemy", "if": "foe_downed"}],
	[{"when": "deploy", "do": "poison", "target": "enemy", "amount": 300}],
	[{"when": "deploy", "do": "burn", "target": "enemies", "amount": 200}],
	[{"when": "defend", "do": "bleed", "target": "attacker", "amount": 200}, {"when": "attack", "do": "poison", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "shock", "target": "enemy", "amount": 900}],
	[{"when": "attack", "do": "shock", "target": "enemies", "amount": 400}, {"when": "self_ko", "do": "burn", "target": "enemies", "amount": 300}],
	[{"when": "deploy", "do": "freeze", "target": "enemy"}],
	[{"when": "defend", "do": "freeze", "target": "attacker"}, {"when": "deploy", "do": "bleed", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "stasis", "target": "enemy"}],
	[{"when": "turn_end", "do": "stasis", "target": "self", "once": true, "if": "morale_le", "n": 3000}, {"when": "passive", "do": "buff", "target": "self", "atk": 300}],
	[{"when": "defend", "do": "down", "target": "attacker", "if": "vs_def"}, {"when": "defend", "do": "ko", "target": "attacker", "once": true, "if": "vs_downed"}],
	[{"when": "deploy", "do": "search", "max_auth": 3, "choose": true}],
	[{"when": "deploy", "do": "search", "kind": "gang_member", "role": "striver", "level": 1, "amount": 2}],
	[{"when": "deploy", "do": "search", "name": "pride"}, {"when": "attack", "do": "buff", "target": "self", "atk": 300, "if": "leader_awake"}],
	[{"when": "self_ko", "do": "revive", "max_auth": 4}],
	[{"when": "deploy", "do": "revive", "choose": true, "if": "gutter_ge", "n": 2}],
	[{"when": "deploy", "do": "break_ambush", "amount": 1}],
	[{"when": "foe_deployed", "do": "buff", "target": "self", "atk": 200, "until": "turn"}],
	[{"when": "hustle_played", "do": "heal", "amount": 200}, {"when": "turn_start", "do": "damage", "amount": 100, "if": "hand_ge", "n": 3}],
	[{"when": "deploy", "do": "recover", "role": "brawler", "amount": 2, "choose": true}],
	[{"when": "passive", "do": "immune"}, {"when": "attack", "do": "pierce", "if": "leader_dormant"}],
	[{"when": "deploy", "do": "down", "target": "enemy", "clan": "nebula", "if": "adjacent", "if_clan": ""}],
	[{"when": "direct", "do": "attack_again"}, {"when": "attack", "do": "attack_again"}],
	[{"when": "attack", "do": "promote", "times": 2, "if": "vs_downed"}, {"when": "defend", "do": "draw", "amount": 1, "times": 2}],
	[{"when": "attack", "do": "draw", "amount": 1, "times": 3}],
	[{"when": "passive", "do": "immune", "statuses": ["poison", "stun"]}, {"when": "deploy", "do": "burn", "target": "enemies", "amount": 100}],
	[{"when": "deploy", "do": "silence", "target": "enemy"}, {"when": "turn_start", "do": "ramp", "amount": 1, "if": "authority_ge", "n": 3, "once": true}],
	[{"when": "passive", "do": "elusive"}, {"when": "deploy", "do": "break_ambush", "if": "foe_ambush"}],
	[{"when": "turn_start", "do": "influence", "amount": 500}, {"when": "deploy", "do": "discard", "amount": 1, "if": "foe_hand_le", "n": 3}],
	[{"when": "turn_end", "do": "stand", "target": "allies", "if": "ally_downed"}, {"when": "defend", "do": "silence", "target": "attacker", "until": "next_turn"}],
	[{"when": "ally_deployed", "do": "buff", "target": "allies", "atk": 200, "clan": "", "when_clan": "nebula"}, {"when": "passive", "do": "buff", "target": "self", "atk": 300, "if": "allies", "n": 2, "if_clan": "nebula", "clan": ""}],
	[{"when": "ko", "do": "buff", "target": "self", "atk": 300, "until": "forever"}, {"when": "ally_ko", "do": "buff", "target": "self", "atk": 400, "def": 200, "until": "forever"}],
	[{"when": "activate", "do": "stand", "target": "ally"}, {"when": "activate", "do": "buff", "target": "self", "atk": 500, "cost": "authority", "cost_n": 1}],
	[{"when": "activate", "do": "draw", "amount": 1, "cost": "discard", "cost_n": 1}, {"when": "activate", "do": "damage", "amount": 300, "cost": "morale", "cost_n": 200}],
	[{"when": "activate", "do": "ready", "target": "ally"}, {"when": "ally_ko", "do": "draw", "amount": 1, "once": true}],
	[{"when": "activate", "do": "buff", "target": "allies", "atk": 300, "cost": "exhaust"}, {"when": "passive", "do": "guard"}],
	[{"when": "deploy", "do": "suppress", "target": "enemy", "amount": 400}, {"when": "defend", "do": "suppress", "target": "attacker", "amount": 300}],
	[{"when": "attack", "do": "suppress", "target": "enemies", "amount": 200, "if": "self_atk"}, {"when": "foe_ko", "do": "heal", "amount": 200}],
	[{"when": "deploy", "do": "force_atk", "target": "enemies"}, {"when": "foe_turn_end", "do": "buff", "target": "self", "def": 300, "until": "next_turn", "if": "self_def"}],
	[{"when": "turn_start", "do": "draw", "amount": 1, "if": "turn_ge", "n": 6}, {"when": "deploy", "do": "damage", "amount": 300, "if": "enemies_le", "n": 1}],
	[{"when": "turn_start", "do": "heal", "amount": 300, "if": "deck_le", "n": 20}, {"when": "foe_ko", "do": "buff", "target": "self", "atk": 200, "until": "forever"}],
	[{"when": "passive", "do": "buff", "target": "allies", "atk": 200, "clan": "nebula", "if": "allies", "n": 2, "if_clan": "nebula"}, {"when": "turn_start", "do": "draw", "amount": 1, "if": "allies_le", "n": 1, "if_clan": "nebula"}],
	[{"when": "attack", "do": "buff", "target": "self", "atk": 300, "if": "hand_ge", "n": 2, "if_clan": "nebula"}, {"when": "turn_end", "do": "heal", "amount": 200, "if": "gutter_ge", "n": 3, "if_clan": "nebula"}],
	[{"when": "turn_start", "do": "stand", "target": "ally", "if": "ally_downed", "if_clan": "nebula"}],
	[{"when": "passive", "do": "buff", "target": "self", "atk": 100, "per": "allies", "per_clan": "nebula"}, {"when": "deploy", "do": "damage", "amount": 100, "per": "enemies", "per_max": 3}],
	[{"when": "ally_attacked", "do": "suppress", "target": "attacker", "amount": 300, "once": true}, {"when": "attack", "do": "buff", "target": "self", "atk": 200, "per": "foe_downed"}],
	[{"when": "deploy", "do": "draw", "amount": 1, "or": true, "label": "Draw 1 card"}, {"when": "deploy", "do": "suppress", "target": "enemy", "amount": 300, "label": "SUPPRESS one enemy for 300"}],
	[{"when": "deploy", "do": "call", "amount": 1, "max_auth": 3}, {"when": "defend", "do": "buff", "target": "self", "def": 100, "per": "hand", "per_max": 5}],
	[{"when": "turn_start", "do": "token", "token": "card_nebu_036", "amount": 2, "once": true}, {"when": "ally_attacked", "do": "buff", "target": "ally", "def": 300}],
	[{"when": "ko", "do": "buff", "target": "allies", "atk": 100, "until": "turn", "per": "gutter"}, {"when": "deploy", "do": "down", "target": "enemy", "or": true, "label": "Down an enemy"}, {"when": "deploy", "do": "heal", "amount": 500, "label": "Heal 500"}],
	# "If you do": only if the effect before did something (after its target is chosen)
	[{"when": "activate", "cost": "authority", "cost_n": 1, "do": "break_ambush", "amount": 1}, {"when": "activate", "do": "promote", "target": "self", "if_done": true}],
	[{"when": "deploy", "do": "ko", "target": "enemy"}, {"when": "deploy", "do": "draw", "amount": 1, "if_done": true}, {"when": "deploy", "do": "heal", "amount": 300, "if_done": true}],
	[{"when": "attack", "do": "down", "target": "enemy"}, {"when": "attack", "do": "buff", "target": "self", "atk": 300, "if_done": true}],
	[{"when": "deploy", "do": "search", "kind": "gang_member", "choose": true}, {"when": "deploy", "do": "suppress", "target": "enemy", "amount": 200, "if_done": true}],
	# Every character on the field, both sides (not this card)
	[{"when": "deploy", "do": "down", "target": "all"}],
	[{"when": "activate", "do": "down", "target": "all", "cost": "authority", "cost_n": 1}, {"when": "ko", "do": "buff", "target": "all", "atk": -200, "until": "next_turn"}],
]


## Effects for Hustles (happen when played) and Ambushes (happen when sprung) in odd games.
const FX_CARD_SAMPLES := [
	[{"do": "draw", "amount": 2}],
	[{"do": "damage", "amount": 400}, {"do": "heal", "amount": 200}],
	[{"do": "buff", "target": "allies", "atk": 300}],
	[{"do": "down", "target": "enemy"}],
	[{"do": "poison", "target": "enemies", "amount": 200}],
	[{"do": "stasis", "target": "ally"}, {"do": "search", "kind": "gang_member"}],
	[{"do": "buff", "target": "attacker", "atk": -1200}],
	# An Ambush that negates the attack (on a Hustle it does nothing); one whose choice comes before the brawl;
	# a coin on the attacker's ATK, and on tails the attack is negated instead
	[{"do": "negate"}, {"do": "draw", "amount": 1}],
	[{"do": "buff", "target": "enemy", "atk": -1500, "until": "turn"}],
	[{"do": "freeze", "target": "enemy", "negate": true}],
	[{"do": "charm", "target": "enemy"}, {"do": "draw", "amount": 1}],
	[{"do": "promote_ally", "target": "ally"}],
	[{"do": "give_undead", "target": "allies"}],
	[{"do": "revive", "from": "foe"}, {"do": "exile_gutter", "amount": 1}],
	[{"do": "buff", "target": "attacker", "atk": -800, "luck": "coin"}, {"do": "negate", "if_luck": "lost"}],
	[{"do": "down", "target": "attacker"}],
	[{"do": "bounce", "target": "attacker", "if": "vs_atk"}, {"do": "draw", "amount": 1}],
	[{"do": "freeze", "target": "attacker"}, {"do": "shock", "target": "enemy", "amount": 700}],
	[{"do": "stand", "target": "allies"}, {"do": "shield", "target": "ally"}],
	[{"do": "revive", "choose": true}],
	[{"do": "down", "target": "all"}],
	[{"do": "break_ambush", "amount": 2}],
	[{"do": "search", "kind": "gang_member", "max_auth": 2, "amount": 2}],
	[{"do": "draw", "amount": 1, "or": true, "label": "Draw 1"}, {"do": "token", "token": "card_nebu_036", "amount": 1, "label": "A token"}],
	[{"do": "damage", "amount": 100, "per": "foe_downed"}, {"do": "call", "choose": true}],
]


## Continuous / Equip Hustles and Ambushes (merged over the card) for a third of them in odd games.
const HUSTLE_LASTING := [
	{"subtype": "continuous", "effects": [{"when": "passive", "do": "buff", "target": "allies", "atk": 200},
		{"when": "turn_start", "do": "heal", "amount": 200}, {"when": "deploy", "do": "draw", "amount": 1}]},
	{"subtype": "equip", "effects": [{"when": "passive", "do": "buff", "target": "self", "atk": 500}, {"when": "passive", "do": "pierce"}]},
	{"subtype": "equip", "equip_to": "enemy", "effects": [{"when": "passive", "do": "buff", "target": "self", "atk": -400}]},
	{"subtype": "continuous", "effects": [{"when": "ally_deployed", "do": "buff", "target": "allies", "atk": 100, "until": "turn"},
		{"when": "foe_ko", "do": "draw", "amount": 1}, {"when": "passive", "do": "untargetable"}, {"when": "passive", "do": "cost_down", "amount": 1}]},
]
const AMBUSH_LASTING := [
	{"subtype": "continuous", "effects": [{"when": "defend", "do": "suppress", "target": "attacker", "amount": 300},
		{"when": "passive", "do": "buff", "target": "enemies", "atk": -200}, {"when": "turn_end", "do": "damage", "amount": 100}]},
	{"subtype": "continuous", "effects": [{"when": "defend", "do": "set_stats", "target": "attacker", "atk": 100, "def": 100, "until": "forever"},
		{"when": "turn_end", "do": "set_stats", "target": "enemy", "def": 0, "until": "next_turn"}]},
]


## Card Forge leaders for every fourth game (merged over the leader card).
const LEADER_SAMPLES := [
	{"effectKey": "", "awakenCondition": {"chars": 3, "influence": 1500, "ready": true}, "effects": [
		{"when": "dormant", "do": "buff", "target": "allies", "atk": 200}, {"when": "dormant", "do": "pierce"},
		{"when": "dormant_turn_start", "do": "heal", "amount": 200}, {"when": "dormant_hit", "do": "draw", "amount": 1},
		{"when": "awaken", "do": "down", "target": "enemy"}]},
	{"effectKey": "", "awakenCondition": {"authority": 6, "gutter": 4}, "effects": [
		{"when": "dormant", "do": "cost_down", "amount": 1}, {"when": "dormant", "do": "immune"},
		{"when": "dormant_ally_deployed", "do": "damage", "amount": 100, "once": true},
		{"when": "dormant_foe_deployed", "do": "buff", "target": "enemies", "atk": -200},
		{"when": "dormant_hustle", "do": "draw", "amount": 1}, {"when": "awaken", "do": "search", "max_auth": 4, "choose": true},
		{"when": "passive", "do": "buff", "target": "allies", "atk": 300}]},
	{"effectKey": "", "awakenCondition": {"morale": 4000, "foe_morale": 2500}, "effects": [
		{"when": "dormant", "do": "untargetable"}, {"when": "dormant", "do": "buff", "target": "enemies", "def": -300},
		{"when": "dormant_turn_end", "do": "stand", "target": "allies"}, {"when": "awaken", "do": "revive"},
		{"when": "attack", "do": "buff", "target": "self", "atk": 500}]},
	# Underworld: your characters have UNDEAD (and LIFESTEAL) while it's Dormant
	{"effectKey": "", "awakenCondition": {"gutter": 5}, "effects": [
		{"when": "dormant", "do": "undead"}, {"when": "dormant", "do": "lifesteal"},
		{"when": "awaken", "do": "revive", "from": "foe"}]},
	# Wildcard: Awakens after 3 won flips / rolls; flips a coin every turn while it waits
	{"effectKey": "", "awakenCondition": {"luck": 3}, "effects": [
		{"when": "dormant_turn_start", "do": "draw", "amount": 1, "luck": "coin"},
		{"when": "dormant_turn_start", "do": "heal", "amount": 200, "if_luck": "lost"},
		{"when": "awaken", "do": "damage", "amount": 300, "luck": "double"}]},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://golden.json"
	var games := int(args[1]) if args.size() > 1 else 25
	var rng := RandomNumberGenerator.new()
	var records: Array = []
	for g in games:
		rng.seed = 1000 + g
		var seats: Array = ["player", "opponent"]
		if g % 6 == 4:
			seats = ["p1", "p2", "p3", "p4"]
		elif g % 6 == 5:
			seats = ["p1", "p2", "p3"]
		var base := DuelAI.test_setup()
		var setup := {"decks": {}, "hideouts": {}, "leaders": {}}
		for side in seats:
			setup.decks[side] = base.decks.player.duplicate(true)
			setup.hideouts[side] = base.hideouts.player.duplicate(true)
			setup.leaders[side] = base.leaders.player
			_shuffle(setup.decks[side], rng)
		if g % 2 == 1:
			for side in seats:
				var deck: Array = setup.decks[side]
				for i in deck.size():
					var kind: String = CardDB.get_card(deck[i]).get("cardType", "")
					if kind == "gang_member":
						var heavy: bool = CardDB.get_card(deck[i]).get("subtype", "") == "heavy"
						deck[i] = {"id": deck[i], "effectKey": "", "effects": FX_SAMPLES[rng.randi_range(0, FX_SAMPLES.size() - 1)]}
						if heavy:
							deck[i].tributeCost = 1 + i % 3   # Heavies that sacrifice 1, 2 or 3
					elif kind in ["hustle", "ambush"] and rng.randi_range(0, 2) == 0:
						var pool: Array = HUSTLE_LASTING if kind == "hustle" else AMBUSH_LASTING
						var spec: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
						spec.id = deck[i]
						spec.effectKey = ""
						deck[i] = spec
					elif kind in ["hustle", "ambush"]:
						deck[i] = {"id": deck[i], "effectKey": "", "effects": FX_CARD_SAMPLES[rng.randi_range(0, FX_CARD_SAMPLES.size() - 1)]}
		var first: String = seats[g % seats.size()] if seats.size() > 2 else ("player" if g % 2 == 0 else "opponent")
		var levels := {}
		for i in seats.size():
			levels[seats[i]] = DuelAI.LEVELS[(g + i) % 3]
		# Every fifth game is played with a weekly-challenge twist (shared/challenges.js)
		var rules: Dictionary = TWIST_RULES[(g / 5) % TWIST_RULES.size()] if g % 5 == 2 else {}
		var d := DuelState.new(setup.decks, setup.hideouts, setup.leaders, first, -1, rules)
		# Every fourth game the leaders are Card Forge leaders (Dormant / Awaken effects)
		var leader_fx := {}
		if g % 4 == 3:
			for i in seats.size():
				var side: String = seats[i]
				if d.sides[side].leader != null:
					leader_fx[side] = LEADER_SAMPLES[(g / 4 + i) % LEADER_SAMPLES.size()]
					d.sides[side].leader.merge(leader_fx[side].duplicate(true), true)
		d.start()
		var steps: Array = [{"action": null, "side": "", "events": d.take_events()}]
		var n := 0
		while d.winner == "" and n < MAX_ACTIONS * (2 if seats.size() > 2 else 1):
			var side: String = d.pending.side if not d.pending.is_empty() else d.active
			var a := DuelAI.choose(d, side, levels[side])
			if a.is_empty() or not d.do_action(side, a):
				push_error("refused action in game %d" % g)
				break
			steps.append({"action": a, "side": side, "events": d.take_events()})
			n += 1
		records.append({"decks": setup.decks, "hideouts": setup.hideouts, "leaders": setup.leaders, "leader_fx": leader_fx, "rules": rules,
			"first": first, "levels": levels, "steps": steps, "winner": d.winner})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(records))
	f.close()
	print("wrote %d games to %s" % [games, out_path])
	quit()


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
