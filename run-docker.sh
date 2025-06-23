#!/bin/bash

# Function to check if .env file exists and has required variables
check_env_file() {
    if [ ! -f ".env" ]; then
        echo "❌ .env file not found! Creating from env.example..."
        if [ -f "env.example" ]; then
            cp env.example .env
            echo "⚠️  Please edit .env file with your actual database credentials and private key"
            echo "📝 Required variables: DB_HOST, DB_USER, DB_PASSWORD, DB_DATABASE, OPERATOR_PRIVATE_KEY"
            return 1
        else
            echo "❌ env.example file not found either!"
            return 1
        fi
    fi
    
    # Check if critical variables are set (not just placeholders)
    if grep -q "your_db_user\|your_db_password\|0x1234567890abcdef" .env; then
        echo "⚠️  Warning: .env file contains placeholder values!"
        echo "📝 Please update DB_USER, DB_PASSWORD, and OPERATOR_PRIVATE_KEY in .env"
        echo "🔍 Current .env content:"
        cat .env
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

# Function to clean up existing containers
cleanup_container() {
    echo "🧹 Stopping and removing existing containers..."
    docker-compose down 2>/dev/null || true
    
    # Also clean up any standalone containers
    if docker ps -a --format "table {{.Names}}" | grep -q "^vote-operator$"; then
        docker stop vote-operator 2>/dev/null
        docker rm vote-operator 2>/dev/null
    fi
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^vote-operator-db$"; then
        docker stop vote-operator-db 2>/dev/null
        docker rm vote-operator-db 2>/dev/null
    fi
}

# Function to show container logs
show_logs() {
    echo "📋 Vote Operator logs:"
    docker-compose logs vote-operator 2>&1
    echo ""
    echo "📋 Database logs:"
    docker-compose logs mysql 2>&1
    echo ""
}

# Function to check container status
check_container_status() {
    local app_container_id=$(docker ps -q -f name=vote-operator)
    local db_container_id=$(docker ps -q -f name=vote-operator-db)
    
    if [ -n "$db_container_id" ]; then
        echo "✅ Database container is running (ID: $db_container_id)"
    else
        echo "❌ Database container is not running"
        return 1
    fi
    
    if [ -n "$app_container_id" ]; then
        echo "✅ Vote Operator container is running (ID: $app_container_id)"
        echo "📡 Server should be available at: http://localhost:3000"
        
        # Wait a moment and test the health endpoint
        echo "🔍 Testing health endpoint in 10 seconds..."
        sleep 10
        if curl -s http://localhost:3000 >/dev/null 2>&1; then
            echo "✅ Health check passed!"
        else
            echo "⚠️  Health check failed - container may still be starting"
            show_logs
        fi
    else
        echo "❌ Vote Operator container is not running"
        
        # Check if containers exist but stopped
        if docker ps -a -q -f name=vote-operator >/dev/null 2>&1; then
            echo "🔍 Containers exist but stopped. Checking logs..."
            show_logs
            
            # Show container status
            echo "📊 Container status:"
            docker-compose ps
        fi
        return 1
    fi
}

echo "🚀 Vote Operator Docker Deployment"
echo "=================================="

# Check environment file
if ! check_env_file; then
    exit 1
fi

# Clean up any existing containers
cleanup_container

echo "🐳 Starting Vote Operator with Docker Compose..."
docker-compose up -d --build

if [ $? -eq 0 ]; then
    echo "✅ Services started successfully!"
    
    # Wait a bit for containers to start
    echo "⏳ Waiting for services to initialize..."
    sleep 5
    
    check_container_status
else
    echo "❌ Failed to start services"
    echo "📋 Checking logs for errors..."
    show_logs
    exit 1
fi

echo ""
echo "🔧 Useful commands:"
echo "  Check status:     docker-compose ps"
echo "  View logs:        docker-compose logs"
echo "  Follow logs:      docker-compose logs -f"
echo "  Stop services:    docker-compose down"
echo "  Restart:          docker-compose restart"
echo "  Rebuild:          docker-compose up -d --build"
