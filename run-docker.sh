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

# Function to test network connectivity
test_network_connectivity() {
    echo "🔍 Testing network connectivity..."
    
    # Get host IP
    local host_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    
    echo "📍 Host IP detected: $host_ip"
    
    # Test if port is open on the host
    if command -v netstat >/dev/null 2>&1; then
        echo "🔌 Checking if port 3000 is bound on host:"
        netstat -tulpn 2>/dev/null | grep :3000 || echo "   No processes found listening on port 3000"
    fi
    
    # Test Docker port mapping
    echo "🐳 Docker port mappings:"
    docker port vote-operator 2>/dev/null || echo "   Could not retrieve port mappings"
    
    # Test connectivity from different angles
    echo "🧪 Testing connectivity:"
    
    # Test localhost
    if timeout 5 curl -s http://localhost:3000 >/dev/null 2>&1; then
        echo "   ✅ localhost:3000 - OK"
    else
        echo "   ❌ localhost:3000 - Failed"
    fi
    
    # Test 127.0.0.1
    if timeout 5 curl -s http://127.0.0.1:3000 >/dev/null 2>&1; then
        echo "   ✅ 127.0.0.1:3000 - OK"
    else
        echo "   ❌ 127.0.0.1:3000 - Failed"
    fi
    
    # Test host IP if different
    if [ "$host_ip" != "localhost" ] && [ "$host_ip" != "127.0.0.1" ]; then
        if timeout 5 curl -s http://$host_ip:3000 >/dev/null 2>&1; then
            echo "   ✅ $host_ip:3000 - OK"
        else
            echo "   ❌ $host_ip:3000 - Failed"
        fi
    fi
    
    # Test if we can reach the container directly
    local container_ip=$(docker inspect vote-operator --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    if [ -n "$container_ip" ] && [ "$container_ip" != "<no value>" ]; then
        echo "🐳 Container IP: $container_ip"
        if timeout 5 curl -s http://$container_ip:3000 >/dev/null 2>&1; then
            echo "   ✅ Direct container access - OK"
        else
            echo "   ❌ Direct container access - Failed"
        fi
    fi
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
        
        # Get the actual host IP for external access
        local host_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo "📡 Server should be available at:"
        echo "   • Local:    http://localhost:3000"
        echo "   • Network:  http://$host_ip:3000"
        
        # Check port binding
        echo "🔍 Checking port bindings..."
        docker port vote-operator 2>/dev/null || echo "⚠️  Could not get port info"
        
        # Wait a moment and test the health endpoint
        echo "🔍 Testing health endpoint in 10 seconds..."
        sleep 10
        
        # Test localhost first
        if curl -s http://localhost:3000 >/dev/null 2>&1; then
            echo "✅ Local health check passed!"
        else
            echo "⚠️  Local health check failed - container may still be starting"
        fi
        
        # Test network access if different from localhost
        if [ "$host_ip" != "localhost" ] && [ "$host_ip" != "127.0.0.1" ]; then
            echo "🔍 Testing network accessibility..."
            if timeout 5 bash -c "curl -s http://$host_ip:3000" >/dev/null 2>&1; then
                echo "✅ Network health check passed!"
            else
                echo "⚠️  Network health check failed"
                echo "💡 This might be due to:"
                echo "   • Firewall blocking port 3000"
                echo "   • Docker not binding to external interface"
                echo "   • Network configuration issues"
            fi
        fi
        
        # Show network diagnostics
        echo ""
        echo "🌐 Network diagnostics:"
        echo "   • Container IP: $(docker inspect vote-operator --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo 'unknown')"
        echo "   • Host IP: $host_ip"
        echo "   • Listening processes in container:"
        docker exec vote-operator netstat -tulpn 2>/dev/null | grep :3000 || echo "     No netstat available in container"
        
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
docker compose up -d --build

if [ $? -eq 0 ]; then
    echo "✅ Services started successfully!"
    
    # Wait a bit for containers to start
    echo "⏳ Waiting for services to initialize..."
    sleep 5
    
    check_container_status
    
    # Run network connectivity tests
    echo ""
    test_network_connectivity
else
    echo "❌ Failed to start services"
    echo "📋 Checking logs for errors..."
    show_logs
    exit 1
fi

echo ""
echo "🔧 Useful commands:"
echo "  Check status:     docker compose ps"
echo "  View logs:        docker compose logs"
echo "  Follow logs:      docker compose logs -f"
echo "  Stop services:    docker compose down"
echo "  Restart:          docker compose restart"
echo "  Rebuild:          docker compose up -d --build"
echo ""
echo "🌐 Network troubleshooting:"
echo "  Check port:       netstat -tulpn | grep :3000"
echo "  Test local:       curl http://localhost:3000"
echo "  Test network:     curl http://$(hostname -I | awk '{print $1}'):3000"
echo "  Container shell:  docker exec -it vote-operator sh"
echo "  Container logs:   docker logs vote-operator"
echo ""
echo "🔥 If external access fails, try:"
echo "  1. Check firewall: sudo ufw status (Linux) or Windows Firewall"
echo "  2. Verify Docker daemon binding: docker info | grep 'Docker Root Dir'"
echo "  3. Test with telnet: telnet <your-ip> 3000"
