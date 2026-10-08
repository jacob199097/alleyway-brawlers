'use strict';

/**
 * DUEL SOCKET HANDLER
 * Handles all in-match game events relayed between the two clients.
 * The server acts as the authority — it validates every action before
 * broadcasting the result to both players.
 *
 * Events handled:
 *   Client → Server:  'duel:playCard', 'duel:attack', 'duel:phaseAdvance',
 *                     'duel:activateTrap', 'duel:endTurn'
 *   Server → Clients: 'duel:stateUpdate', 'duel:attacked', 'duel:cardPlayed',
 *                     'duel:phaseChanged', 'duel:matchOver'
 */

const { getMatch, removeMatch } = require('./matchmaker');
const { resolveMatch }          = require('../economy/postMatch');

// ── Shared card catalog (server-side promoted forms) ──────────────────────────
const CARD_CATALOG = {
    'eric_lv1':         { id: 'eric_lv1',         name: 'Eric',             clan: 'iron_saints', cardType: 'gang_member', authority: 1,  attack: 700,  defense: 600,  level: 1, rarity: 1, subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus',          promotesTo: 'eric_lv2' },
    'eric_lv2':         { id: 'eric_lv2',         name: 'Eric Lv.2',        clan: 'iron_saints', cardType: 'gang_member', authority: 5,  attack: 1600, defense: 1300, level: 2, rarity: 2, subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus',          promotesTo: 'eric_lv3' },
    'eric_lv3':         { id: 'eric_lv3',         name: 'Eric Lv.3',        clan: 'iron_saints', cardType: 'gang_member', authority: 8,  attack: 2600, defense: 2000, level: 3, rarity: 3, subtype: 'striver', clanTag: 'lion', effectKey: 'eric_lv3_draw',            promotesTo: null },
    'maya_lv1':         { id: 'maya_lv1',         name: 'Maya',             clan: 'iron_saints', cardType: 'gang_member', authority: 2,  attack: 900,  defense: 500,  level: 1, rarity: 1, subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus',          promotesTo: 'maya_lv2' },
    'maya_lv2':         { id: 'maya_lv2',         name: 'Maya Lv.2',        clan: 'iron_saints', cardType: 'gang_member', authority: 5,  attack: 2000, defense: 1500, level: 2, rarity: 2, subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus',          promotesTo: 'maya_lv3' },
    'maya_lv3':         { id: 'maya_lv3',         name: 'Maya Lv.3',        clan: 'iron_saints', cardType: 'gang_member', authority: 9,  attack: 2900, defense: 2500, level: 3, rarity: 3, subtype: 'striver', clanTag: 'lion', effectKey: 'maya_lv3_buff',            promotesTo: null },
    'pride_runner':     { id: 'pride_runner',     name: 'Pride Runner',     clan: 'iron_saints', cardType: 'gang_member', authority: 2,  attack: 1000, defense: 500,  level: 1, rarity: 1, subtype: 'striver', clanTag: 'lion', effectKey: 'pride_runner_adjacency',   promotesTo: null },
    'lion_grunt':       { id: 'lion_grunt',       name: 'Lion Grunt',       clan: 'iron_saints', cardType: 'gang_member', authority: 1,  attack: 700,  defense: 500,  level: 1, rarity: 1, subtype: 'brawler', clanTag: 'lion', effectKey: 'lion_grunt_synergy',       promotesTo: null },
    'block_enforcer':   { id: 'block_enforcer',   name: 'Block Enforcer',   clan: 'iron_saints', cardType: 'gang_member', authority: 3,  attack: 1300, defense: 1500, level: 1, rarity: 2, subtype: 'brawler', clanTag: 'lion', effectKey: 'block_enforcer_redirect',  promotesTo: null },
    'goldfang':         { id: 'goldfang',         name: 'Goldfang',         clan: 'iron_saints', cardType: 'gang_member', authority: 4,  attack: 1700, defense: 1400, level: 1, rarity: 2, subtype: 'brawler', clanTag: 'lion', effectKey: 'goldfang_attacker',        promotesTo: null },
    'pride_lieutenant': { id: 'pride_lieutenant', name: 'Pride Lieutenant', clan: 'iron_saints', cardType: 'gang_member', authority: 5,  attack: 2300, defense: 1900, level: 1, rarity: 3, subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_lieutenant_deploy',  promotesTo: null },
    'pride_mentor':     { id: 'pride_mentor',     name: 'Pride Mentor',     clan: 'iron_saints', cardType: 'gang_member', authority: 5,  attack: 2100, defense: 1800, level: 1, rarity: 3, subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_mentor_draw',        promotesTo: null },
    'brutus':           { id: 'brutus',           name: 'Brutus',           clan: 'iron_saints', cardType: 'gang_member', authority: 8,  attack: 2800, defense: 2500, level: 1, rarity: 4, subtype: 'heavy',   clanTag: 'lion', effectKey: 'brutus_enter',             promotesTo: null },
    'king_roan':        { id: 'king_roan',        name: 'King Roan',        clan: 'iron_saints', cardType: 'leader',      authority: 10, attack: 3000, defense: 3000, level: 1, rarity: 5, subtype: 'heavy',   clanTag: 'lion', effectKey: 'king_roan_leader',         promotesTo: null },
    'lion_ambush':      { id: 'lion_ambush',      name: "Lion's Ambush",    clan: 'iron_saints', cardType: 'ambush',      authority: 2,  rarity: 2, clanTag: 'lion', effectKey: 'lion_ambush' },
    'no_witnesses':     { id: 'no_witnesses',     name: 'No Witnesses',     clan: 'iron_saints', cardType: 'ambush',      authority: 3,  rarity: 3, clanTag: 'lion', effectKey: 'no_witnesses_ambush' },
    'kings_test':       { id: 'kings_test',       name: "King's Test",      clan: 'iron_saints', cardType: 'ambush',      authority: 3,  rarity: 3, clanTag: 'lion', effectKey: 'kings_test' },
    'corner_deal':      { id: 'corner_deal',      name: 'Corner Deal',      clan: 'iron_saints', cardType: 'hustle',      authority: 2,  rarity: 1, clanTag: 'lion', effectKey: 'corner_deal' },
    'blood_scent':      { id: 'blood_scent',      name: 'Blood Scent',      clan: 'iron_saints', cardType: 'hustle',      authority: 3,  rarity: 2, clanTag: 'lion', effectKey: 'blood_scent' },
    'lion_rescue':      { id: 'lion_rescue',      name: 'Lion Rescue',      clan: 'iron_saints', cardType: 'hustle',      authority: 2,  rarity: 1, clanTag: 'lion', effectKey: 'lion_rescue' },
};

// ── Clan bonus recalculation (per side) ──────────────────────────────────────
// Each player's clan bonus is evaluated only against THEIR field. The
// opponent controlling a Lion doesn't trigger your bonus.
function recalcClanBonuses(match) {
    for (const side of ['p1', 'p2']) {
        const cards     = match[side].field;
        const lionCount = cards.filter(c => c && c.clanTag === 'lion' && !c.faceDown && !c.downed).length;
        const lionBonus = lionCount >= 2 ? 300 : 0;

        cards.forEach(card => {
            if (!card || card.clanTag !== 'lion') return;
            card._baseAtk = card._baseAtk ?? card.attack;
            card._baseDef = card._baseDef ?? card.defense;
            card.attack   = card._baseAtk + lionBonus;
        });
    }
}

// Snapshot of effective + base stats for both sides — drives the client
// stat HUD overlays. Always recomputed after any state-changing event so
// that buffs/debuffs stay in sync between the two clients.
function buildFieldStatsSnapshot(match) {
    const sideSnap = (side) => side.field.map((card, slotIndex) => {
        if (!card || card.cardType !== 'gang_member' || card.faceDown) return null;
        return {
            slotIndex,
            attack:   card.attack,
            defense:  card.defense,
            baseAttack:  card._baseAtk ?? card.attack,
            baseDefense: card._baseDef ?? card.defense,
            position: card.position || 'atk',
        };
    }).filter(Boolean);
    return { p1: sideSnap(match.p1), p2: sideSnap(match.p2) };
}

function emitFieldStats(io, match) {
    io.to(match.roomId).emit('duel:fieldStats', {
        matchId: match.matchId,
        stats:   buildFieldStatsSnapshot(match),
    });
}

// ── Phase order ───────────────────────────────────────────────────────────────
const PHASES = ['upkeep', 'deployment', 'brawl', 'regroup', 'end'];

function nextPhase(current) {
    const idx = PHASES.indexOf(current);
    return PHASES[(idx + 1) % PHASES.length];
}

// ── Field index helpers ───────────────────────────────────────────────────────
// Field is a flat 10-slot array per player:
//   slots 0-4  = front row (Gang Members)
//   slots 5-9  = back row  (Ambushes / Hustles face-down)

function isFrontRow(slotIndex) { return slotIndex >= 0 && slotIndex <= 4; }
function isBackRow(slotIndex)  { return slotIndex >= 5 && slotIndex <= 9; }

// ── Combat resolution (also used by BrawlPhase in DuelScene) ─────────────────

/**
 * Resolves an attack between two Gang Members, or a direct attack on Morale.
 *
 * @param {object} attacker      - card object with { attack, defense }
 * @param {object|null} defender - card object or null for direct attack
 * @param {object} matchState    - full match object from activeMatches
 * @param {string} attackerOwner - 'p1' | 'p2'
 * @returns {{ destroyed: boolean, moraleDealt: number, defenderDestroyed: boolean }}
 */
function resolveCombat(attacker, defender, matchState, attackerOwner) {
    const defenderOwner = attackerOwner === 'p1' ? 'p2' : 'p1';

    // Direct attack — no defender on field
    if (!defender) {
        matchState[defenderOwner].morale -= attacker.attack;
        return { destroyed: false, moraleDealt: attacker.attack, defenderDestroyed: false };
    }

    if (defender.position === 'def') {
        // ── ATK vs DEF position ──────────────────────────────────────────────
        if (attacker.attack > defender.defense) {
            return { destroyed: true, moraleDealt: 0, defenderDestroyed: true };
        } else {
            // Defender walls the attack, no damage to either side
            return { destroyed: false, moraleDealt: 0, defenderDestroyed: false };
        }
    } else {
        // ── ATK vs ATK position ──────────────────────────────────────────────
        if (attacker.attack > defender.attack) {
            const excess = attacker.attack - defender.attack;
            matchState[defenderOwner].morale -= excess;
            return { destroyed: true, moraleDealt: excess, defenderDestroyed: true };
        } else if (attacker.attack < defender.attack) {
            const excess = defender.attack - attacker.attack;
            matchState[attackerOwner].morale -= excess;
            return { destroyed: false, moraleDealt: -excess, defenderDestroyed: false, attackerDestroyed: true };
        } else {
            // Tie — both destroyed, no morale damage
            return { destroyed: true, moraleDealt: 0, defenderDestroyed: true, tie: true };
        }
    }
}

// ── Register duel events on a socket ─────────────────────────────────────────

// ── Validation helpers ────────────────────────────────────────────────────────

/** 'p1' | 'p2' for a player in this match, null for anyone else. */
function roleOf(match, playerId) {
    if (match.p1.playerId === playerId) return 'p1';
    if (match.p2.playerId === playerId) return 'p2';
    return null;
}

function isSlot(n, min, max) { return Number.isInteger(n) && n >= min && n <= max; }

/** Finds a card with copies left in the player's server-side deck pool. */
function findInDeck(side, requestedId) {
    const pool = side.deckPool;
    if (!pool || typeof requestedId !== 'string') return null;
    // Clients may identify a card by DB id or by its art key
    const entry = pool.get(requestedId)
        || [...pool.values()].find(e => e.card.art_url === requestedId);
    return entry && entry.remaining > 0 ? entry : null;
}

/** Consumes one copy from a deck-pool entry and builds the field card from DB stats. */
function takeFromDeck(entry, requestedPosition) {
    entry.remaining--;

    const c       = entry.card;
    const catalog = c.art_url ? CARD_CATALOG[c.art_url] : null;
    return {
        id:         c.art_url || c.id,
        dbId:       c.id,
        name:       c.name,
        clan:       c.clan,
        clanTag:    c.clan_tag,
        cardType:   c.card_type,
        subtype:    c.subtype,
        level:      c.level,
        authority:  c.authority,
        attack:     c.attack  ?? 0,
        defense:    c.defense ?? 0,
        rarity:     c.rarity,
        art_url:    c.art_url,
        effectKey:  c.effect_key,
        promotesTo: catalog?.promotesTo ?? null,
        position:   requestedPosition === 'def' ? 'def' : 'atk',
    };
}

function registerDuelHandler(socket, io, playerData) {

    // ── Play a card from hand to field ───────────────────────────────────────
    socket.on('duel:playCard', ({ matchId, card, slotIndex } = {}) => {
        const match = getMatch(matchId);
        if (!match || match.over) return socket.emit('duel:error', { message: 'Match not found.' });

        const role = roleOf(match, playerData.playerId);
        if (!role) return socket.emit('duel:error', { message: 'You are not in this match.' });
        if (!isSlot(slotIndex, 0, 9)) return socket.emit('duel:error', { message: 'Invalid slot.' });

        if (match.activePlayerId !== playerData.playerId) {
            return socket.emit('duel:error', { message: 'Not your turn.' });
        }
        if (!['deployment', 'regroup'].includes(match.phase)) {
            return socket.emit('duel:error', { message: 'Cannot play cards in this phase.' });
        }

        // Validate slot availability
        if (match[role].field[slotIndex] !== null) {
            return socket.emit('duel:error', { message: 'Slot already occupied.' });
        }

        // Look up the card in the player's own deck — stats come from the DB
        const entry = findInDeck(match[role], card?.dbId || card?.id);
        if (!entry) {
            return socket.emit('duel:error', { message: 'That card is not in your deck.' });
        }
        const cardType = entry.card.card_type;
        if (cardType === 'leader') {
            return socket.emit('duel:error', { message: 'Leader cards cannot be played to the field.' });
        }

        // Gang Members go front row; Ambushes / Hustles go back row
        if (cardType === 'gang_member' && !isFrontRow(slotIndex)) {
            return socket.emit('duel:error', { message: 'Gang Members must be placed in the front row (slots 0-4).' });
        }
        if (cardType !== 'gang_member' && !isBackRow(slotIndex)) {
            return socket.emit('duel:error', { message: 'Hustles and Ambushes go in the back row (slots 5-9).' });
        }

        // Place the server-built card (consumes one copy from the deck pool)
        const placed = takeFromDeck(entry, card?.position);
        match[role].field[slotIndex] = {
            ...placed,
            faceDown:    cardType === 'ambush',
            hasAttacked: false,
        };
        card = match[role].field[slotIndex];

        recalcClanBonuses(match);

        io.to(match.roomId).emit('duel:cardPlayed', {
            matchId,
            role,
            slotIndex,
            card: card.cardType === 'ambush'
                ? { id: card.id, cardType: 'ambush', faceDown: true }  // hide ambush data from opponent
                : card,
        });
        emitFieldStats(io, match);
    });

    // ── Declare an attack ────────────────────────────────────────────────────
    socket.on('duel:attack', ({ matchId, attackerSlot, defenderSlot } = {}) => {
        const match = getMatch(matchId);
        if (!match || match.over) return socket.emit('duel:error', { message: 'Match not found.' });
        if (!roleOf(match, playerData.playerId)) {
            return socket.emit('duel:error', { message: 'You are not in this match.' });
        }
        if (!isSlot(attackerSlot, 0, 4) || (defenderSlot !== null && !isSlot(defenderSlot, 0, 4))) {
            return socket.emit('duel:error', { message: 'Invalid slot.' });
        }

        if (match.activePlayerId !== playerData.playerId) {
            return socket.emit('duel:error', { message: 'Not your turn.' });
        }
        if (match.phase !== 'brawl') {
            return socket.emit('duel:error', { message: 'Attacks can only be declared in the Brawl Phase.' });
        }

        const role         = roleOf(match, playerData.playerId);
        const opponentRole = role === 'p1' ? 'p2' : 'p1';

        const attacker = match[role].field[attackerSlot];
        if (!attacker || attacker.cardType !== 'gang_member') {
            return socket.emit('duel:error', { message: 'Invalid attacker.' });
        }
        if (attacker.hasAttacked) {
            return socket.emit('duel:error', { message: 'This Gang Member already attacked this turn.' });
        }

        // null defenderSlot = direct attack
        const defender = defenderSlot !== null ? match[opponentRole].field[defenderSlot] : null;

        // Check if opponent has any front-row monsters (must attack them first)
        const opponentFront = match[opponentRole].field.slice(0, 5).filter(Boolean);
        if (opponentFront.length > 0 && defender === null) {
            return socket.emit('duel:error', { message: 'You must attack a Gang Member before attacking directly.' });
        }

        // ── Ambush check: does the defender slot have a face-down Ambush? ───
        // (full trap logic lives in the client; server just triggers the reveal)
        const backRowSlot = defenderSlot !== null ? defenderSlot + 5 : null;
        const ambush      = backRowSlot !== null ? match[opponentRole].field[backRowSlot] : null;

        let ambushTriggered = false;
        if (ambush && ambush.faceDown && ambush.cardType === 'ambush') {
            ambushTriggered = true;
            // Reveal the ambush
            match[opponentRole].field[backRowSlot].faceDown = false;
            // Full effect resolution delegated to client via event
        }

        // ── Resolve combat ───────────────────────────────────────────────────
        const result = resolveCombat(attacker, defender, match, role);
        attacker.hasAttacked = true;

        // Destroy cards if needed
        let promoted = false, promotedCard = null;

        if (result.defenderDestroyed && defender) {
            match[opponentRole].graveyard = match[opponentRole].graveyard || [];
            match[opponentRole].graveyard.push(defender);
            match[opponentRole].field[defenderSlot] = null;

            // Promotion: attacker evolves after a kill
            if (attacker.promotesTo && CARD_CATALOG[attacker.promotesTo]) {
                promotedCard = {
                    ...CARD_CATALOG[attacker.promotesTo],
                    hasAttacked: true,   // promotion sickness — sits out the rest of this turn
                };
                match[role].graveyard = match[role].graveyard || [];
                match[role].graveyard.push({ ...attacker });
                match[role].field[attackerSlot] = promotedCard;
                promoted = true;
            }
        }
        // Attacker destroyed (lost ATK vs ATK battle, or tie)
        if (result.attackerDestroyed || result.tie) {
            match[role].graveyard = match[role].graveyard || [];
            if (result.tie && !result.attackerDestroyed) match[role].graveyard.push({ ...attacker });
            match[role].field[attackerSlot] = null;
        }

        // Recalc continuous effects after field change
        recalcClanBonuses(match);

        // ── Check win condition ──────────────────────────────────────────────
        const gameOver = match.p1.morale <= 0 || match.p2.morale <= 0;

        const combatPayload = {
            matchId,
            attackerRole:  role,
            attackerSlot,
            defenderSlot,
            result,
            ambushTriggered,
            ambushCard:    ambushTriggered ? match[opponentRole].field[backRowSlot] : null,
            p1Morale:      match.p1.morale,
            p2Morale:      match.p2.morale,
            promoted,
            promotedCard,
            promotingRole: promoted ? role : null,
            promotingSlot: promoted ? attackerSlot : null,
            gameOver,
        };

        io.to(match.roomId).emit('duel:attacked', combatPayload);
        emitFieldStats(io, match);

        if (gameOver) {
            // Winner is decided by morale, not by who attacked — an attack that
            // backfires can knock out the attacker. Both at 0 is a draw.
            const p1Out = match.p1.morale <= 0;
            const p2Out = match.p2.morale <= 0;
            finishMatch(io, match, p1Out && p2Out ? null : (p1Out ? 'p2' : 'p1'));
        }
    });

    // ── Set position for a just-promoted card ────────────────────────────────
    socket.on('duel:setPromotionPosition', ({ matchId, slotIndex, position } = {}) => {
        const match = getMatch(matchId);
        if (!match || match.over) return;

        const role = roleOf(match, playerData.playerId);
        if (!role || !isSlot(slotIndex, 0, 4) || !['atk', 'def'].includes(position)) return;
        const card = match[role].field[slotIndex];
        if (!card || card.cardType !== 'gang_member') return;

        card.position = position;

        io.to(match.roomId).emit('duel:promotionPositionSet', {
            matchId,
            role,
            slotIndex,
            position,
        });
        emitFieldStats(io, match);
    });

    // ── Phase advance ────────────────────────────────────────────────────────
    socket.on('duel:phaseAdvance', ({ matchId } = {}) => {
        const match = getMatch(matchId);
        if (!match || match.over || match.activePlayerId !== playerData.playerId) return;

        match.phase = nextPhase(match.phase);

        // When phase wraps back to 'upkeep', it's the other player's turn
        if (match.phase === 'upkeep') {
            match.activePlayerId = match.activePlayerId === match.p1.playerId
                ? match.p2.playerId
                : match.p1.playerId;
            match.turn++;

            // Clear summon-sick and hasAttacked flags for the new active player
            const newRole = match.activePlayerId === match.p1.playerId ? 'p1' : 'p2';
            match[newRole].field.forEach(card => {
                if (card) { card.hasAttacked = false; }
            });
        }

        io.to(match.roomId).emit('duel:phaseChanged', {
            matchId,
            phase:           match.phase,
            activePlayerId:  match.activePlayerId,
            turn:            match.turn,
        });
    });
}

// ── Match-over resolution ─────────────────────────────────────────────────────

/**
 * Ends a match exactly once, records it and pays out rewards.
 * @param {'p1'|'p2'|null} winnerRole  null = draw
 */
async function finishMatch(io, match, winnerRole) {
    if (match.over) return;
    match.over = true;
    removeMatch(match.matchId);

    const winnerId = winnerRole ? match[winnerRole].playerId : null;
    const loserId  = winnerRole ? match[winnerRole === 'p1' ? 'p2' : 'p1'].playerId : null;

    let rewardResults = null;
    try {
        rewardResults = await resolveMatch({
            winnerId,
            loserId,
            p1Id: match.p1.playerId,
            p2Id: match.p2.playerId,
            matchMeta: {
                turns:        match.turn,
                p1MoraleEnd:  match.p1.morale,
                p2MoraleEnd:  match.p2.morale,
                durationSecs: Math.round((Date.now() - match.startedAt) / 1000),
            },
        });
    } catch (err) {
        console.error('[DuelHandler] Post-match reward error:', err.message);
    }

    io.to(match.roomId).emit('duel:matchOver', {
        matchId:   match.matchId,
        winnerId,
        rewards:   rewardResults,
        p1Morale:  match.p1.morale,
        p2Morale:  match.p2.morale,
    });
}

module.exports = { registerDuelHandler, resolveCombat, finishMatch };
