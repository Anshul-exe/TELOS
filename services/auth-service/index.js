const auth = require("./routes/auth");
const { init } = require("./db");
const cors = require("cors");
const express = require("express");
const app = express();

init();

app.use(express.json());
app.use(cors());

app.get("/ok", (req, res) => {
  res.status(200).send("ok");
});

app.use("/api/auth", auth);

const port = process.env.PORT || 4000;
app.listen(port, () => console.log(`Listening on port ${port}...`));
