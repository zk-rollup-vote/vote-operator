-- Initialize vote_operator database

USE vote_operator;

-- Create votes table with proper indexes
CREATE TABLE IF NOT EXISTS votes (
  id VARCHAR(66) PRIMARY KEY,
  data LONGTEXT NOT NULL,
  signature VARCHAR(132) NOT NULL,
  signer VARCHAR(42),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_created_at (created_at),
  INDEX idx_signer (signer)
);

-- Create a user with limited privileges (optional)
-- This is handled by environment variables in docker-compose
