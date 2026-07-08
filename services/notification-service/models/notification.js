const mongoose = require("mongoose");
const Schema = mongoose.Schema;

const notificationSchema = new Schema({
    taskId: {
        type: String,
        required: true,
    },
    event: {
        type: String,
        required: true,
    },
    message: {
        type: String,
    },
    receivedAt: {
        type: Date,
        default: Date.now,
    },
});

module.exports = mongoose.model("notification", notificationSchema);
