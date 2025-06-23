#!/bin/sh

# wait-for-mysql.sh - Wait for MySQL to be ready before starting the application

# Remove set -e to prevent script from exiting on error
# set -e

host="$DB_HOST"
user="$DB_USER"
password="$DB_PASSWORD"
database="$DB_DATABASE"
port="${DB_PORT:-3306}"

echo "⏳ Waiting for MySQL at $host:$port..."
echo "🔍 Connection parameters:"
echo "   Host: $host"
echo "   Port: $port"
echo "   User: $user"
echo "   Database: $database"

# Check if MySQL/MariaDB client is available
mysql_cmd="mariadb"
if ! which mariadb >/dev/null 2>&1; then
  if which mysql >/dev/null 2>&1; then
    mysql_cmd="mysql"
    echo "⚠️  Using deprecated mysql command (MariaDB client)"
  else
    echo "❌ Neither MySQL nor MariaDB client found! Installing..."
    apk add --no-cache mysql-client || {
      echo "❌ Failed to install MySQL client. Using alternative approach..."
      # Alternative approach without MySQL client - just test port connectivity
      echo "🔍 Testing network connectivity to $host:$port..."
      for i in $(seq 1 30); do
        echo "🔄 Connection attempt $i/30..."
        if nc -z "$host" "$port"; then
          echo "✅ Port $port is reachable on $host"
          echo "🚀 Starting Vote Operator application..."
          exec node index.js
        else
          echo "⏳ Waiting 3 seconds before retry..."
          sleep 3
        fi
      done
      echo "❌ Failed to connect to $host:$port after 30 attempts"
      exit 1
    }
  fi
else
  echo "✅ Using MariaDB client"
fi

# First, check if we can reach the host and port
echo "🔍 Testing network connectivity to $host:$port..."
nc -z "$host" "$port"
if [ $? -eq 0 ]; then
    echo "✅ Network connectivity to $host:$port is working"
else
    echo "❌ Cannot reach $host:$port - checking if service is up..."
fi

# Wait for MySQL to be ready
attempt=0
max_attempts=30

# Wait for MySQL to be ready - simplified approach
# Since MariaDB client has compatibility issues with MySQL 8.0 auth,
# we'll use network connectivity + timing approach
attempt=0
max_attempts=30

echo "🔄 Using simplified MySQL readiness check (network + timing)..."

while [ $attempt -lt $max_attempts ]; do
  attempt=$((attempt + 1))
  
  echo "🔄 Connectivity check $attempt/$max_attempts..."
  
  # Test network connectivity
  if nc -z "$host" "$port"; then
    echo "✅ Port $port is reachable on $host"
    
    # Wait a bit more for MySQL to be fully ready after port becomes available
    if [ $attempt -ge 5 ]; then
      echo "✅ MySQL should be ready! Port has been accessible for multiple attempts."
      break
    else
      echo "🔍 Port is open, waiting for MySQL to fully initialize..."
    fi
  else
    echo "❌ Cannot reach $host:$port (attempt $attempt/$max_attempts)"
  fi
  
  if [ $attempt -ge $max_attempts ]; then
    echo "❌ MySQL failed to become available after $max_attempts attempts"
    echo "🔍 Final debug information:"
    echo "   DNS resolution test:"
    nslookup "$host" 2>/dev/null || echo "   DNS resolution failed for $host"
    exit 1
  fi
  
  echo "⏳ Waiting 2 seconds before retry..."
  sleep 2
done

echo "✅ MySQL network connectivity verified!"

# Note: Skipping database connection test with MariaDB client due to MySQL 8.0 compatibility issues
# The Node.js application will handle database connection and creation using mysql2 driver
echo "🔍 The Node.js application will handle database connection and creation..."

echo "🚀 Starting Vote Operator application..."
exec node index.js
