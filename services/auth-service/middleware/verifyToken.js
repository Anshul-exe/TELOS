const jwt = require("jsonwebtoken");

// Express middleware that verifies a JWT from the `Authorization: Bearer <token>`
// header. On success it attaches the decoded payload to req.user and calls next();
// otherwise it responds 401. Intended to be reused by other services (e.g.
// task-service) to guard their routes.
module.exports = function verifyToken(req, res, next) {
    const header = req.headers["authorization"] || "";
    const [scheme, token] = header.split(" ");

    if (scheme !== "Bearer" || !token) {
        return res
            .status(401)
            .send({ error: "missing or malformed Authorization header" });
    }

    try {
        req.user = jwt.verify(token, process.env.JWT_SECRET);
        next();
    } catch (error) {
        res.status(401).send({ error: "invalid or expired token" });
    }
};
