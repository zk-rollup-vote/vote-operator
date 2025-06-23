#!/bin/sh

# wait-for-mysql.sh - Wait for MySQL to be ready before starting the application

set -e

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
until mysql -h"$host" -P"$port" -u"$user" -p"$password" --skip-ssl -e "SELECT 1" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  echo "MySQL is unavailable (attempt $attempt/$max_attempts) - sleeping"
  
  if [ $attempt -ge $max_attempts ]; then
    echo "❌ MySQL failed to become available after $max_attempts attempts"
    echo "🔍 Debug information:"
    echo "   Checking if MySQL service is running..."
    nslookup "$host" || echo "   DNS resolution failed for $host"
    exit 1
  fi
  
  sleep 2
done

echo "✅ MySQL is ready!"

# Test database connection
echo "🔍 Testing database connection..."
mysql -h"$host" -P"$port" -u"$user" -p"$password" --skip-ssl -e "USE $database; SELECT 'Database connection successful' as status;"

if [ $? -eq 0 ]; then
  echo "✅ Database connection verified!"
else
  echo "❌ Database connection failed!"
  exit 1
fi

echo "🚀 Starting Vote Operator application..."
exec node index.js
