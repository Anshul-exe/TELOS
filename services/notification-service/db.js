const mongoose = require("mongoose");

module.exports = async () => {
    try {
        const connectionParams = {
            useNewUrlParser: true,
            useUnifiedTopology: true,
            // This service owns a separate logical database from task-service.
            dbName: process.env.MONGO_DB_NAME || "notifications",
        };
        const useDBAuth = process.env.USE_DB_AUTH || false;
        if (useDBAuth) {
            connectionParams.user = process.env.MONGO_USERNAME;
            connectionParams.pass = process.env.MONGO_PASSWORD;
        }
        await mongoose.connect(process.env.MONGO_CONN_STR, connectionParams);
        console.log("Connected to database.");
    } catch (error) {
        console.log("Could not connect to database.", error);
    }
};
