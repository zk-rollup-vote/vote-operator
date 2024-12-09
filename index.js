const express = require("express");
const bodyParser = require("body-parser");
const mysql = require("mysql");
const { keccak256 } = require("js-sha3");
const { ethers } = require("ethers");
require("dotenv").config();

const app = express();
app.timeout = 3000000;
let port = process.env.PORT || 3000;

app.use(bodyParser.json({ limit: "50mb" }));

const privateKey = process.env.OPERATOR_PRIVATE_KEY;

if (!privateKey) {
  console.error("Operator private key not set in .env file");
  process.exit(1);
}

const db = mysql.createPool({
  connectionLimit: 5,
  acquireTimeout: 100000,
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_DATABASE,
  port: process.env.DB_PORT || 3306,
});

const createTableQuery = `
CREATE TABLE IF NOT EXISTS votes (
  id VARCHAR(255) PRIMARY KEY,
  data LONGTEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)`;

db.query(createTableQuery, (err, result) => {
  if (err) throw err;
  console.log("Table created or already exists");
});

// Routes
app.post("/votes", async (req, res) => {
  const { data } = req.body;

  if (!data) {
    return res.status(400).json({ error: "Data field is required" });
  }

  const id = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(data)));
  const wallet = new ethers.Wallet(privateKey);
  const signature = await wallet.signMessage(ethers.getBytes(id));

  const query = "INSERT INTO votes (data, id) VALUES (?, ?)";
  db.query(query, [JSON.stringify(data), id], (err, result) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: "Failed to save data" });
    }
    res.status(201).json({
      message: "Data saved successfully",
      id: id,
      signature: signature,
    });
  });
});

app.get("/votes/:id", (req, res) => {
  const id = req.params.id;

  if (!id) {
    return res.status(400).json({ error: "ID is required" });
  }

  const query = "SELECT * FROM votes WHERE id=?";
  db.query(query, [req.params.id], (err, results) => {
    if (err) {
      console.error(err);
      return res.status(500).json({ error: "Failed to retrieve data" });
    }

    if (results.length === 0) {
      return res.status(200).json({ data: [] });
    }

    res.status(200).json({ data: JSON.parse(results[0].data) });
  });
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
