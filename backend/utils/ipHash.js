'use strict';

/**
 * A scrambled IP address: an HMAC of it with the server's secret, so the auction house can tell that two
 * accounts used the same connection without the address itself being stored (economy/auction.js).
 */

const crypto = require('crypto');

function clientIp(req) {
    return String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '').split(',')[0].trim();
}

function ipHash(req) {
    const ip = clientIp(req);
    if (!ip) return null;
    return crypto.createHmac('sha256', process.env.JWT_SECRET || 'dev').update(ip).digest('hex').slice(0, 24);
}

module.exports = { ipHash, clientIp };
