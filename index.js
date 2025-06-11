const express = require("express");
const bodyParser = require("body-parser");
const mysql = require("mysql2/promise");
const { ethers } = require("ethers");
const rateLimit = require("express-rate-limit");
const cors = require("cors");
const helmet = require("helmet");
require("dotenv").config();

const DEFAULT_PORT = 3000;
const DEFAULT_HOST = "0.0.0.0";
const REQUEST_TIMEOUT = 30000;
const DB_CONNECTION_LIMIT = 10;
const MAX_REQUESTS_PER_MINUTE = 10000;

class VoteOperatorServer {
  constructor() {
    this.app = express();
    this.port = process.env.PORT || DEFAULT_PORT;
    this.host = process.env.HOST || DEFAULT_HOST;
    this.db = null;
    this.wallet = null;

    this.initializeMiddleware();
    this.initializeDatabase();
    this.initializeWallet();
    this.initializeRoutes();
    this.initializeErrorHandling();
  }

  validateEnvironment() {
    const requiredVars = [
      "OPERATOR_PRIVATE_KEY",
      "DB_HOST",
      "DB_USER",
      "DB_PASSWORD",
      "DB_DATABASE",
    ];

    const missing = requiredVars.filter((varName) => !process.env[varName]);

    if (missing.length > 0) {
      console.error(
        `Missing required environment variables: ${missing.join(", ")}`
      );
      process.exit(1);
    }
  }

  initializeMiddleware() {
    this.app.use(helmet());
    this.app.use(cors());

    const limiter = rateLimit({
      windowMs: 60 * 1000, // 1 minute
      max: MAX_REQUESTS_PER_MINUTE,
      message: { error: "Too many requests, please try again later." },
    });
    this.app.use(limiter);

    this.app.use(
      bodyParser.json({
        limit: "50mb",
        verify: (req, res, buf) => {
          try {
            JSON.parse(buf);
          } catch (e) {
            throw new Error("Invalid JSON");
          }
        },
      })
    );

    this.app.use((req, res, next) => {
      req.setTimeout(REQUEST_TIMEOUT);
      next();
    });

    this.app.use((req, res, next) => {
      console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
      next();
    });
  }

  async initializeDatabase() {
    try {
      this.validateEnvironment();

      this.db = mysql.createPool({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_DATABASE,
        port: process.env.DB_PORT || 3306,
        connectionLimit: DB_CONNECTION_LIMIT,
      });

      await this.createTables();
      console.log("Database connected and tables initialized");
    } catch (error) {
      console.error("Database initialization failed:", error.message);
      process.exit(1);
    }
  }

  async createTables() {
    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS votes (
        id VARCHAR(66) PRIMARY KEY,
        data LONGTEXT NOT NULL,
        signature VARCHAR(132) NOT NULL,
        signer VARCHAR(42),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )`;

    try {
      await this.db.execute(createTableQuery);
    } catch (error) {
      throw new Error(`Failed to create tables: ${error.message}`);
    }
  }

  initializeWallet() {
    try {
      const privateKey = process.env.OPERATOR_PRIVATE_KEY;
      if (!privateKey) {
        throw new Error(
          "OPERATOR_PRIVATE_KEY not set in environment variables"
        );
      }

      this.wallet = new ethers.Wallet(privateKey);
      console.log("Wallet initialized:", this.wallet.address);
    } catch (error) {
      console.error("Wallet initialization failed:", error.message);
      process.exit(1);
    }
  }

  validateVoteData(req, res, next) {
    const { data, signature, signer } = req.body;

    if (!data) {
      return res.status(400).json({
        error: "Missing required field: data",
        code: "MISSING_DATA",
      });
    }

    if (typeof data !== "object") {
      return res.status(400).json({
        error: "Data must be an object",
        code: "INVALID_DATA_TYPE",
      });
    }

    if (signature && typeof signature !== "string") {
      return res.status(400).json({
        error: "Signature must be a string",
        code: "INVALID_SIGNATURE_TYPE",
      });
    }

    if (signature && !ethers.isHexString(signature)) {
      return res.status(400).json({
        error: "Signature must be a valid hex string",
        code: "INVALID_SIGNATURE_FORMAT",
      });
    }

    if (signer && !ethers.isAddress(signer)) {
      return res.status(400).json({
        error: "Invalid signer address format",
        code: "INVALID_SIGNER_ADDRESS",
      });
    }

    next();
  }

  async validateSignature(data, signature, expectedSigner = null) {
    try {
      const dataString = JSON.stringify(data);
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(dataString));

      const recoveredSigner = ethers.verifyMessage(
        ethers.getBytes(messageHash),
        signature
      );

      if (
        expectedSigner &&
        recoveredSigner.toLowerCase() !== expectedSigner.toLowerCase()
      ) {
        return {
          isValid: false,
          error: "Signature does not match expected signer",
          recoveredSigner: recoveredSigner,
        };
      }

      return {
        isValid: true,
        recoveredSigner: recoveredSigner,
      };
    } catch (error) {
      return {
        isValid: false,
        error: `Signature verification failed: ${error.message}`,
        recoveredSigner: null,
      };
    }
  }

  initializeRoutes() {
    // Health check
    this.app.get("/", this.handleHealthCheck.bind(this));

    // Vote routes
    this.app.post(
      "/votes",
      this.validateVoteData.bind(this),
      this.handleCreateVote.bind(this)
    );
    this.app.get("/votes/:id", this.handleGetVote.bind(this));

    // Signature verification route
    this.app.post(
      "/verify-signature",
      this.validateVoteData.bind(this),
      this.handleVerifySignature.bind(this)
    );

    // Additional utility routes
    this.app.get("/votes", this.handleGetAllVotes.bind(this));
  }

  // Route handlers
  async handleHealthCheck(req, res) {
    try {
      // Check database connection
      await this.db.execute("SELECT 1");

      res.status(200).json({
        status: "healthy",
        timestamp: new Date().toISOString(),
        version: "1.0.0",
        operator: this.wallet.address,
      });
    } catch (error) {
      res.status(503).json({
        status: "unhealthy",
        error: "Database connection failed",
      });
    }
  }

  async handleCreateVote(req, res) {
    try {
      const { data, signature: providedSignature, signer } = req.body;

      // Generate deterministic ID from data
      const dataString = JSON.stringify(data);
      const id = ethers.keccak256(ethers.toUtf8Bytes(dataString));

      let operatorSignature;
      let signerAddress;

      // If signature is provided, validate it
      if (providedSignature) {
        const validationResult = await this.validateSignature(
          data,
          providedSignature,
          signer
        );

        if (!validationResult.isValid) {
          return res.status(400).json({
            error: validationResult.error,
            code: "INVALID_SIGNATURE",
          });
        }

        signerAddress = validationResult.recoveredSigner;
        console.log(`Signature validated for signer: ${signerAddress}`);

        operatorSignature = await this.wallet.signMessage(ethers.getBytes(id));
        console.log(`Operator signature created: ${operatorSignature}`);
      } else {
        return res.status(400).json({
          error: "signature is required",
          code: "INVALID_SIGNATURE",
        });
      }

      // Store in database with operator signature
      const query =
        "INSERT INTO votes (id, data, signature, signer) VALUES (?, ?, ?, ?)";
      await this.db.execute(query, [
        id,
        dataString,
        operatorSignature,
        signerAddress,
      ]);

      console.log(`✅ Vote created with ID: ${id}`);

      res.status(201).json({
        success: true,
        message: "Vote saved successfully",
        data: {
          id,
          signature: operatorSignature,
          signer: signerAddress,
          operator: this.wallet.address,
        },
      });
    } catch (error) {
      console.error("❌ Create vote error:", error);

      if (error.code === "ER_DUP_ENTRY") {
        return res.status(409).json({
          error: "Vote with this data already exists",
          code: "DUPLICATE_VOTE",
        });
      }

      res.status(500).json({
        error: "Failed to save vote",
        code: "INTERNAL_ERROR",
      });
    }
  }

  async handleGetVote(req, res) {
    try {
      const { id } = req.params;

      if (!id || !ethers.isHexString(id, 32)) {
        return res.status(400).json({
          error: "Invalid vote ID format",
          code: "INVALID_ID",
        });
      }

      const query = "SELECT * FROM votes WHERE id = ?";
      const [results] = await this.db.execute(query, [id]);

      if (results.length === 0) {
        return res.status(404).json({
          error: "Vote not found",
          code: "VOTE_NOT_FOUND",
        });
      }

      const vote = results[0];
      res.status(200).json({
        success: true,
        data: {
          id: vote.id,
          data: JSON.parse(vote.data),
          signature: vote.signature,
          signer: vote.signer,
          createdAt: vote.created_at,
        },
      });
    } catch (error) {
      console.error("❌ Get vote error:", error);
      res.status(500).json({
        error: "Failed to retrieve vote",
        code: "INTERNAL_ERROR",
      });
    }
  }

  async handleGetAllVotes(req, res) {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 10, 100); // Max 100 items
      const offset = parseInt(req.query.offset) || 0;

      const query =
        "SELECT id, created_at FROM votes ORDER BY created_at DESC LIMIT ? OFFSET ?";
      const [results] = await this.db.execute(query, [limit, offset]);

      res.status(200).json({
        success: true,
        data: results,
        pagination: {
          limit,
          offset,
          count: results.length,
        },
      });
    } catch (error) {
      console.error("Get all votes error:", error);
      res.status(500).json({
        error: "Failed to retrieve votes",
        code: "INTERNAL_ERROR",
      });
    }
  }

  async handleVerifySignature(req, res) {
    try {
      const { data, signature, signer } = req.body;

      if (!signature) {
        return res.status(400).json({
          error: "Signature is required for verification",
          code: "MISSING_SIGNATURE",
        });
      }

      const validationResult = await this.validateSignature(
        data,
        signature,
        signer
      );

      if (!validationResult.isValid) {
        return res.status(400).json({
          success: false,
          error: validationResult.error,
          code: "SIGNATURE_VERIFICATION_FAILED",
        });
      }

      res.status(200).json({
        success: true,
        message: "Signature is valid",
        data: {
          isValid: true,
          recoveredSigner: validationResult.recoveredSigner,
          dataHash: ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(data))),
        },
      });
    } catch (error) {
      console.error("Verify signature error:", error);
      res.status(500).json({
        error: "Failed to verify signature",
        code: "INTERNAL_ERROR",
      });
    }
  }

  // Error handling middleware
  initializeErrorHandling() {
    // 404 handler
    this.app.use((req, res) => {
      res.status(404).json({
        error: "Endpoint not found",
        code: "NOT_FOUND",
      });
    });

    // Global error handler
    this.app.use((err, req, res, next) => {
      console.error("Unhandled error:", err);

      if (err.type === "entity.parse.failed") {
        return res.status(400).json({
          error: "Invalid JSON in request body",
          code: "INVALID_JSON",
        });
      }

      res.status(500).json({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      });
    });
  }

  // Start the server
  async start() {
    try {
      this.app.listen(this.port, this.host, () => {
        console.log(
          `Vote Operator Server running on ${this.host}:${this.port}`
        );
      });
    } catch (error) {
      console.error("Server start failed:", error);
      process.exit(1);
    }
  }

  // Graceful shutdown
  async shutdown() {
    console.log("Shutting down gracefully...");

    if (this.db) {
      await this.db.end();
      console.log("Database connections closed");
    }

    process.exit(0);
  }
}

// Initialize and start server
const server = new VoteOperatorServer();
server.start();

// Handle graceful shutdown
process.on("SIGTERM", () => server.shutdown());
process.on("SIGINT", () => server.shutdown());

module.exports = server;
