# Use official Node.js runtime as base image
FROM node:18-alpine AS base

# Install mysql-client for the wait script and netcat for network testing
RUN apk add --no-cache mysql-client netcat-openbsd

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S voteoperator -u 1001

# Copy package files first for better layer caching
COPY package*.json ./

# Check if yarn.lock exists and install accordingly
COPY yarn.lock* ./

# Install dependencies
# If yarn.lock exists, use yarn; otherwise use npm
RUN if [ -f yarn.lock ]; then \
      yarn install --frozen-lockfile --production && yarn cache clean; \
    else \
      npm ci --omit=dev && npm cache clean --force; \
    fi

# Copy application code
COPY . .

# Make wait script executable
RUN chmod +x wait-for-mysql.sh

# Change ownership to non-root user
RUN chown -R voteoperator:nodejs /app
USER voteoperator

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e " \
    const http = require('http'); \
    const options = { hostname: 'localhost', port: 3000, path: '/', timeout: 3000 }; \
    const req = http.request(options, (res) => { \
      process.exit(res.statusCode === 200 ? 0 : 1); \
    }); \
    req.on('error', () => process.exit(1)); \
    req.on('timeout', () => process.exit(1)); \
    req.end(); \
  "

# Start the application
CMD ["./wait-for-mysql.sh"]
