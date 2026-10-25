'use strict';

/**
 * Which websites may talk to the server (CORS, and the live socket). The game is not a website: it
 * sends no Origin header, so requests without one (the game, payment webhooks, curl) always pass.
 * A browser page may only call in from the server's own site (the privacy and account-deletion
 * pages): APP_BASE_URL / APP_CLIENT_URL, the LAN and localhost addresses, and any extra origins in
 * CORS_ORIGINS (comma-separated). Every other website is refused (403), not just left unable to
 * read the answer.
 */

function allowedOrigins(env = process.env) {
    const port = env.PORT || 3000;
    const list = [env.APP_BASE_URL, env.APP_CLIENT_URL, ...(env.CORS_ORIGINS || '').split(','),
        'https://alleywaybrawlers.duckdns.org', `http://192.168.0.200:${port}`, `http://localhost:${port}`, `http://127.0.0.1:${port}`];
    const out = new Set();
    for (const u of list) {
        if (!u || !String(u).trim()) continue;
        try {
            out.add(new URL(String(u).trim()).origin);
        } catch {
            // (not a URL: ignored)
        }
    }
    return out;
}

/** Whether a request with this Origin header may go ahead (none: the game, a webhook). */
function originAllowed(origin, allowed = allowedOrigins()) {
    return origin == null || origin === '' || allowed.has(String(origin));
}

/** Express middleware: refuse other websites outright. */
function refuseOtherSites(allowed = allowedOrigins()) {
    return (req, res, next) => {
        if (originAllowed(req.headers.origin, allowed)) return next();
        res.status(403).json({ error: 'This website may not use the AlleyWay Brawlers server.' });
    };
}

module.exports = { allowedOrigins, originAllowed, refuseOtherSites };
