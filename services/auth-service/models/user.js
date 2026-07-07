const { pool } = require("../db");

// Inserts a new user and returns the safe fields only (never password_hash).
// Throws on unique-violation (Postgres error code 23505) so the route can map
// it to a 409.
async function createUser(email, passwordHash) {
    const result = await pool.query(
        "INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email",
        [email, passwordHash]
    );
    return result.rows[0];
}

// Returns the full user row (including password_hash for verification) or
// undefined if no user matches.
async function findUserByEmail(email) {
    const result = await pool.query(
        "SELECT id, email, password_hash FROM users WHERE email = $1",
        [email]
    );
    return result.rows[0];
}

module.exports = { createUser, findUserByEmail };
