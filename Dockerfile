# Use official Node.js runtime as base image
FROM node:18-alpine AS base

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

# Change ownership to non-root user
RUN chown -R voteoperator:nodejs /app
USER voteoperator

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# Start the application
CMD ["npm", "start"]
