const tasks = require("./routes/tasks");
const connection = require("./db");
const cors = require("cors");
const express = require("express");
const app = express();

connection();

app.use(express.json());
app.use(cors());

app.get("/ok", (req, res) => {
  res.status(200).send("ok");
});

// will replace this with /ok for better liveness and readiness probe practice
// app.get("/healthz", (req, res) => {
//   res.sendStatus(200);
// });
//
// app.get("/readyz", async (req, res) => {
//   try {
//     await mongoose.connection.db.admin().ping();
//     res.sendStatus(200);
//   } catch {
//     res.sendStatus(500);
//   }
// });

app.use("/api/tasks", tasks);

const port = process.env.PORT || 3500;
app.listen(port, () => console.log(`Listening on port ${port}...`));
