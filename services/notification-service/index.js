const notifications = require("./routes/notifications");
const connection = require("./db");
const { startConsumer } = require("./consumer");
const cors = require("cors");
const express = require("express");
const app = express();

app.use(express.json());
app.use(cors());

app.get("/ok", (req, res) => {
  res.status(200).send("ok");
});

app.use("/api/notifications", notifications);

const port = process.env.PORT || 4500;

// Connect to the DB first, then start the SQS consumer loop, then listen.
(async () => {
  await connection();
  startConsumer();
  app.listen(port, () => console.log(`Listening on port ${port}...`));
})();
