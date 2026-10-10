-- ============================================================
-- Card set — Lions (generated from CARD_CATALOG in client/scenes/DuelScene.js).
-- art_url is the card's game ID; the client loads assets/cards/<art_url>.png.
-- Safe to re-run: existing cards (matched by name) are updated in place.
-- ============================================================

INSERT INTO cards (name, clan, card_type, clan_tag, subtype, level, authority, attack, defense,
                   tribute_cost, rarity, effect_text, effect_key, art_url, flavour_text)
VALUES
    ('Eric', 'lion_pride', 'gang_member', 'lion', 'striver', 1, 1, 700, 600, 0, 1, 'When this card sends an opponent''s character to the Gutter: You can PROMOTE this card.', 'lion_clan_bonus', 'eric_lv1', 'I don''t follow footsteps. I leave my own.'),
    ('Eric Lv.2', 'lion_pride', 'gang_member', 'lion', 'striver', 2, 5, 1600, 1300, 0, 2, 'When this card sends an opponent''s character to the Gutter: You can PROMOTE this card.', 'lion_clan_bonus', 'eric_lv2', 'I don''t follow footsteps. I leave my own.'),
    ('Eric Lv.3', 'lion_pride', 'gang_member', 'lion', 'striver', 3, 8, 2600, 2000, 0, 3, 'When this card sends an opponent''s character to the Gutter: Draw 1 card.
At the start of your turn: gains +100 ATK for each other LIONS card you control.', 'eric_lv3_draw', 'eric_lv3', 'I don''t follow footsteps. I leave my own.'),
    ('Maya', 'lion_pride', 'gang_member', 'lion', 'striver', 1, 2, 900, 500, 0, 1, 'If you control another LIONS card with equal or higher Authority, you can PROMOTE this card.', 'lion_clan_bonus', 'maya_lv1', 'Loyalty isn''t given. It''s earned in the streets.'),
    ('Maya Lv.2', 'lion_pride', 'gang_member', 'lion', 'striver', 2, 5, 2000, 1500, 0, 2, 'At the start of your turn: if you control another LIONS card with equal or higher Authority, you can PROMOTE this card.', 'lion_clan_bonus', 'maya_lv2', 'Loyalty isn''t given. It''s earned in the streets.'),
    ('Maya Lv.3', 'lion_pride', 'gang_member', 'lion', 'striver', 3, 9, 2900, 2500, 0, 3, 'Once per turn: Choose 1 other LIONS card. It gains +400 ATK and +400 DEF until end of turn.', 'maya_lv3_buff', 'maya_lv3', 'Loyalty isn''t given. It''s earned in the streets.'),
    ('Pride Runner', 'lion_pride', 'gang_member', 'lion', 'striver', 1, 2, 1000, 500, 0, 1, 'While adjacent to another LIONS character, this card gains +400 ATK.', 'pride_runner_adjacency', 'pride_runner', 'One lion hunts. Two lions own the street.'),
    ('Lion Grunt', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 1, 700, 500, 0, 1, 'If you control another LIONS character, this card gains +300 ATK.', 'lion_grunt_synergy', 'lion_grunt', 'A lone lion prowls. A pack owns the block.'),
    ('Block Enforcer', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 3, 1300, 1500, 0, 2, 'Once per turn, when an allied LIONS would be targeted in a brawl, you may have this card become the target instead.', 'block_enforcer_redirect', 'block_enforcer', 'We hold the line. You handle the lion.'),
    ('Goldfang', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 4, 1700, 1400, 0, 2, 'If this card attacks a defending character, it gains +500 ATK during that brawl.', 'goldfang_attacker', 'goldfang', 'They hide behind defense. I break it, then I break them.'),
    ('Pride Lieutenant', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 5, 2300, 1900, 0, 3, 'When deployed: One other LIONS card gains +500 ATK until end of turn.', 'pride_lieutenant_deploy', 'pride_lieutenant', 'Strength is nothing without your people.'),
    ('Pride Mentor', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 5, 2100, 1800, 0, 3, 'Once per turn, when a LIONS Striver PROMOTES, draw 2 cards.', 'pride_mentor_draw', 'pride_mentor', 'Strength gets respect. Survival earns wisdom.'),
    ('Brutus', 'lion_pride', 'gang_member', 'lion', 'heavy', 1, 8, 2800, 2500, 0, 4, 'When this enters the grid: Choose 1 enemy character; it loses 700 ATK until the end of your opponent''s next turn.
When this defeats an opponent''s character: Your next LIONS attacker this turn gains +300 ATK.', 'brutus_enter', 'brutus', 'Strength leads. Loyalty follows. We finish.'),
    ('Hunter', 'lion_pride', 'gang_member', 'lion', 'striver', 1, 1, 800, 400, 0, 3, 'When this card attacks a Downed character: +500 ATK this Brawl.
When this card KOs a Downed character: PROMOTE this card.', 'hunter_lv1', 'hunter_lv1', 'The hunt never ends. Only the hunted changes.'),
    ('Hunter Lv.2', 'lion_pride', 'gang_member', 'lion', 'striver', 2, 5, 1900, 1000, 0, 3, 'When this card attacks a Downed character: +500 ATK this Brawl.
When this card KOs a character: Choose 1 enemy character → Down it.
When this card KOs a Downed character: PROMOTE this card.', 'hunter_lv2', 'hunter_lv2', 'The hunt never ends. Only the hunted changes.'),
    ('Hunter Lv.3', 'lion_pride', 'gang_member', 'lion', 'striver', 3, 9, 2700, 1900, 0, 3, 'When this card attacks a Downed character: +500 ATK this Brawl.
When this card KOs a character: Choose 1 enemy character → Down it.
When this card KOs a Downed character: It may attack again this turn.', 'hunter_lv3', 'hunter_lv3', 'The hunt never ends. Only the hunted changes.'),
    ('Debt Collector', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 3, 1400, 700, 0, 3, 'When this card Downs a character by battle: Your opponent discards 1 card.', 'debt_collector', 'debt_collector', 'Everyone pays. It''s just a matter of when.'),
    ('Bulwark', 'lion_pride', 'gang_member', 'lion', 'heavy', 1, 6, 2300, 2600, 0, 3, 'This card cannot be moved by enemy effects.
While this card is in play: Adjacent allies gain +400 DEF.
When this card is attacked: The attacking character loses 300 ATK during that Brawl.', 'bulwark', 'bulwark', 'The wall doesn''t move. The wall doesn''t break.'),
    ('Mauler', 'lion_pride', 'gang_member', 'lion', 'heavy', 1, 6, 2300, 2000, 0, 3, 'This card deals +500 ATK when attacking a Downed character.
When this card KOs a Downed character: All enemy characters in adjacent lanes take -500 DEF this turn.', 'mauler', 'mauler', 'Down doesn''t mean done. Until I say it does.'),
    ('Kingpin', 'lion_pride', 'gang_member', 'lion', 'brawler', 1, 4, 1800, 1000, 0, 4, 'While your opponent controls a Downed character: This card gains +400 ATK.', 'kingpin', 'kingpin', 'When they''re down, I take everything.'),
    ('Sovereign', 'lion_pride', 'gang_member', 'lion', 'heavy', 1, 10, 2900, 1800, 0, 5, 'When this card enters play: All enemy characters with 1500 DEF or less become Downed.
While your opponent controls a Downed character: This card gains +600 ATK.', 'sovereign', 'sovereign', 'Bow or break.'),
    ('King Roan', 'lion_pride', 'leader', 'lion', 'heavy', 1, 10, 3000, 3000, 0, 3, 'DORMANT: While Dormant, all LIONS characters you control gain +300 ATK with 2 or more LIONS on field.
AWAKEN: When you control 4+ LIONS characters OR your total Authority is 10+.', 'king_roan_leader', 'king_roan', 'A lion doesn''t ask for respect. He earns it. Then he takes more.'),
    ('Lion''s Ambush', 'lion_pride', 'ambush', 'lion', NULL, NULL, 2, NULL, NULL, 0, 2, 'Play when an opponent declares an attack. If they attack a LIONS character, that attacker loses 1000 ATK during this brawl.', 'lion_ambush', 'lion_ambush', NULL),
    ('No Witnesses', 'lion_pride', 'ambush', 'lion', NULL, NULL, 3, NULL, NULL, 0, 3, 'When an opponent brawls a LIONS character: Down the attacking character and negate their attack.', 'no_witnesses_ambush', 'no_witnesses', NULL),
    ('King''s Test', 'lion_pride', 'ambush', 'lion', NULL, NULL, 3, NULL, NULL, 0, 3, 'When a LIONS Striver would be destroyed in battle: Negate that destruction. If it survives, you may PROMOTE it at the start of your next turn.', 'kings_test', 'kings_test', NULL),
    ('Corner Deal', 'lion_pride', 'hustle', 'lion', NULL, NULL, 2, NULL, NULL, 0, 1, 'Draw 2 cards, then discard 1 card. If you control a Striver, you do not discard.', 'corner_deal', 'corner_deal', NULL),
    ('Blood Scent', 'lion_pride', 'hustle', 'lion', NULL, NULL, 3, NULL, NULL, 0, 2, 'Choose 1 LIONS Striver you control; its PROMOTE condition is treated as fulfilled this turn.', 'blood_scent', 'blood_scent', NULL),
    ('Lion Rescue', 'lion_pride', 'hustle', 'lion', NULL, NULL, 2, NULL, NULL, 0, 1, 'Choose 1 Downed LIONS character; Stand it.', 'lion_rescue', 'lion_rescue', NULL)
ON CONFLICT (name) DO UPDATE SET
    clan = EXCLUDED.clan, card_type = EXCLUDED.card_type, clan_tag = EXCLUDED.clan_tag,
    subtype = EXCLUDED.subtype, level = EXCLUDED.level, authority = EXCLUDED.authority,
    attack = EXCLUDED.attack, defense = EXCLUDED.defense, tribute_cost = EXCLUDED.tribute_cost,
    rarity = EXCLUDED.rarity, effect_text = EXCLUDED.effect_text, effect_key = EXCLUDED.effect_key,
    art_url = EXCLUDED.art_url, flavour_text = EXCLUDED.flavour_text;
