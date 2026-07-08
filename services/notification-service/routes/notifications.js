const Notification = require("../models/notification");
const express = require("express");
const router = express.Router();

router.get("/", async (req, res) => {
    try {
        const notifications = await Notification.find()
            .sort({ receivedAt: -1 })
            .limit(50);
        res.send(notifications);
    } catch (error) {
        res.send(error);
    }
});

module.exports = router;
