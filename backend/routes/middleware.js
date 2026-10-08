'use strict';

const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET;

function requireAuth(req, res, next) {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Authorization header missing.' });
    }
    try {
        const decoded = jwt.verify(header.slice(7), JWT_SECRET);
        req.playerId  = decoded.sub;
        req.username  = decoded.username;
        next();
    } catch {
        res.status(401).json({ error: 'Invalid or expired token.' });
    }
}

module.exports = { requireAuth };
