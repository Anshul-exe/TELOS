const { createUser, findUserByEmail } = require("../models/user");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const express = require("express");
const router = express.Router();

const SALT_ROUNDS = 10;

router.post("/register", async (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res
                .status(400)
                .send({ error: "email and password are required" });
        }
        const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
        const user = await createUser(email, passwordHash);
        res.status(201).send(user);
    } catch (error) {
        // 23505 = unique_violation (email already registered)
        if (error.code === "23505") {
            return res.status(409).send({ error: "email already registered" });
        }
        res.status(500).send({ error: "internal server error" });
    }
});

router.post("/login", async (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res
                .status(400)
                .send({ error: "email and password are required" });
        }
        const user = await findUserByEmail(email);
        if (!user) {
            return res.status(401).send({ error: "invalid credentials" });
        }
        const match = await bcrypt.compare(password, user.password_hash);
        if (!match) {
            return res.status(401).send({ error: "invalid credentials" });
        }
        const token = jwt.sign(
            { userId: user.id, email: user.email },
            process.env.JWT_SECRET,
            { expiresIn: "1h" }
        );
        res.send({ token });
    } catch (error) {
        res.status(500).send({ error: "internal server error" });
    }
});

module.exports = router;
