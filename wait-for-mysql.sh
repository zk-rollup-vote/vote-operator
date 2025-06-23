#!/bin/sh

# wait-for-mysql.sh - Wait for MySQL to be ready before starting the application

set -e

host="$DB_HOST"
user="$DB_USER"
password="$DB_PASSWORD"
database="$DB_DATABASE"
port="${DB_PORT:-3306}"

echo "⏳ Waiting for MySQL at $host:$port..."

# Wait for MySQL to be ready
until mysql -h"$host" -P"$port" -u"$user" -p"$password" --skip-ssl -e "SELECT 1" >/dev/null 2>&1; do
  echo "MySQL is unavailable - sleeping"
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
