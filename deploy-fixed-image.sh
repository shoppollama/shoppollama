#!/bin/bash

# Build and deploy updated Docker image with timeout fixes

echo "Building updated Docker image with thinking timeout fixes..."

# Connect to EC2 and build new image
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 << 'EOF'
cd /var/www/shoppollama

# Pull latest code with fixes
sudo git pull origin main

# Build new Docker image
sudo docker build -t shoppollama:fixed .

# Stop current containers
sudo docker-compose down

# Update docker-compose.yml to use new image
sudo sed -i 's|279714322890.dkr.ecr.us-east-1.amazonaws.com/shoppollama:local-20251227-2055|shoppollama:fixed|' docker-compose.yml

# Start with new image
sudo /usr/local/bin/docker-compose up -d

echo "Deployment with new image complete!"
EOF

echo "Fixed image deployed successfully!"
