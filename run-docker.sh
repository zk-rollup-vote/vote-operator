#!/bin/bash

echo "🐳 Building Vote Operator Docker image..."
docker build -t vote-operator .

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    echo "🚀 Starting Vote Operator container..."
    docker run -d \
        --name vote-operator \
        -p 3000:3000 \
        --env-file .env \
        vote-operator
    
    if [ $? -eq 0 ]; then
        echo "✅ Container started successfully!"
        echo "📡 Server should be available at: http://localhost:3000"
        echo "🔍 Check container status: docker ps"
        echo "📋 View logs: docker logs vote-operator"
        echo "🛑 Stop container: docker stop vote-operator"
    else
        echo "❌ Failed to start container"
    fi
else
    echo "❌ Build failed"
fi
