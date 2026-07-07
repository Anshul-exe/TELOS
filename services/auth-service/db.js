const { Pool } = require("pg");

// Shared connection pool. Reads the full connection string from PG_CONN_STR.
const pool = new Pool({
    connectionString: process.env.PG_CONN_STR,
});

// Ensures the users table exists. Kept here (rather than a migration tool) to
// stay minimal — mirrors how task-service relies on Mongoose to auto-create
// collections. Safe to call on every boot.
const init = async () => {
    try {
        await pool.query(`
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        `);
        console.log("Connected to database.");
    } catch (error) {
        console.log("Could not connect to database.", error);
    }
};

module.exports = { pool, init };
