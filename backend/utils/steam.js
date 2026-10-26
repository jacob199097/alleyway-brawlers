'use strict';

/**
 * STEAM WEB API (routes/steam.js): checks the game's Steam sign-in tickets and runs Steam wallet
 * purchases (Steam Microtransactions). Settings in backend/.env:
 *
 *   STEAM_APP_ID          the game's App ID (480, Valve's test app "Spacewar", until it has its own)
 *   STEAM_WEB_API_KEY     a Steam Web API key: enough to check sign-in tickets and read player names
 *   STEAM_PUBLISHER_KEY   the publisher Web API key from Steamworks (needed for purchases; used for
 *                         sign-in too when set)
 *   STEAM_MTX_SANDBOX     "false" for real money; anything else uses Steam's sandbox (no charge)
 *
 * The game asks Steam for a ticket for the identity "alleyway" (scripts/steam.gd) and sends it as
 * hex; AuthenticateUserTicket says whose it is. Purchases: InitTxn (Steam shows the player the
 * order in the overlay), then FinalizeTxn once they approve.
 */

const IDENTITY = 'alleyway';

function config(env = process.env) {
    const publisher = env.STEAM_PUBLISHER_KEY || '';
    return {
        appId: String(env.STEAM_APP_ID || '480'),
        key: publisher || env.STEAM_WEB_API_KEY || '',
        publisher,
        sandbox: env.STEAM_MTX_SANDBOX !== 'false',
    };
}

class SteamError extends Error {
    constructor(message, status = 502) {
        super(message);
        this.status = status;
    }
}

/** A Steam Web API call → its JSON. Publisher keys go to partner.steam-api.com. */
async function call(cfg, iface, method, version, params, { post = false, fetchFn = fetch } = {}) {
    const host = cfg.publisher ? 'https://partner.steam-api.com' : 'https://api.steampowered.com';
    const query = new URLSearchParams({ key: cfg.key, ...params });
    const url = `${host}/${iface}/${method}/v${version}/`;
    const res = post
        ? await fetchFn(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: query.toString() })
        : await fetchFn(`${url}?${query}`);
    if (!res.ok) throw new SteamError(`Steam said ${res.status} to ${method}.`);
    return res.json();
}

/** The Steam ID (string) a sign-in ticket belongs to; throws a SteamError if it isn't valid. */
async function verifyTicket(ticketHex, { cfg = config(), fetchFn } = {}) {
    if (!cfg.key) throw new SteamError("Steam sign-in isn't set up on the server yet.", 503);
    if (typeof ticketHex !== 'string' || !/^[0-9a-fA-F]{16,4096}$/.test(ticketHex)) throw new SteamError('That Steam ticket is not valid.', 400);
    const data = await call(cfg, 'ISteamUserAuth', 'AuthenticateUserTicket', 1,
        { appid: cfg.appId, ticket: ticketHex, identity: IDENTITY }, { fetchFn });
    const p = data?.response?.params;
    if (!p || p.result !== 'OK' || !/^\d{17}$/.test(String(p.steamid || ''))) {
        const why = data?.response?.error?.errordesc;
        throw new SteamError(why ? `Steam didn't accept the ticket (${why}).` : "Steam didn't accept the ticket.", 401);
    }
    if (p.vacbanned || p.publisherbanned) throw new SteamError('This Steam account is banned from the game.', 403);
    return String(p.steamid);
}

/** A Steam player's display name (or '' when it can't be read). */
async function personaName(steamId, { cfg = config(), fetchFn } = {}) {
    try {
        const data = await call({ ...cfg, publisher: '' }, 'ISteamUser', 'GetPlayerSummaries', 2, { steamids: steamId }, { fetchFn });
        return String(data?.response?.players?.[0]?.personaname || '');
    } catch {
        return '';
    }
}

/** Steam Microtransactions: InitTxn, FinalizeTxn (publisher key only). */
function mtxInterface(cfg) {
    return cfg.sandbox ? 'ISteamMicroTxnSandbox' : 'ISteamMicroTxn';
}

async function initTxn({ orderId, steamId, itemId, description, amountCents, currency = 'USD', language = 'en' }, { cfg = config(), fetchFn } = {}) {
    if (!cfg.publisher) throw new SteamError("Steam purchases aren't set up on the server yet.", 503);
    const data = await call(cfg, mtxInterface(cfg), 'InitTxn', 3, {
        orderid: String(orderId), steamid: steamId, appid: cfg.appId, itemcount: '1', language, currency,
        'itemid[0]': String(itemId), 'qty[0]': '1', 'amount[0]': String(amountCents), 'description[0]': description,
    }, { post: true, fetchFn });
    const r = data?.response;
    if (r?.result !== 'OK') throw new SteamError(r?.error?.errordesc ? `Steam: ${r.error.errordesc}` : 'Steam could not start the purchase.');
    return { transId: String(r.params?.transid ?? '') };
}

async function finalizeTxn(orderId, { cfg = config(), fetchFn } = {}) {
    if (!cfg.publisher) throw new SteamError("Steam purchases aren't set up on the server yet.", 503);
    const data = await call(cfg, mtxInterface(cfg), 'FinalizeTxn', 2, { orderid: String(orderId), appid: cfg.appId }, { post: true, fetchFn });
    const r = data?.response;
    if (r?.result !== 'OK') throw new SteamError(r?.error?.errordesc ? `Steam: ${r.error.errordesc}` : 'Steam could not complete the purchase.', 402);
    return { transId: String(r.params?.transid ?? '') };
}

module.exports = { config, verifyTicket, personaName, initTxn, finalizeTxn, SteamError, IDENTITY };
