const Task = require("../models/task");
const { publishEvent } = require("../sqs");
const express = require("express");
const router = express.Router();

router.post("/", async (req, res) => {
    try {
        const task = await new Task(req.body).save();
        await publishEvent({
            taskId: task._id,
            event: "task.created",
            timestamp: new Date().toISOString(),
        });
        res.send(task);
    } catch (error) {
        res.send(error);
    }
});

router.get("/", async (req, res) => {
    try {
        const tasks = await Task.find();
        res.send(tasks);
    } catch (error) {
        res.send(error);
    }
});

router.put("/:id", async (req, res) => {
    try {
        const task = await Task.findOneAndUpdate(
            { _id: req.params.id },
            req.body
        );
        if (task) {
            await publishEvent({
                taskId: req.params.id,
                event:
                    req.body.completed === true
                        ? "task.completed"
                        : "task.updated",
                timestamp: new Date().toISOString(),
            });
        }
        res.send(task);
    } catch (error) {
        res.send(error);
    }
});

router.delete("/:id", async (req, res) => {
    try {
        const task = await Task.findByIdAndDelete(req.params.id);
        res.send(task);
    } catch (error) {
        res.send(error);
    }
});

module.exports = router;
