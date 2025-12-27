#!/bin/bash

# Deploy fix for infinite thinking state to Docker/ECS setup

echo "Deploying fix for AI thinking state to Docker..."

# Connect to EC2 and update the application
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 << 'EOF'
cd /var/www/shoppollama

# Pull latest changes
sudo git pull origin main

# Stop the containers
sudo docker-compose down

# Build and start with new code
sudo docker-compose up -d --build

echo "Waiting for services to start..."
sleep 10

# Check status
sudo docker-compose ps
EOF

echo "Fix deployed!"
