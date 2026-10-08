'use strict';

const { Pool } = require('pg');

const pool = new Pool({
    host:     process.env.DB_HOST     || 'localhost',
    port:     parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME     || 'turf_war',
    user:     process.env.DB_USER     || 'turf_admin',
    password: process.env.DB_PASS || undefined,
    max:      20,   // max pool connections
    idleTimeoutMillis:    30_000,
    connectionTimeoutMillis: 5_000,
});

pool.on('error', (err) => {
    console.error('[DB] Unexpected pool error:', err.message);
});

module.exports = { pool };
