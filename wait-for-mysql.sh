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

while [ $attempt -lt $max_attempts ]; do
  attempt=$((attempt + 1))
  
  echo "🔄 MySQL connection attempt $attempt/$max_attempts..."
  
  # Try connecting and capture the error output
  error_output=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" --connect-timeout=5 --skip-ssl --default-auth=mysql_native_password -e "SELECT 1" 2>&1)
  
  if [ $? -eq 0 ]; then
    echo "✅ MySQL connection successful!"
    break
  else
    echo "❌ MySQL connection failed (attempt $attempt/$max_attempts)"
    echo "   Error: $error_output"
    
    if [ $attempt -ge $max_attempts ]; then
      echo "❌ MySQL failed to become available after $max_attempts attempts"
      echo "🔍 Final debug information:"
      echo "   DNS resolution test:"
      nslookup "$host" || echo "   DNS resolution failed for $host"
      echo "   Network connectivity test:"
      nc -z "$host" "$port" && echo "   Port is reachable" || echo "   Port is not reachable"
      exit 1
    fi
    
    echo "⏳ Waiting 3 seconds before retry..."
    sleep 3
  fi
done

echo "✅ MySQL is ready!"

# Test database connection
echo "🔍 Testing database connection to '$database'..."
db_test_output=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" --skip-ssl --default-auth=mysql_native_password -e "USE $database; SELECT 'Database connection successful' as status;" 2>&1)

if [ $? -eq 0 ]; then
  echo "✅ Database connection verified!"
  echo "   Output: $db_test_output"
else
  echo "❌ Database connection failed!"
  echo "   Error: $db_test_output"
  echo "🔍 Attempting to create database if it doesn't exist..."
  
  # Try to create the database if it doesn't exist
  create_output=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" --skip-ssl --default-auth=mysql_native_password -e "CREATE DATABASE IF NOT EXISTS $database;" 2>&1)
  
  if [ $? -eq 0 ]; then
    echo "✅ Database created/verified successfully!"
    echo "   Output: $create_output"
  else
    echo "❌ Failed to create database!"
    echo "   Error: $create_output"
    exit 1
  fi
fi

echo "🚀 Starting Vote Operator application..."
exec node index.js
