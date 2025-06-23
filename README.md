# Vote Operator Server

A secure blockchain voting server that stores vote data with cryptographic signatures using Ethereum-compatible keys.

## 🚀 Features

- **Cryptographic Signatures**: Each vote is signed with an Ethereum private key
- **Secure Storage**: Vote data stored in MySQL with unique hash IDs
- **Rate Limiting**: Protection against spam and abuse
- **Input Validation**: Comprehensive data validation
- **Error Handling**: Proper error responses with error codes
- **Health Monitoring**: Built-in health check endpoint
- **Graceful Shutdown**: Clean database connection handling
- **Security Headers**: Helmet.js for security best practices
- **CORS Support**: Cross-origin resource sharing enabled

## 📋 Prerequisites

- Node.js >= 16.0.0
- MySQL 5.7+ or 8.0+
- npm or yarn

## 🛠️ Installation

### Local Development

1. Clone the repository
2. Install dependencies:

```bash
npm install
```

3. Copy environment configuration:

```bash
cp env.example .env
```

4. Update `.env` with your configuration:

```env
# Server Configuration
PORT=3000

# Database Configuration
DB_HOST=localhost
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_DATABASE=vote_operator
DB_PORT=3306

# Operator Configuration (32-byte hex private key)
OPERATOR_PRIVATE_KEY=0x123..
```

### Docker Deployment

1. **Install Docker and Docker Compose** (Ubuntu 22.04):

```bash
sudo apt update && sudo apt upgrade -y && \
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo apt update && \
sudo apt install -y docker-ce docker-ce-cli containerd.io && \
sudo curl -L "https://github.com/docker/compose/releases/download/2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
sudo chmod +x /usr/local/bin/docker-compose && \
docker-compose --version
```

2. **Create environment file**:

```bash
cp env.example .env
```

3. **Edit your environment variables**:

```bash
nano .env  # or use your preferred editor
```

4. **Run the deployment script**:

```bash
sudo sh ./run-docker.sh
```

## 🚀 Usage

### Development

```bash
npm run dev
```

### Production

```bash
npm start
```

### Docker

```bash
# Build and run
docker build -t vote-operator .
docker run -p 3000:3000 --env-file .env vote-operator

# View logs
docker logs vote-operator

# Stop container
docker stop vote-operator
```

## 📡 API Endpoints

### Health Check

```http
GET /
```

**Response:**

```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "version": "1.0.0",
  "operator": "0x742d35Cc6634C0532925a3b8D4ff1e0E7C6EF9b8"
}
```

### Create Vote

```http
POST /votes
Content-Type: application/json

{
  "data": {
    "proposal_id": "prop_123",
    "voter_address": "0x742d35Cc6634C0532925a3b8D4ff1e0E7C6EF9b8",
    "choice": "yes",
    "timestamp": 1640995200
  }
}
```

**Response:**

```json
{
  "success": true,
  "message": "Vote saved successfully",
  "data": {
    "id": "0x8a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a",
    "signature": "0x1234567890abcdef...",
    "operator": "0x742d35Cc6634C0532925a3b8D4ff1e0E7C6EF9b8"
  }
}
```

### Get Vote by ID

```http
GET /votes/{id}
```

**Response:**

```json
{
  "success": true,
  "data": {
    "id": "0x8a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a",
    "data": {
      "proposal_id": "prop_123",
      "voter_address": "0x742d35Cc6634C0532925a3b8D4ff1e0E7C6EF9b8",
      "choice": "yes",
      "timestamp": 1640995200
    },
    "signature": "0x1234567890abcdef...",
    "createdAt": "2024-01-01T00:00:00.000Z"
  }
}
```

### List Votes

```http
GET /votes?limit=10&offset=0
```

**Response:**

```json
{
  "success": true,
  "data": [
    {
      "id": "0x8a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a",
      "created_at": "2024-01-01T00:00:00.000Z"
    }
  ],
  "pagination": {
    "limit": 10,
    "offset": 0,
    "count": 1
  }
}
```

## 🔐 Security Features

- **Rate Limiting**: 100 requests per minute per IP
- **Input Validation**: Data type and size validation
- **Security Headers**: Helmet.js protection
- **Error Codes**: Structured error responses
- **SQL Injection Protection**: Parameterized queries

## 📊 Error Codes

| Code                | Description                        |
| ------------------- | ---------------------------------- |
| `MISSING_DATA`      | Required data field is missing     |
| `INVALID_DATA_TYPE` | Data must be an object             |
| `DATA_TOO_LARGE`    | Data exceeds 1MB limit             |
| `DUPLICATE_VOTE`    | Vote with same data already exists |
| `INVALID_ID`        | Invalid vote ID format             |
| `VOTE_NOT_FOUND`    | Vote not found                     |
| `NOT_FOUND`         | Endpoint not found                 |
| `INVALID_JSON`      | Invalid JSON in request            |
| `INTERNAL_ERROR`    | Internal server error              |

## 🛡️ Rate Limiting

- **Limit**: 100 requests per minute per IP address
- **Response**: 429 Too Many Requests

## 🗄️ Database Schema

```sql
CREATE TABLE votes (
  id VARCHAR(66) PRIMARY KEY,
  data LONGTEXT NOT NULL,
  signature VARCHAR(132) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_created_at (created_at)
);
```

## 🔧 Configuration

### Environment Variables

| Variable               | Description                         | Required           |
| ---------------------- | ----------------------------------- | ------------------ |
| `PORT`                 | Server port                         | No (default: 3000) |
| `DB_HOST`              | Database host                       | Yes                |
| `DB_USER`              | Database user                       | Yes                |
| `DB_PASSWORD`          | Database password                   | Yes                |
| `DB_DATABASE`          | Database name                       | Yes                |
| `DB_PORT`              | Database port                       | No (default: 3306) |
| `OPERATOR_PRIVATE_KEY` | Ethereum private key (32 bytes hex) | Yes                |

### Performance Tuning

- **Connection Pool**: 10 concurrent connections
- **Request Timeout**: 30 seconds
- **Body Limit**: 10MB
- **Data Size Limit**: 1MB per vote

## 🧪 Testing

```bash
# Run tests
npm test

# Test health endpoint
curl http://localhost:3000/

# Test vote creation
curl -X POST http://localhost:3000/votes \
  -H "Content-Type: application/json" \
  -d '{"data":{"test":"vote"}}'
```

## 📝 Improvements Made

### From Original Code:

1. **Class-based Architecture**: Better organization and maintainability
2. **Async/Await**: Consistent async patterns throughout
3. **Error Handling**: Comprehensive error handling with proper status codes
4. **Security**: Rate limiting, CORS, Helmet, input validation
5. **Database**: Upgraded to mysql2 with connection pooling
6. **Validation**: Input validation middleware
7. **Logging**: Better logging with timestamps
8. **Graceful Shutdown**: Proper cleanup on exit
9. **Documentation**: Comprehensive API documentation
10. **Response Format**: Consistent JSON response structure

## 🚨 Important Notes

- **Private Key Security**: Never commit your private key to version control
- **Database Security**: Use strong passwords and limit database access
- **SSL/TLS**: Use HTTPS in production
- **Monitoring**: Set up proper monitoring and alerting
- **Backup**: Regular database backups recommended

## 📄 License

MIT License
